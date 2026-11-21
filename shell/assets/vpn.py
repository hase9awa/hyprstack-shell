#!/usr/bin/env python3
"""On-demand controls for upstream sing-box and Xray. No resident manager.

Only the selected core runs while connected. Imports use stdin, profile files
are private, and the shell never receives server credentials or native configs.
"""
from __future__ import annotations

import argparse
import base64
import copy
from concurrent.futures import ThreadPoolExecutor
import errno
import fcntl
import hashlib
import hmac
import http.client
import json
import os
from pathlib import Path
import pwd
import re
import secrets
import shutil
import socket
import ssl
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.parse
import urllib.error
import urllib.request
import zipfile

from vpn_profiles import parse, ProfileError

DATA = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'hyprstack'
ROOT = Path(os.environ.get('HYPRSTACK_VPN_STATE', DATA / 'vpn'))
RUNTIME = Path(os.environ.get('HYPRSTACK_VPN_RUNTIME', DATA / 'runtime/vpn/cores'))
PRIVILEGED = Path('/usr/local/lib/hyprstack-vpn')
DNS_RULE = Path(f'/etc/polkit-1/rules.d/49-hyprstack-vpn-{os.getuid()}.rules')
SERVICE = 'hyprstack-vpn.service'
MAX_IMPORT = 8 * 1024 * 1024
CAPS = (1 << 10) | (1 << 12) | (1 << 13)  # bind_service, net_admin, net_raw
RELEASES = {
    'sing-box': ('1.14.4', 'https://github.com/SagerNet/sing-box/releases/download/v1.14.4/', {
        'x86_64': ('sing-box-1.14.4-linux-amd64.tar.gz', '699a1b510aa4396b2176d32d1181920399ebf1e267835da6f3b598d0f7c24968'),
        'aarch64': ('sing-box-1.14.4-linux-arm64.tar.gz', '436441f76ee2f7fe21b5b2d426d3cb261a480455a704865789ad533e4273ec26')}),
    'xray': ('26.10.21', 'https://github.com/XTLS/Xray-core/releases/download/v26.10.21/', {
        'x86_64': ('Xray-linux-64.zip', '0eec3ed4163c273d8c8bf821f7d219e257921cf584aa3fb970715e458e631978'),
        'aarch64': ('Xray-linux-arm64-v8a.zip', 'd1304946c486d98e6b886e9b931eaaaebb23835b30e217638037b7f2721d4e9c')})}
# CGO variants include Cronet in the executable, including when installed with
# network capabilities. The existing purego core is upgraded on first Naive use.
NAIVE_RELEASES = {
    'x86_64': ('sing-box-1.14.4-linux-amd64-glibc.tar.gz', '231e57c18378f780a08de832844a1ca9716e17a7bcf82964b350844d243c03ac'),
    'aarch64': ('sing-box-1.14.4-linux-arm64-glibc.tar.gz', '241cb4ccbf1a003235f8a969cc25d28cc74487df52721f6de28be7e37eae2ae9')}


class VpnError(Exception):
    pass


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temp = path.with_name(path.name + '.' + secrets.token_hex(4))
    descriptor = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, 'w') as output:
            json.dump(value, output, ensure_ascii=False)
            output.write('\n')
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def read_json(path, default=None):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return default


def model():
    value = read_json(ROOT / 'profiles.json', {'profiles': [], 'groups': [], 'selectedProfile': -1,
                                               'mode': 'tun', 'route': 'all'})
    value.setdefault('sendHwid', False)
    value.setdefault('userAgent', '')
    return value


def selected(value):
    profile = next((p for p in value['profiles'] if p['id'] == value['selectedProfile']), None)
    if profile is None:
        raise VpnError('Add or select a VPN profile first')
    return profile


def can_tun(path):
    try:
        stat = path.stat()
        caps = struct.unpack_from('<III', os.getxattr(path, 'security.capability'))
        return bool(stat.st_uid == 0 and not stat.st_mode & 0o022 and caps[0] & 1 and caps[1] & CAPS == CAPS)
    except (OSError, struct.error):
        return False


def tun_error():
    try:
        descriptor = os.open('/dev/net/tun', os.O_RDWR | os.O_CLOEXEC)
        os.close(descriptor)
    except OSError as error:
        if error.errno in (errno.ENODEV, errno.ENXIO, errno.ENOENT):
            if not Path('/usr/lib/modules', os.uname().release).is_dir():
                return 'The running kernel has no TUN module. Restart the system to finish the kernel update.'
            return 'The TUN device is unavailable. Enable TUN support before connecting.'
    return ''


def proxy_ports(previous):
    """Keep both chosen ports reserved until allocation is complete."""
    reservations = []
    result = {}
    try:
        for key, default in (('socksPort', 2080), ('httpPort', 2081)):
            preferred = previous.get(key, default)
            for attempt in range(16):
                tcp, udp = socket.socket(), None
                try:
                    tcp.bind(('127.0.0.1', preferred if attempt == 0 else 0))
                    port = tcp.getsockname()[1]
                    if key == 'socksPort':
                        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                        udp.bind(('127.0.0.1', port))
                except OSError as error:
                    tcp.close()
                    if udp is not None:
                        udp.close()
                    if error.errno != errno.EADDRINUSE:
                        raise VpnError('No local port is available for the VPN proxy') from error
                    continue
                reservations.append(tcp)
                if udp is not None:
                    reservations.append(udp)
                result[key] = port
                break
            else:
                raise VpnError('No local port is available for the VPN proxy')
        return result
    finally:
        for reservation in reservations:
            reservation.close()


def dns_policy():
    user = json.dumps(pwd.getpwuid(os.getuid()).pw_name)
    return ('// Hyprstack: DNS changes for its own tunnel only.\n'
            'polkit.addRule(function(action, subject) {\n'
            f'    if (subject.user !== {user}) return;\n'
            '    if (action.id === "org.freedesktop.resolve1.flush-caches") return polkit.Result.YES;\n'
            '    if (action.lookup("interface") !== "hyprstack-vpn") return;\n'
            '    var allowed = ["org.freedesktop.resolve1.set-dns-servers",\n'
            '        "org.freedesktop.resolve1.set-domains", "org.freedesktop.resolve1.set-default-route",\n'
            '        "org.freedesktop.resolve1.revert"];\n'
            '    if (allowed.indexOf(action.id) !== -1) return polkit.Result.YES;\n'
            '});\n')


def dns_authorized():
    return read_json(ROOT / 'authorization.json', {}).get('dnsPolicy') == hashlib.sha256(dns_policy().encode()).hexdigest()


def binary(engine):
    local = RUNTIME / engine
    if local.is_file() and not local.is_symlink():
        return local
    privileged = PRIVILEGED / engine
    if can_tun(privileged):
        return privileged
    system = shutil.which(engine)
    return Path(system) if system else RUNTIME / engine


def required(value):
    return {'sing-box'} | {p['engine'] for p in value['profiles']}


def panel_version():
    path = Path(os.environ.get('HYPRSTACK_DATA_DIR', DATA)) / 'version.json'
    try:
        value = json.loads(path.read_text())
        version = str(value.get('version', '')).strip() if isinstance(value, dict) else ''
    except (OSError, ValueError):
        return 'dev'
    return version or 'dev'


def hwid():
    try:
        machine = Path('/etc/machine-id').read_text().strip()
    except OSError:
        return None
    if len(machine) != 32 or any(c not in '0123456789abcdef' for c in machine.lower()):
        return None
    return hmac.new(bytes.fromhex(machine), b'hyprstack/vpn/device-id/v1', hashlib.sha256).hexdigest()


class SubscriptionRedirectHandler(urllib.request.HTTPRedirectHandler):
    @staticmethod
    def origin(value):
        parsed = urllib.parse.urlsplit(value)
        return parsed.scheme.lower(), parsed.hostname, parsed.port or (443 if parsed.scheme == 'https' else 80)

    def redirect_request(self, request, fp, code, message, headers, new_url):
        redirected = super().redirect_request(request, fp, code, message, headers, new_url)
        if redirected is not None and self.origin(request.full_url) != self.origin(new_url):
            for key in list(redirected.headers):
                if key.lower() in ('x-hwid', 'hwid', 'x-device-os'):
                    redirected.remove_header(key)
        return redirected


def download(url, limit=MAX_IMPORT, subscription=False):
    headers = {'User-Agent': 'Hyprstack-VPN/1'}
    if subscription:
        settings = model()
        headers['User-Agent'] = str(settings['userAgent']).strip() or f'hyprstack/{panel_version()}'
        if settings['sendHwid']:
            identifier = hwid()
            if identifier:
                # X-HWID is what 3x-ui and Happ read; hwid covers generic servers.
                headers['X-HWID'] = identifier
                headers['hwid'] = identifier
                headers['X-Device-OS'] = 'Linux'
    request = urllib.request.Request(url, headers=headers)
    try:
        opener = urllib.request.build_opener(SubscriptionRedirectHandler()) if subscription else None
        with (opener.open(request, timeout=30) if opener else urllib.request.urlopen(request, timeout=30)) as response:
            content = response.read(limit + 1)
    except urllib.error.HTTPError as error:
        if not subscription:
            raise
        error.close()
        enabled = lambda key: error.headers.get(key, '').strip().lower() == 'true'
        if enabled('X-Hwid-Max-Devices-Reached') or enabled('X-Hwid-Limit'):
            raise VpnError('The subscription device limit has been reached') from error
        if enabled('X-Hwid-Not-Supported'):
            if not settings['sendHwid']:
                raise VpnError('Enable hardware ID in VPN settings to load this subscription') from error
            raise VpnError('The server requires a device identifier that this system cannot provide') from error
        raise VpnError('The subscription server refused the request') from error
    if len(content) > limit:
        raise VpnError('The download is too large')
    return content


def naive_runtime_ready(path):
    try:
        result = subprocess.run([str(path), 'version'], capture_output=True, text=True, timeout=5)
        return result.returncode == 0 and 'with_naive_outbound' in result.stdout and (
            'CGO: enabled' in result.stdout or (path.parent / 'libcronet.so').is_file())
    except (OSError, subprocess.TimeoutExpired):
        return False


def has_naive(value):
    return any(p['engine'] == 'sing-box' and p['type'] == 'naive' for p in value['profiles'])


def install(engine, *, naive=False):
    if binary(engine).is_file() and (not naive or naive_runtime_ready(binary(engine))):
        return
    version, prefix, platforms = RELEASES[engine]
    asset = (NAIVE_RELEASES if naive else platforms).get(os.uname().machine)
    if not asset:
        raise VpnError('Install the VPN core using your package manager')
    filename, checksum = asset
    RUNTIME.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.install-', dir=RUNTIME) as temporary:
        archive = Path(temporary) / filename
        archive.write_bytes(download(prefix + filename, 128 * 1024 * 1024))
        if hashlib.sha256(archive.read_bytes()).hexdigest() != checksum:
            raise VpnError('The VPN core download did not pass verification')
        target = Path(temporary) / engine
        if engine == 'xray':
            with zipfile.ZipFile(archive) as files, files.open('xray') as source, target.open('wb') as output:
                shutil.copyfileobj(source, output)
        else:
            with tarfile.open(archive) as files:
                entry = next(e for e in files.getmembers() if e.isfile() and e.name.endswith('/sing-box'))
                with files.extractfile(entry) as source, target.open('wb') as output:
                    shutil.copyfileobj(source, output)
        os.chmod(target, 0o755)
        os.replace(target, RUNTIME / engine)


def routing_rules():
    cache = ROOT / 'rules.json'
    if cache.exists() and time.time() - cache.stat().st_mtime < 86400:
        return read_json(cache)
    install('sing-box')
    result = {}
    try:
        with tempfile.TemporaryDirectory(prefix='.rules-', dir=ROOT) as temporary:
            for name in ('geoip-ru', 'geosite-category-ru', 'geosite-ru-available-only-inside'):
                directory = 'rule-set-geoip' if name.startswith('geoip-') else 'rule-set-geosite'
                url = 'https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/' + directory + '/' + name + '.srs'
                source, dest = Path(temporary) / (name + '.srs'), Path(temporary) / (name + '.json')
                source.write_bytes(download(url))
                completed = subprocess.run([str(binary('sing-box')), 'rule-set', 'decompile', '--output', str(dest), str(source)], capture_output=True, timeout=20)
                if completed.returncode:
                    raise VpnError('Unable to update routing rules')
                for rule in read_json(dest)['rules']:
                    if any(k not in ('domain', 'domain_suffix', 'domain_keyword', 'domain_regex', 'ip_cidr') for k in rule):
                        raise VpnError('Unsupported routing rule format')
                    for key, values in rule.items():
                        result.setdefault(key, []).extend(values)
        result.setdefault('domain_suffix', []).extend(['ru', 'xn--p1ai'])
        result = {k: sorted(set(v)) for k, v in result.items()}
        atomic_json(cache, result)
        return result
    except Exception:
        if cache.exists():
            return read_json(cache)
        raise VpnError('Unable to update routing rules') from None


def direct_ipv6_available(routes_path=Path('/proc/net/ipv6_route')):
    """Ignore the VPN's own IPv6 route when checking the underlying connection."""
    try:
        for line in routes_path.read_text().splitlines():
            fields = line.split()
            if len(fields) < 10 or fields[0] != '0' * 32 or fields[1] != '00':
                continue
            flags = int(fields[-2], 16)
            if fields[-1] not in ('lo', 'hyprstack-vpn') and flags & 1 and not flags & 0x200:
                return True
    except OSError:
        pass
    return False


def configuration(profile, mode='proxy', route='all', port=2080, http_port=2081):
    outbound = copy.deepcopy(profile['outbound'])
    outbound['tag'] = 'vpn'
    private = ['127.0.0.0/8', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '169.254.0.0/16', '::1/128', 'fc00::/7', 'fe80::/10']
    bypass = routing_rules() if route == 'bypass-ru' else {}
    ipv4_only = not direct_ipv6_available()
    ipv4_bypass = bool(bypass) and ipv4_only
    if profile['engine'] == 'sing-box':
        inbounds = [{'type': 'socks', 'tag': 'socks', 'listen': '127.0.0.1', 'listen_port': port}]
        if http_port:
            inbounds.append({'type': 'http', 'tag': 'http', 'listen': '127.0.0.1', 'listen_port': http_port})
        if mode == 'tun':
            inbounds.append({'type': 'tun', 'tag': 'tun', 'interface_name': 'hyprstack-vpn',
                             'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'], 'mtu': 1500,
                             'auto_route': True, 'auto_redirect': True, 'strict_route': True, 'stack': 'mixed'})
        rules = [{'action': 'sniff'}, {'protocol': 'dns', 'action': 'hijack-dns'}, {'ip_cidr': private, 'outbound': 'direct'}]
        direct = {'type': 'direct', 'tag': 'direct'}
        dns_rules = []
        if ipv4_bypass:
            # A TUN can acknowledge IPv6 TCP before the direct dial fails. That
            # prevents browsers from falling back to IPv4 after TLS resets.
            direct['domain_resolver'] = {'server': 'bootstrap', 'strategy': 'ipv4_only'}
            rules.append({'ip_version': 6, 'outbound': 'vpn'})
            dns_rules = [{key: values, 'query_type': ['AAAA'], 'action': 'predefined', 'rcode': 'NOERROR'}
                         for key, values in bypass.items() if key != 'ip_cidr']
        for key, values in bypass.items():
            rules.append({key: values, 'outbound': 'direct'})
        return {'log': {'level': 'warn', 'timestamp': False}, 'inbounds': inbounds,
                'outbounds': [outbound, direct],
                'dns': {'servers': [{'type': 'https', 'tag': 'remote', 'server': '1.1.1.1', 'detour': 'vpn'},
                                    {'type': 'udp', 'tag': 'bootstrap', 'server': '1.1.1.1'}], 'final': 'remote', 'rules': dns_rules},
                'route': {'auto_detect_interface': True, 'default_domain_resolver': 'bootstrap', 'rules': rules, 'final': 'vpn'}}
    inbounds = [{'tag': 'socks', 'listen': '127.0.0.1', 'port': port, 'protocol': 'socks', 'settings': {'auth': 'noauth', 'udp': True}}]
    if http_port:
        inbounds.append({'tag': 'http', 'listen': '127.0.0.1', 'port': http_port, 'protocol': 'http'})
    if mode == 'tun':
        inbounds.append({'tag': 'tun', 'protocol': 'tun', 'settings': {'name': 'hyprstack-vpn', 'mtu': 1500,
                         'gateway': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
                         'autoSystemRoutingTable': ['0.0.0.0/0', '::/0'], 'autoOutboundsInterface': 'auto',
                         'autoSystemDnsToGateway': True},
                         'sniffing': {'enabled': True, 'destOverride': ['http', 'tls', 'quic'], 'routeOnly': True}})
    rules = [{'type': 'field', 'inboundTag': ['tun'], 'port': 53, 'outboundTag': 'dns'},
             {'type': 'field', 'ip': private, 'outboundTag': 'direct'}]
    direct = {'tag': 'direct', 'protocol': 'freedom'}
    if ipv4_bypass:
        direct['settings'] = {'domainStrategy': 'UseIPv4'}
        rules.append({'type': 'field', 'ip': ['::/0'], 'outboundTag': 'vpn'})
    domains = []
    for key, prefix in (('domain', 'full:'), ('domain_suffix', 'domain:'), ('domain_keyword', 'keyword:'), ('domain_regex', 'regexp:')):
        domains.extend(prefix + text for text in bypass.get(key, []))
    if domains:
        rules.append({'type': 'field', 'domain': domains, 'outboundTag': 'direct'})
    if bypass.get('ip_cidr'):
        rules.append({'type': 'field', 'ip': bypass['ip_cidr'], 'outboundTag': 'direct'})
    dns_servers = ['https://1.1.1.1/dns-query']
    if ipv4_bypass and domains:
        dns_servers.insert(0, {'address': dns_servers[0], 'domains': domains, 'queryStrategy': 'UseIPv4', 'skipFallback': True})
    return {'log': {'loglevel': 'warning'}, 'inbounds': inbounds,
            'outbounds': [outbound, direct, {'tag': 'dns', 'protocol': 'dns'}],
            'dns': {'servers': dns_servers, 'queryStrategy': 'UseIPv4' if ipv4_only else 'UseIP'},
            'routing': {'domainStrategy': 'IPIfNonMatch', 'rules': rules}}


def command(engine, config, check=False):
    args = [str(binary(engine))]
    return (args + (['check'] if check else ['run']) + ['-c', str(config)] if engine == 'sing-box'
            else args + ['run'] + (['-test'] if check else []) + ['-config', str(config)])


def validate(profile):
    install(profile['engine'], naive=profile['engine'] == 'sing-box' and profile['type'] == 'naive')
    with tempfile.TemporaryDirectory(prefix='.check-', dir=ROOT) as temporary:
        path = Path(temporary) / 'config.json'
        atomic_json(path, configuration(profile, http_port=0))
        result = subprocess.run(command(profile['engine'], path, True), capture_output=True, timeout=15)
        if result.returncode:
            raise VpnError('The profile configuration is invalid or unsupported')


def proc_start(pid):
    return Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[19]


def connection_status():
    session = read_json(ROOT / 'process.json', {})
    alive = False
    try:
        alive = proc_start(session['pid']) == session['start']
        os.kill(session['pid'], 0)
    except (OSError, KeyError):
        alive = False
    connected = alive and (session.get('mode') == 'proxy' or Path('/sys/class/net/hyprstack-vpn').exists())
    return {'connected': bool(connected), 'state': 'connected' if connected else 'disconnected',
            'reason': '', 'authUrl': '', 'server': session.get('name', '') if connected else '',
            'coreRunning': alive, 'engine': session.get('engine', '') if connected else '',
            'socksPort': session.get('socksPort', 2080), 'httpPort': session.get('httpPort', 2081)}


def status(value=None):
    value = model() if value is None else value
    engines = {engine: binary(engine) for engine in required(value)}
    return {**connection_status(),
            'selectedProfile': value['selectedProfile'], 'mode': value['mode'],
            'installed': all(path.is_file() for path in engines.values()) and (
                not has_naive(value) or naive_runtime_ready(engines['sing-box'])),
            'canTun': all(can_tun(path) for path in engines.values()) and dns_authorized(),
            'tunError': tun_error(), 'engines': sorted(engines)}


def overview():
    value = model()
    countries = cached_locations(value['profiles'])
    return {**status(value), 'profiles': [{**{k: p[k] for k in ('id', 'name', 'type', 'group', 'latency_ms', 'engine')},
                                    'country': countries.get(p['id'], '')} for p in value['profiles']],
            'groups': [{k: g[k] for k in ('id', 'name', 'subscription')} for g in value['groups']],
            'sendHwid': value['sendHwid'], 'userAgent': value['userAgent'],
            'routes': [{'id': 'all', 'name': 'All traffic', 'active': value['route'] == 'all'},
                       {'id': 'bypass-ru', 'name': 'Bypass Russia', 'active': value['route'] == 'bypass-ru'}]}


def service(action):
    completed = subprocess.run(['systemctl', '--user', action, SERVICE], capture_output=True, timeout=30)
    if completed.returncode:
        load = subprocess.run(['systemctl', '--user', 'show', SERVICE, '-p', 'LoadState', '--value'], capture_output=True, text=True, timeout=5)
        if load.stdout.strip() == 'not-found':
            if action == 'stop':
                return
            result = subprocess.run(['systemd-run', '--user', '--collect', '--unit=hyprstack-vpn',
                                     '--property=Restart=on-failure', '--property=UMask=0077',
                                     f'--setenv=HYPRSTACK_VPN_STATE={ROOT}', f'--setenv=HYPRSTACK_VPN_RUNTIME={RUNTIME}',
                                     sys.executable, str(Path(__file__).resolve()), 'serve'], capture_output=True, timeout=15)
            if result.returncode == 0:
                return
        raise VpnError('The VPN service could not complete the operation')


def ready():
    current = connection_status()
    if not current['connected']:
        return False
    try:
        with socket.create_connection(('127.0.0.1', current['socksPort']), timeout=.5) as stream:
            stream.sendall(b'\x05\x01\x00')
            return stream.recv(2) == b'\x05\x00'
    except OSError:
        return False


def connect(value=None):
    value = value or model()
    profile = selected(value)
    if profile['engine'] == 'sing-box' and profile['type'] == 'naive':
        install('sing-box', naive=True)
    if not binary(profile['engine']).is_file():
        raise VpnError('The VPN core is not installed')
    if value['mode'] == 'tun' and (not can_tun(binary(profile['engine'])) or not dns_authorized()):
        raise VpnError('Authorize the VPN tunnel in VPN settings first')
    if value['mode'] == 'tun' and (reason := tun_error()):
        raise VpnError(reason)
    old_config, old_session = read_json(ROOT / 'config.json'), read_json(ROOT / 'session.json')
    was_connected = status()['connected']
    ports = ({key: old_session.get(key, default) for key, default in (('socksPort', 2080), ('httpPort', 2081))}
             if was_connected and old_session else proxy_ports(old_session or {}))
    config = configuration(profile, value['mode'], value['route'], ports['socksPort'], ports['httpPort'])
    atomic_json(ROOT / 'pending.json', config)
    completed = subprocess.run(command(profile['engine'], ROOT / 'pending.json', True), capture_output=True, timeout=20)
    if completed.returncode:
        raise VpnError('The profile configuration is invalid or unsupported')
    os.replace(ROOT / 'pending.json', ROOT / 'config.json')
    atomic_json(ROOT / 'session.json', {k: profile[k] for k in ('id', 'name', 'type', 'engine')} | {'mode': value['mode']} | ports)
    try:
        service('restart')
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if ready():
                return
            time.sleep(.1)
        raise VpnError('The VPN tunnel did not start')
    except Exception:
        service('stop')
        if old_config is not None and old_session is not None:
            atomic_json(ROOT / 'config.json', old_config)
            atomic_json(ROOT / 'session.json', old_session)
            if was_connected:
                service('start')
        raise


def receive(stream, size):
    result = b''
    while len(result) < size:
        part = stream.recv(size - len(result))
        if not part:
            raise VpnError('The VPN server did not respond to the connection test')
        result += part
    return result


def latency(profile, *, location=False):
    if not location:
        validate(profile)
    with tempfile.TemporaryDirectory(prefix='.test-', dir=ROOT) as temporary:
        with socket.socket() as reservation:
            reservation.bind(('127.0.0.1', 0))
            port = reservation.getsockname()[1]
        path = Path(temporary) / 'config.json'
        atomic_json(path, configuration(profile, port=port, http_port=0))
        with (Path(temporary) / 'core.log').open('w') as log:
            process = subprocess.Popen(command(profile['engine'], path), stdout=log, stderr=log, umask=0o077)
            try:
                deadline = time.monotonic() + 5
                while True:
                    try:
                        stream = socket.create_connection(('127.0.0.1', port), timeout=.2)
                        break
                    except OSError:
                        if process.poll() is not None or time.monotonic() > deadline:
                            raise VpnError('The VPN core could not start the connection test')
                        time.sleep(.05)
                started = time.monotonic()
                with stream:
                    stream.settimeout(10)
                    stream.sendall(b'\x05\x01\x00')
                    if receive(stream, 2) != b'\x05\x00':
                        raise VpnError('The VPN connection test failed')
                    host = b'www.cloudflare.com' if location else b'www.gstatic.com'
                    stream.sendall(b'\x05\x01\x00\x03' + bytes([len(host)]) + host + struct.pack('>H', 443))
                    header = receive(stream, 4)
                    if header[1] != 0:
                        raise VpnError('The VPN server did not respond to the connection test')
                    receive(stream, {1: 4, 4: 16}.get(header[3], 0) or receive(stream, 1)[0])
                    receive(stream, 2)
                    with ssl.create_default_context().wrap_socket(stream, server_hostname=host.decode()) as secure:
                        if location:
                            secure.sendall(b'GET /cdn-cgi/trace HTTP/1.1\r\nHost: www.cloudflare.com\r\nConnection: close\r\n\r\n')
                            response = http.client.HTTPResponse(secure)
                            response.begin()
                            body = response.read(16384).decode('ascii', errors='replace')
                            country = re.search(r'^loc=([A-Z]{2})\s*$', body, re.MULTILINE)
                            return country[1] if response.status == 200 and country and country[1] not in ('XX', 'ZZ') else ''
                        secure.sendall(b'GET /generate_204 HTTP/1.1\r\nHost: www.gstatic.com\r\nConnection: close\r\n\r\n')
                        if b' 204 ' not in secure.recv(1024).split(b'\r\n', 1)[0]:
                            raise VpnError('The VPN connection test failed')
                return round((time.monotonic() - started) * 1000)
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def location_signature(profile):
    return hashlib.sha256(json.dumps(profile['outbound'], sort_keys=True).encode()).hexdigest()


def named_country(profile):
    flag = re.search(r'([\U0001f1e6-\U0001f1ff]{2})', profile.get('name', ''))
    return ''.join(chr(ord(letter) - 0x1f1e6 + 65) for letter in flag[1]) if flag else ''


def cached_locations(profiles):
    cached = read_json(ROOT / 'locations.json', {})
    if not isinstance(cached, dict):
        cached = {}
    result = {}
    for profile in profiles:
        entry = cached.get(profile['id'], {})
        if not isinstance(entry, dict):
            entry = {}
        country = named_country(profile)
        if not country and entry.get('signature') == location_signature(profile):
            country = entry.get('country', '')
        if re.fullmatch('[A-Z]{2}', country) and country not in ('XX', 'ZZ'):
            result[profile['id']] = country
    return result


def locations():
    """Cache the exit country through isolated proxies, without changing the VPN.

    Country names supplied as flags need no network lookup. Other profiles use
    Cloudflare's trace endpoint through that profile's own SOCKS/TLS connection;
    there is no direct-IP geolocation request or automatic core installation.
    """
    profiles = model()['profiles']
    cached = read_json(ROOT / 'locations.json', {})
    if not isinstance(cached, dict):
        cached = {}
    now = time.time()
    pending = []
    for profile in profiles:
        entry = cached.get(profile['id'], {})
        if not isinstance(entry, dict):
            entry = {}
        ttl = 7 * 86400 if entry.get('country') else 3600
        if (not named_country(profile) and binary(profile['engine']).is_file()
                and (entry.get('signature') != location_signature(profile)
                     or now - entry.get('checked', 0) > ttl)):
            pending.append(profile)

    def probe(profile):
        try:
            country = latency(profile, location=True)
        except Exception:
            country = ''
        return profile['id'], {'signature': location_signature(profile), 'country': country, 'checked': now}

    if pending:
        with ThreadPoolExecutor(max_workers=4) as pool:
            cached.update(pool.map(probe, pending))
        atomic_json(ROOT / 'locations.json', cached)
    return cached_locations(profiles)


def authorize(value):
    if has_naive(value):
        install('sing-box', naive=True)
    engines = sorted(e for e in required(value) if not can_tun(binary(e)))
    if not engines and dns_authorized():
        return
    for engine in engines:
        install(engine)
    sources = [binary(e) for e in engines]
    digests = [hashlib.sha256(p.read_bytes()).digest() for p in sources]
    args = [item for engine, source in zip(engines, sources) for item in (str(source), str(PRIVILEGED / engine))]
    with tempfile.TemporaryDirectory(prefix='.authorize-', dir=ROOT) as temporary:
        policy = Path(temporary) / 'dns.rules'
        policy.write_text(dns_policy())
        try:
            subprocess.run(['pkexec', '/bin/sh', '-c',
                            'set -eu\nvpn_gid="$1"\n/usr/bin/install -D -o root -g root -m 644 "$2" "$3"\n'
                            'shift 3\nwhile [ "$#" -gt 0 ]; do\n'
                            '/usr/bin/install -D -o root -g "$vpn_gid" -m 750 "$1" "$2"\n'
                            '/usr/bin/setcap cap_net_admin,cap_net_raw,cap_net_bind_service=ep "$2"\nshift 2\ndone',
                            'hyprstack-vpn-install', str(os.getgid()), str(policy), str(DNS_RULE), *args], check=True, timeout=180,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError as error:
            raise VpnError('VPN tunnel authorization failed or was cancelled') from error
    for engine, source, digest in zip(engines, sources, digests):
        target = PRIVILEGED / engine
        if hashlib.sha256(target.read_bytes()).digest() != digest or not can_tun(target):
            raise VpnError('The installed VPN core did not pass verification')
        if source == RUNTIME / engine and not source.is_symlink():
            link = RUNTIME / ('.' + engine + '-authorized')
            link.unlink(missing_ok=True)
            link.symlink_to(target)
            os.replace(link, source)
    atomic_json(ROOT / 'authorization.json', {'dnsPolicy': hashlib.sha256(dns_policy().encode()).hexdigest()})


def add_profiles(value, group, entries):
    names = set()
    old = {p['id']: p for p in value['profiles']}
    output = [p for p in value['profiles'] if p['group'] != group['id']]
    for item in entries:
        name, index = item['name'], 1
        while name in names:
            index += 1
            name = item['name'] + f' ({index})'
        names.add(name)
        if name in group.get('excluded', []):
            continue
        ident = hashlib.sha256((group['id'] + '\0' + name).encode()).hexdigest()[:16]
        output.append({**item, 'id': ident, 'name': name, 'group': group['id'], 'latency_ms': old.get(ident, {}).get('latency_ms', -1)})
    value['profiles'] = output
    if value['selectedProfile'] not in {p['id'] for p in output}:
        value['selectedProfile'] = output[0]['id'] if output else -1


def dispatch(action, payload):
    if action == 'connection-status':
        return connection_status()
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(ROOT, 0o700)
    if action == 'status':
        return status()
    if action == 'overview':
        return overview()
    if action == 'locations':
        return locations()
    if action == 'serve':
        session = read_json(ROOT / 'session.json')
        if session is None:
            raise VpnError('Add or select a VPN profile first')
        atomic_json(ROOT / 'process.json', {**session, 'pid': os.getpid(), 'start': proc_start(os.getpid())})
        os.umask(0o077)
        os.execv(binary(session['engine']), command(session['engine'], ROOT / 'config.json'))
    descriptor = os.open(ROOT / 'mutation.lock', os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(descriptor, 'a+') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise VpnError('Another VPN operation is in progress') from error
        value = model()
        if action == 'install':
            for engine in required(value):
                install(engine, naive=engine == 'sing-box' and has_naive(value))
        elif action == 'authorize':
            authorize(value)
        elif action == 'connect':
            connect()
        elif action == 'disconnect':
            service('stop')
        else:
            connected = connection_status()['connected']
            if action == 'import':
                text = str(payload.get('text', '')).strip()
                if not text or len(text.encode()) > MAX_IMPORT:
                    raise VpnError('Paste a profile link or subscription URL')
                subscription = bool(payload.get('subscription'))
                if subscription:
                    if urllib.parse.urlsplit(text).scheme not in ('https', 'http'):
                        raise VpnError('A subscription URL must begin with https:// or http://')
                    entries = parse(download(text, subscription=True).decode('utf-8-sig'))
                else:
                    entries = parse(text)
                for entry in entries:
                    validate(entry)
                group = {'id': secrets.token_hex(6), 'name': str(payload.get('name', '')).strip() or ('Subscription' if subscription else 'Imported'),
                         'subscription': subscription, 'excluded': []}
                if subscription:
                    group['url'] = text
                value['groups'].append(group)
                add_profiles(value, group, entries)
            elif action == 'update':
                for group in value['groups']:
                    if group['subscription']:
                        entries = parse(download(group['url'], subscription=True).decode('utf-8-sig'))
                        for entry in entries:
                            validate(entry)
                        add_profiles(value, group, entries)
            elif action == 'select':
                value['selectedProfile'] = payload['id']
                selected(value)
            elif action == 'mode':
                if payload['mode'] not in ('tun', 'proxy'):
                    raise VpnError('Choose VPN mode or local proxy mode')
                value['mode'] = payload['mode']
            elif action == 'route':
                if payload['id'] not in ('all', 'bypass-ru'):
                    raise VpnError('Choose a routing profile')
                value['route'] = payload['id']
            elif action == 'settings':
                agent = str(payload.get('userAgent', '')).strip()[:200]
                if any(ord(c) < 32 or ord(c) > 126 for c in agent):
                    raise VpnError('User-Agent must contain only printable ASCII characters')
                value['sendHwid'] = bool(payload.get('sendHwid'))
                value['userAgent'] = agent
            elif action in ('delete', 'test'):
                profile = next((p for p in value['profiles'] if p['id'] == payload['id']), None)
                if profile is None:
                    raise VpnError('The selected profile no longer exists')
                if action == 'test':
                    profile['latency_ms'] = latency(profile)
                else:
                    if connected and profile['id'] == value['selectedProfile']:
                        raise VpnError('Disconnect this profile before deleting it')
                    group = next(g for g in value['groups'] if g['id'] == profile['group'])
                    group['excluded'].append(profile['name'])
                    value['profiles'].remove(profile)
                    if value['selectedProfile'] == profile['id']:
                        value['selectedProfile'] = value['profiles'][0]['id'] if value['profiles'] else -1
            else:
                raise VpnError('Unknown VPN action')
            if connected and action in ('select', 'mode', 'route', 'update'):
                connect(value)
            atomic_json(ROOT / 'profiles.json', value)
        return overview()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('serve', 'status', 'connection-status', 'overview', 'locations', 'install', 'authorize', 'connect', 'disconnect', 'import', 'update', 'select', 'mode', 'route', 'settings', 'delete', 'test'))
    args = parser.parse_args()
    try:
        payload = json.load(sys.stdin) if args.action in ('import', 'select', 'mode', 'route', 'settings', 'delete', 'test') else {}
        print(json.dumps(dispatch(args.action, payload), ensure_ascii=False))
        return 0
    except Exception as error:
        message = str(error) if isinstance(error, (VpnError, ProfileError)) else 'The VPN action did not complete'
        print(json.dumps({'connected': False, 'state': 'error', 'error': message, 'reason': message,
                          'installed': all(binary(e).is_file() for e in required(model()))}, ensure_ascii=False))
        return 1


if __name__ == '__main__':
    sys.exit(main())
