#!/usr/bin/env python3
"""On-demand controls for upstream sing-box and Xray. No resident manager.

Only the selected core runs while connected. Imports use stdin, profile files
are private, and the shell never receives server credentials or native configs.
"""
from __future__ import annotations

import argparse
import base64
import copy
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pwd
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
    return read_json(ROOT / 'profiles.json', {'profiles': [], 'groups': [], 'selectedProfile': -1,
                                             'mode': 'tun', 'route': 'all'})


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
    privileged = PRIVILEGED / engine
    if can_tun(privileged):
        return privileged
    system = shutil.which(engine)
    return Path(system) if system else RUNTIME / engine


def required(value):
    return {'sing-box'} | {p['engine'] for p in value['profiles']}


def download(url, limit=MAX_IMPORT):
    request = urllib.request.Request(url, headers={'User-Agent': 'Hyprstack-VPN/1'})
    with urllib.request.urlopen(request, timeout=30) as response:
        content = response.read(limit + 1)
    if len(content) > limit:
        raise VpnError('The download is too large')
    return content


def install(engine):
    if binary(engine).is_file():
        return
    version, prefix, platforms = RELEASES[engine]
    asset = platforms.get(os.uname().machine)
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
    ipv4_bypass = bool(bypass) and not direct_ipv6_available()
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
                         'autoSystemRoutingTable': ['0.0.0.0/0', '::/0'], 'autoOutboundsInterface': 'auto'},
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
            'dns': {'servers': dns_servers, 'queryStrategy': 'UseIP'},
            'routing': {'domainStrategy': 'IPIfNonMatch', 'rules': rules}}


def command(engine, config, check=False):
    args = [str(binary(engine))]
    return (args + (['check'] if check else ['run']) + ['-c', str(config)] if engine == 'sing-box'
            else args + ['run'] + (['-test'] if check else []) + ['-config', str(config)])


def validate(profile):
    install(profile['engine'])
    with tempfile.TemporaryDirectory(prefix='.check-', dir=ROOT) as temporary:
        path = Path(temporary) / 'config.json'
        atomic_json(path, configuration(profile, http_port=0))
        result = subprocess.run(command(profile['engine'], path, True), capture_output=True, timeout=15)
        if result.returncode:
            raise VpnError('The profile configuration is invalid or unsupported')


def proc_start(pid):
    return Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[19]


def status():
    value = model()
    session = read_json(ROOT / 'process.json', {})
    alive = False
    try:
        alive = proc_start(session['pid']) == session['start']
        os.kill(session['pid'], 0)
    except (OSError, KeyError):
        alive = False
    connected = alive and (session.get('mode') == 'proxy' or Path('/sys/class/net/hyprstack-vpn').exists())
    engines = required(value)
    return {'connected': bool(connected), 'state': 'connected' if connected else 'disconnected',
            'reason': '', 'authUrl': '', 'server': session.get('name', '') if connected else '',
            'selectedProfile': value['selectedProfile'], 'mode': value['mode'],
            'installed': all(binary(e).is_file() for e in engines),
            'canTun': all(can_tun(binary(e)) for e in engines) and dns_authorized(),
            'engine': session.get('engine', '') if connected else '', 'engines': sorted(engines)}


def overview():
    value = model()
    return {**status(), 'profiles': [{k: p[k] for k in ('id', 'name', 'type', 'group', 'latency_ms', 'engine')} for p in value['profiles']],
            'groups': [{k: g[k] for k in ('id', 'name', 'subscription')} for g in value['groups']],
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
    if not status()['connected']:
        return False
    try:
        with socket.create_connection(('127.0.0.1', 2080), timeout=.5) as stream:
            stream.sendall(b'\x05\x01\x00')
            return stream.recv(2) == b'\x05\x00'
    except OSError:
        return False


def connect(value=None):
    value = value or model()
    profile = selected(value)
    if not binary(profile['engine']).is_file():
        raise VpnError('The VPN core is not installed')
    if value['mode'] == 'tun' and (not can_tun(binary(profile['engine'])) or not dns_authorized()):
        raise VpnError('Authorize the VPN tunnel in VPN settings first')
    config = configuration(profile, value['mode'], value['route'])
    atomic_json(ROOT / 'pending.json', config)
    completed = subprocess.run(command(profile['engine'], ROOT / 'pending.json', True), capture_output=True, timeout=20)
    if completed.returncode:
        raise VpnError('The profile configuration is invalid or unsupported')
    old_config, old_session = read_json(ROOT / 'config.json'), read_json(ROOT / 'session.json')
    was_connected = status()['connected']
    os.replace(ROOT / 'pending.json', ROOT / 'config.json')
    atomic_json(ROOT / 'session.json', {k: profile[k] for k in ('id', 'name', 'type', 'engine')} | {'mode': value['mode']})
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


def latency(profile):
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
                    host = b'www.gstatic.com'
                    stream.sendall(b'\x05\x01\x00\x03' + bytes([len(host)]) + host + struct.pack('>H', 443))
                    header = receive(stream, 4)
                    if header[1] != 0:
                        raise VpnError('The VPN server did not respond to the connection test')
                    receive(stream, {1: 4, 4: 16}.get(header[3], 0) or receive(stream, 1)[0])
                    receive(stream, 2)
                    with ssl.create_default_context().wrap_socket(stream, server_hostname=host.decode()) as secure:
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


def authorize(value):
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
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(ROOT, 0o700)
    if action == 'status':
        return status()
    if action == 'overview':
        return overview()
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
                install(engine)
        elif action == 'authorize':
            authorize(value)
        elif action == 'connect':
            connect()
        elif action == 'disconnect':
            service('stop')
        else:
            connected = status()['connected']
            if action == 'import':
                text = str(payload.get('text', '')).strip()
                if not text or len(text.encode()) > MAX_IMPORT:
                    raise VpnError('Paste a profile link or subscription URL')
                subscription = bool(payload.get('subscription'))
                if subscription:
                    if urllib.parse.urlsplit(text).scheme not in ('https', 'http'):
                        raise VpnError('A subscription URL must begin with https:// or http://')
                    entries = parse(download(text).decode('utf-8-sig'))
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
                        entries = parse(download(group['url']).decode('utf-8-sig'))
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
    parser.add_argument('action', choices=('serve', 'status', 'overview', 'install', 'authorize', 'connect', 'disconnect', 'import', 'update', 'select', 'mode', 'route', 'delete', 'test'))
    args = parser.parse_args()
    try:
        payload = json.load(sys.stdin) if args.action in ('import', 'select', 'mode', 'route', 'delete', 'test') else {}
        print(json.dumps(dispatch(args.action, payload), ensure_ascii=False))
        return 0
    except Exception as error:
        message = str(error) if isinstance(error, (VpnError, ProfileError)) else 'The VPN action did not complete'
        print(json.dumps({'connected': False, 'state': 'error', 'error': message, 'reason': message,
                          'installed': all(binary(e).is_file() for e in required(model()))}, ensure_ascii=False))
        return 1


if __name__ == '__main__':
    sys.exit(main())
