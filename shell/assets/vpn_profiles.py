"""Share-link and native JSON imports for the two upstream VPN cores."""
from __future__ import annotations

import base64
import json
import urllib.parse as url


class ProfileError(ValueError):
    pass


def decode64(value):
    return base64.urlsafe_b64decode(value + '=' * (-len(value) % 4)).decode('utf-8-sig')


def number(value):
    return int(value)


def tls_options(query, server):
    result = {'enabled': True, 'server_name': query.get('sni') or query.get('peer') or server}
    if query.get('insecure', query.get('allowInsecure')) in ('1', 'true'):
        result['insecure'] = True
    if query.get('alpn'):
        result['alpn'] = query['alpn'].split(',')
    return result


def xray_transport(query):
    network = query.get('type', 'tcp')
    security = query.get('security', 'none')
    stream = {'network': network, 'security': security}
    if security in ('tls', 'reality'):
        opts = {'serverName': query.get('sni', ''), 'fingerprint': query.get('fp', 'chrome')}
        if query.get('alpn'):
            opts['alpn'] = query['alpn'].split(',')
        if security == 'reality':
            opts.update(password=query.get('pbk', ''), shortId=query.get('sid', ''), spiderX=query.get('spx', ''))
        elif query.get('allowInsecure', query.get('insecure')) in ('1', 'true'):
            opts['allowInsecure'] = True
        if query.get('ech'):
            opts['echConfigList'] = query['ech']
        stream[security + 'Settings'] = opts
    if network in ('xhttp', 'splithttp'):
        stream['network'] = 'xhttp'
        opts = {k: query[k] for k in ('host', 'path', 'mode') if k in query}
        if query.get('extra'):
            opts['extra'] = json.loads(query['extra'])
        stream['xhttpSettings'] = opts
    elif network == 'ws':
        stream['wsSettings'] = {'path': query.get('path', '/'), 'headers': {'Host': query['host']} if query.get('host') else {}}
    elif network == 'grpc':
        stream['grpcSettings'] = {'serviceName': query.get('serviceName', ''), 'multiMode': query.get('mode') == 'multi'}
        if query.get('authority'):
            stream['grpcSettings']['authority'] = query['authority']
    elif network == 'httpupgrade':
        stream['httpupgradeSettings'] = {'path': query.get('path', '/'), 'host': query.get('host', '')}
    elif network in ('http', 'h2'):
        stream['network'] = 'http'
        stream['httpSettings'] = {'path': query.get('path', '/'), 'host': query.get('host', '').split(',')}
    elif network == 'kcp':
        stream['kcpSettings'] = {'seed': query.get('seed', ''), 'header': {'type': query.get('headerType', 'none')}}
    elif network == 'tcp' and query.get('headerType') not in (None, 'none'):
        stream['tcpSettings'] = {'header': {'type': query['headerType']}}
    elif network != 'tcp':
        raise ProfileError('Use native JSON configuration for this transport')
    return stream


def native(item, name=''):
    outbound = json.loads(json.dumps(item))
    if isinstance(outbound.get('protocol'), str):
        engine, typ = 'xray', outbound['protocol']
    elif isinstance(outbound.get('type'), str):
        engine, typ = 'sing-box', outbound['type']
    else:
        raise ProfileError('Paste a share link or a native sing-box/Xray outbound JSON')
    if typ in ('direct', 'freedom', 'block', 'blackhole', 'dns', 'selector', 'urltest'):
        return None
    return {'name': (name or str(outbound.get('tag') or typ))[:180], 'type': typ, 'engine': engine, 'outbound': outbound}


def link(text):
    scheme = text.split('://', 1)[0].lower()
    if scheme == 'vmess':
        data = json.loads(decode64(text.split('://', 1)[1]))
        query = {'type': data.get('net', 'tcp'), 'security': 'tls' if data.get('tls') == 'tls' else 'none',
                 'sni': data.get('sni', ''), 'host': data.get('host', ''), 'path': data.get('path', '/'),
                 'fp': data.get('fp', 'chrome')}
        if query['type'] == 'grpc':
            query['serviceName'] = data.get('path', '')
        outbound = {'protocol': 'vmess', 'settings': {'vnext': [{'address': data['add'], 'port': int(data['port']),
                     'users': [{'id': data['id'], 'alterId': int(data.get('aid', 0)), 'security': data.get('scy', 'auto')}]}]},
                    'streamSettings': xray_transport(query)}
        return native(outbound, data.get('ps', 'VMess'))
    if scheme == 'ss' and '@' not in text.split('#', 1)[0]:
        body, _, fragment = text.split('://', 1)[1].partition('#')
        text = 'ss://' + decode64(body) + ('#' + fragment if fragment else '')
    parsed = url.urlsplit(text)
    query = dict(url.parse_qsl(parsed.query))
    server = parsed.hostname
    if not server:
        raise ProfileError('The profile has no server address')
    port = parsed.port or (443 if scheme in ('trojan', 'vless', 'hysteria2', 'hy2', 'tuic', 'https') else 1080)
    user = url.unquote(parsed.username or '')
    password = url.unquote(parsed.password or '')
    name = url.unquote(parsed.fragment) or scheme.upper()
    if scheme == 'vless':
        settings = {'address': server, 'port': port, 'id': user, 'encryption': query.get('encryption', 'none')}
        if query.get('flow'):
            settings['flow'] = query['flow']
        if query.get('packetEncoding'):
            settings['packetEncoding'] = query['packetEncoding']
        return native({'protocol': 'vless', 'settings': settings, 'streamSettings': xray_transport(query)}, name)
    outbound = {'type': scheme, 'server': server, 'server_port': port}
    if scheme == 'trojan':
        outbound['password'] = user + (':' + password if parsed.password is not None else '')
        if query.get('security', 'tls') != 'none':
            outbound['tls'] = tls_options(query, server)
        network = query.get('type', 'tcp')
        if network != 'tcp':
            if network not in ('ws', 'grpc', 'httpupgrade', 'http'):
                raise ProfileError('Use native JSON configuration for this transport')
            transport = {'type': network}
            if network == 'grpc':
                transport['service_name'] = query.get('serviceName', '')
            else:
                transport['path'] = query.get('path', '/')
                if query.get('host'):
                    transport['headers'] = {'Host': query['host']}
            outbound['transport'] = transport
    elif scheme == 'ss':
        if parsed.password is None:
            user, password = decode64(user).split(':', 1)
        if query.get('plugin'):
            raise ProfileError('Use native JSON configuration for Shadowsocks plugins')
        outbound.update(type='shadowsocks', method=user, password=password)
    elif scheme in ('hysteria2', 'hy2'):
        outbound.update(type='hysteria2', password=user + (':' + password if parsed.password is not None else ''), tls=tls_options(query, server))
        if query.get('obfs'):
            outbound['obfs'] = {'type': query['obfs'], 'password': query.get('obfs-password', '')}
        for source, target in (('upmbps', 'up_mbps'), ('downmbps', 'down_mbps')):
            if query.get(source):
                outbound[target] = int(query[source])
    elif scheme == 'tuic':
        outbound.update(uuid=user, password=password, tls=tls_options(query, server))
        for source, target in (('congestion_control', 'congestion_control'), ('udp_relay_mode', 'udp_relay_mode')):
            if query.get(source):
                outbound[target] = query[source]
    elif scheme in ('socks', 'socks5', 'http', 'https'):
        outbound['type'] = 'socks' if scheme.startswith('socks') else 'http'
        if user:
            outbound.update(username=user, password=password)
        if scheme == 'https':
            outbound['tls'] = tls_options(query, server)
    else:
        raise ProfileError('This share-link format is unsupported; use native JSON configuration')
    return native(outbound, name)


def parse(text):
    text = text.strip().lstrip('\ufeff')
    if not text:
        raise ProfileError('No supported profiles were found')
    if text[:1] not in ('{', '[') and '://' not in text:
        text = decode64(text.strip())
    if text[:1] in ('{', '['):
        data = json.loads(text)
        if isinstance(data, dict):
            items = data.get('outbounds', [data])
        else:
            items = data
        profiles = [native(item) for item in items]
    else:
        profiles = [link(line.strip()) for line in text.splitlines() if line.strip() and not line.lstrip().startswith('#')]
    result = [p for p in profiles if p is not None]
    if not result:
        raise ProfileError('No supported profiles were found')
    return result
