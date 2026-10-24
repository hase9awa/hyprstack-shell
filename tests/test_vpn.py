"""Behavior checks for profile compatibility, private output and safe handover.

Run: python3 -m unittest discover -s tests -p test_vpn.py
"""
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
import base64
import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'shell/assets'))
import vpn
import vpn_profiles as imports


class VpnTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for name in ('ROOT', 'RUNTIME', 'PRIVILEGED'):
            p = patch.object(vpn, name, self.root / name.lower())
            p.start()
            self.addCleanup(p.stop)
            getattr(vpn, name).mkdir(mode=0o700)
        self.profile = imports.native({'type': 'trojan', 'server': '192.0.2.1', 'server_port': 8082, 'password': 'private-password'}, 'Server')
        self.value = {'profiles': [], 'groups': [{'id': 'local', 'name': 'Profiles', 'subscription': False, 'excluded': []}], 'selectedProfile': -1, 'mode': 'tun', 'route': 'all'}
        vpn.add_profiles(self.value, self.value['groups'][0], [self.profile])
        vpn.atomic_json(vpn.ROOT / 'profiles.json', self.value)

    def test_native_outbound_keeps_every_transport_field(self):
        raw = {'protocol': 'vless', 'settings': {'address': '192.0.2.1', 'id': 'test', 'encryption': 'custom'},
               'streamSettings': {'network': 'xhttp', 'security': 'reality', 'xhttpSettings': {'extra': {'xmux': {'maxConnections': 2}}}}}
        self.assertEqual(imports.native(raw)['outbound'], raw)
        self.assertEqual(imports.native(raw)['engine'], 'xray')

    def test_xhttp_reality_share_link(self):
        entry = imports.parse('vless://uuid@192.0.2.1:443?type=xhttp&security=reality&pbk=key&sid=abcd&sni=example.com&path=%2Fdata&mode=auto#Server')[0]
        stream = entry['outbound']['streamSettings']
        self.assertEqual(entry['engine'], 'xray')
        self.assertEqual(stream['realitySettings']['password'], 'key')
        self.assertEqual(stream['xhttpSettings'], {'path': '/data', 'mode': 'auto'})

    def test_plain_trojan_is_not_silently_changed_to_tls(self):
        self.assertNotIn('tls', self.profile['outbound'])
        self.assertNotIn('tls', imports.parse('trojan://password@192.0.2.1:8082?security=none')[0]['outbound'])
        self.assertTrue(imports.parse('trojan://password@192.0.2.1:443')[0]['outbound']['tls']['enabled'])

    def test_popular_protocols_and_encoded_credentials(self):
        cases = [('ss://YWVzLTEyOC1nY206cGFzc3dvcmQ@192.0.2.1:1234#SS', 'shadowsocks'),
                 ('hy2://password@192.0.2.1:443?sni=example.com', 'hysteria2'),
                 ('tuic://uuid:password@192.0.2.1:443?congestion_control=bbr', 'tuic'),
                 ('socks5://user:p%40ss@192.0.2.1:1080', 'socks'),
                 ('https://user:password@example.com:443', 'http')]
        for text, typ in cases:
            with self.subTest(typ=typ):
                self.assertEqual(imports.parse(text)[0]['type'], typ)
        self.assertEqual(imports.parse(cases[3][0])[0]['outbound']['password'], 'p@ss')

    def test_base64_subscription(self):
        text = 'trojan://password@192.0.2.1:443#One\nvless://uuid@192.0.2.2:443?type=xhttp#Two'
        encoded = base64.urlsafe_b64encode(text.encode()).decode().rstrip('=')
        self.assertEqual([p['name'] for p in imports.parse(encoded)], ['One', 'Two'])

    def test_unsupported_plugin_does_not_silently_drop_parameters(self):
        with self.assertRaises(imports.ProfileError):
            imports.parse('ss://YWVzLTEyOC1nY206cGFzc3dvcmQ@192.0.2.1:1234?plugin=unknown')

    def test_subscription_rotation_preserves_selection(self):
        ident = self.value['selectedProfile']
        changed = copy.deepcopy(self.profile)
        changed['outbound']['password'] = 'rotated'
        vpn.add_profiles(self.value, self.value['groups'][0], [changed])
        self.assertEqual(self.value['selectedProfile'], ident)
        self.assertEqual(self.value['profiles'][0]['outbound']['password'], 'rotated')

    def test_overview_contains_no_credentials_or_subscription_url(self):
        self.value['groups'][0].update(subscription=True, url='https://example.com/private-token')
        vpn.atomic_json(vpn.ROOT / 'profiles.json', self.value)
        output = json.dumps(vpn.overview())
        self.assertNotIn('private-password', output)
        self.assertNotIn('private-token', output)
        self.assertNotIn('outbound', output)

    def test_private_state_permissions(self):
        self.assertEqual((vpn.ROOT / 'profiles.json').stat().st_mode & 0o777, 0o600)
        self.assertEqual(vpn.ROOT.stat().st_mode & 0o777, 0o700)

    def test_failed_import_preserves_profiles(self):
        original = (vpn.ROOT / 'profiles.json').read_bytes()
        with patch.object(vpn, 'validate', side_effect=vpn.VpnError('Invalid configuration')), patch.object(vpn, 'service') as service:
            with self.assertRaises(vpn.VpnError):
                vpn.dispatch('import', {'text': 'trojan://password@192.0.2.2:443'})
            service.assert_not_called()
        self.assertEqual((vpn.ROOT / 'profiles.json').read_bytes(), original)

    def test_missing_tunnel_permission_preserves_connection(self):
        core = vpn.RUNTIME / 'sing-box'
        core.write_bytes(b'core')
        with patch.object(vpn, 'binary', return_value=core), patch.object(vpn, 'can_tun', return_value=False), patch.object(vpn, 'service') as service:
            with self.assertRaisesRegex(vpn.VpnError, 'Authorize'):
                vpn.connect()
            service.assert_not_called()

    def test_invalid_config_preserves_connection(self):
        core = vpn.RUNTIME / 'sing-box'
        core.write_bytes(b'core')
        with patch.object(vpn, 'binary', return_value=core), patch.object(vpn, 'can_tun', return_value=True), patch.object(vpn, 'dns_authorized', return_value=True), patch.object(vpn.subprocess, 'run', return_value=SimpleNamespace(returncode=1)), patch.object(vpn, 'service') as service:
            with self.assertRaisesRegex(vpn.VpnError, 'invalid'):
                vpn.connect()
            service.assert_not_called()

    def test_failed_switch_restores_old_configuration(self):
        core = vpn.RUNTIME / 'sing-box'
        core.write_bytes(b'core')
        vpn.atomic_json(vpn.ROOT / 'config.json', {'previous': True})
        vpn.atomic_json(vpn.ROOT / 'session.json', {'engine': 'sing-box', 'name': 'Previous'})
        with patch.object(vpn, 'binary', return_value=core), patch.object(vpn, 'can_tun', return_value=True), patch.object(vpn, 'dns_authorized', return_value=True), patch.object(vpn, 'status', return_value={'connected': True}), patch.object(vpn.subprocess, 'run', return_value=SimpleNamespace(returncode=0)), patch.object(vpn, 'ready', side_effect=vpn.VpnError('New connection failed')), patch.object(vpn, 'service') as service:
            with self.assertRaisesRegex(vpn.VpnError, 'New connection failed'):
                vpn.connect()
            self.assertEqual([c.args[0] for c in service.call_args_list], ['restart', 'stop', 'start'])
        self.assertEqual(vpn.read_json(vpn.ROOT / 'config.json'), {'previous': True})
        self.assertEqual(vpn.read_json(vpn.ROOT / 'session.json')['name'], 'Previous')

    def test_cancelled_authorization_does_not_replace_core_or_stop_vpn(self):
        core = vpn.RUNTIME / 'sing-box'
        core.write_bytes(b'core')
        with patch.object(vpn, 'install'), patch.object(vpn, 'binary', return_value=core), patch.object(vpn, 'can_tun', return_value=False), patch.object(vpn.subprocess, 'run', side_effect=subprocess.CalledProcessError(126, ['pkexec'])), patch.object(vpn, 'service') as service:
            with self.assertRaisesRegex(vpn.VpnError, 'cancelled'):
                vpn.authorize(self.value)
            service.assert_not_called()
        self.assertFalse(core.is_symlink())
        self.assertEqual(core.read_bytes(), b'core')

    def test_stale_pid_cannot_report_connected(self):
        vpn.atomic_json(vpn.ROOT / 'process.json', {'pid': 999999, 'start': '123', 'mode': 'proxy'})
        with patch.object(vpn, 'proc_start', side_effect=FileNotFoundError):
            self.assertFalse(vpn.status()['connected'])

    def test_tunnel_ipv6_route_does_not_count_as_wan_connectivity(self):
        routes = self.root / 'ipv6_route'
        prefix = '0' * 32 + ' 00 ' + '0' * 32 + ' 00 ' + '0' * 32 + ' 00000400 00000001 00000000 '
        routes.write_text(prefix + '00000003 hyprstack-vpn\n' + prefix + '00200200 lo\n')
        self.assertFalse(vpn.direct_ipv6_available(routes))
        routes.write_text(prefix + '00000003 wlan0\n')
        self.assertTrue(vpn.direct_ipv6_available(routes))
        routes.write_text(prefix + '00200200 wlan0\n')
        self.assertFalse(vpn.direct_ipv6_available(routes))

    def test_ipv4_bypass_retains_ipv6_for_proxied_domains(self):
        bypass = {'domain_suffix': ['ru'], 'ip_cidr': ['192.0.2.0/24']}
        with patch.object(vpn, 'routing_rules', return_value=bypass), patch.object(vpn, 'direct_ipv6_available', return_value=False):
            config = vpn.configuration(self.profile, 'tun', 'bypass-ru')
        self.assertEqual(config['dns']['rules'], [{'domain_suffix': ['ru'], 'query_type': ['AAAA'], 'action': 'predefined', 'rcode': 'NOERROR'}])
        self.assertEqual(config['dns']['final'], 'remote')
        self.assertNotIn('strategy', config['dns'])
        # Cached IPv6 addresses must use the VPN, never the unavailable WAN.
        ipv6 = next(r for r in config['route']['rules'] if r.get('ip_version') == 6)
        self.assertEqual(ipv6['outbound'], 'vpn')

    def test_ipv6_wan_keeps_dual_stack_bypass(self):
        with patch.object(vpn, 'routing_rules', return_value={'domain_suffix': ['ru']}), patch.object(vpn, 'direct_ipv6_available', return_value=True):
            config = vpn.configuration(self.profile, 'tun', 'bypass-ru')
        self.assertEqual(config['dns']['rules'], [])
        self.assertFalse(any(r.get('ip_version') == 6 for r in config['route']['rules']))

    def test_xray_ipv4_bypass_does_not_disable_vpn_ipv6(self):
        profile = imports.native({'protocol': 'vless', 'settings': {'address': '192.0.2.1', 'id': 'test', 'encryption': 'none'}})
        with patch.object(vpn, 'routing_rules', return_value={'domain_suffix': ['ru']}), patch.object(vpn, 'direct_ipv6_available', return_value=False):
            config = vpn.configuration(profile, 'tun', 'bypass-ru')
        self.assertEqual(config['dns']['queryStrategy'], 'UseIP')
        self.assertEqual(config['dns']['servers'][0]['queryStrategy'], 'UseIPv4')
        self.assertEqual(config['dns']['servers'][0]['domains'], ['domain:ru'])


if __name__ == '__main__':
    unittest.main()
