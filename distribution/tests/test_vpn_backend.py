#!/usr/bin/env python3
"""VPN startup regression tests; no tunnel, installed profile or service is changed."""
import errno
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'shell/assets'))
import vpn


class VpnStartupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='hs-vpn-startup-')
        self.root = Path(self.temporary.name)
        self.environment = patch.object(vpn, 'ROOT', self.root)
        self.environment.start()
        self.core = self.root / 'core'
        self.core.touch()
        self.profile = {'id': 'test', 'name': 'Fixture', 'type': 'vless', 'engine': 'xray',
                        'outbound': {'protocol': 'freedom'}}
        self.model = {'profiles': [self.profile], 'selectedProfile': 'test', 'mode': 'proxy', 'route': 'all'}

    def tearDown(self):
        self.environment.stop()
        self.temporary.cleanup()

    def test_country_cache_uses_each_profile_without_changing_connection_or_installing(self):
        before = json.loads(json.dumps(self.model))
        with patch.object(vpn, 'model', return_value=self.model), patch.object(vpn, 'binary', return_value=self.core), \
             patch.object(vpn, 'latency', return_value='FI') as probe, patch.object(vpn, 'service') as service, \
             patch.object(vpn, 'install') as install:
            self.assertEqual(vpn.locations(), {'test':'FI'})
            self.assertEqual(vpn.locations(), {'test':'FI'})
            probe.assert_called_once_with(self.profile, location=True)
            service.assert_not_called(); install.assert_not_called()
            self.assertEqual(self.model, before)
            self.profile['outbound']['tag'] = 'changed'
            self.assertEqual(vpn.cached_locations(self.model['profiles']), {})
            probe.return_value = 'DE'
            self.assertEqual(vpn.locations(), {'test':'DE'})

    def test_named_flags_need_no_network_and_all_profiles_are_included(self):
        self.model['profiles'] = [dict(self.profile,id=str(i),name='🇫🇷 Server '+str(i)) for i in range(12)]
        with patch.object(vpn, 'model', return_value=self.model), patch.object(vpn, 'latency') as probe:
            self.assertEqual(vpn.locations(), {str(i):'FR' for i in range(12)})
            probe.assert_not_called()

    def test_failed_location_lookups_are_cached_and_optional_cache_corruption_is_ignored(self):
        (self.root/'locations.json').write_text('[]')
        self.assertEqual(vpn.cached_locations([self.profile]), {})
        with patch.object(vpn, 'model', return_value=self.model), patch.object(vpn, 'binary', return_value=self.core), \
             patch.object(vpn, 'latency', side_effect=vpn.VpnError('offline')) as probe:
            self.assertEqual(vpn.locations(), {})
            self.assertEqual(vpn.locations(), {})
            self.assertEqual(probe.call_count,1)

    def test_busy_tcp_ports_choose_distinct_free_ports(self):
        with socket.socket() as socks, socket.socket() as http:
            socks.bind(('127.0.0.1', 0))
            http.bind(('127.0.0.1', 0))
            occupied = {'socksPort': socks.getsockname()[1], 'httpPort': http.getsockname()[1]}
            chosen = vpn.proxy_ports(occupied)
            self.assertFalse(set(chosen.values()) & set(occupied.values()))
            self.assertNotEqual(chosen['socksPort'], chosen['httpPort'])
            # Allocation must release all reservations before the core starts.
            with socket.socket() as tcp, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
                tcp.bind(('127.0.0.1', chosen['socksPort']))
                udp.bind(('127.0.0.1', chosen['socksPort']))

    def test_socks_also_avoids_a_busy_udp_port(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as occupied:
            occupied.bind(('127.0.0.1', 0))
            port = occupied.getsockname()[1]
            chosen = vpn.proxy_ports({'socksPort': port, 'httpPort': port})
            self.assertNotEqual(chosen['socksPort'], port)
            self.assertNotEqual(chosen['socksPort'], chosen['httpPort'])

    def test_both_cores_receive_selected_ports(self):
        for engine in ('xray', 'sing-box'):
            config = vpn.configuration(dict(self.profile, engine=engine), port=41234, http_port=41235)
            key = 'port' if engine == 'xray' else 'listen_port'
            self.assertEqual([i[key] for i in config['inbounds']], [41234, 41235])

    def test_ready_probes_the_session_port(self):
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen()
            listener.settimeout(2)
            def handshake():
                with listener.accept()[0] as stream:
                    stream.settimeout(2)
                    if stream.recv(3) == b'\x05\x01\x00':
                        stream.sendall(b'\x05\x00')
            worker = threading.Thread(target=handshake, daemon=True)
            worker.start()
            with patch.object(vpn, 'status', return_value={'connected': True, 'socksPort': listener.getsockname()[1]}):
                self.assertTrue(vpn.ready())
            worker.join(timeout=2)
            self.assertFalse(worker.is_alive())

    def test_tun_dns_uses_ipv4_without_a_physical_ipv6_route(self):
        with patch.object(vpn, 'direct_ipv6_available', return_value=False), \
             patch.object(vpn, 'routing_rules', return_value={'domain_suffix': ['ru']}):
            for route in ('all', 'bypass-ru'):
                config = vpn.configuration(self.profile, mode='tun', route=route)
                tun = next(i for i in config['inbounds'] if i['tag'] == 'tun')
                self.assertTrue(tun['settings']['autoSystemDnsToGateway'])
                self.assertEqual(config['dns']['queryStrategy'], 'UseIPv4')
                self.assertEqual(config['routing']['rules'][0],
                    {'type': 'field', 'inboundTag': ['tun'], 'port': 53, 'outboundTag': 'dns'})

    def test_real_ipv6_connectivity_keeps_dual_stack_dns(self):
        with patch.object(vpn, 'direct_ipv6_available', return_value=True):
            config = vpn.configuration(self.profile, mode='tun')
        self.assertEqual(config['dns']['queryStrategy'], 'UseIP')

    def test_missing_old_kernel_module_has_a_restart_message(self):
        with patch.object(vpn.os, 'open', side_effect=OSError(errno.ENODEV, 'No such device')), \
             patch.object(Path, 'is_dir', return_value=False):
            self.assertIn('Restart the system', vpn.tun_error())

    def test_tun_failure_does_not_restart_or_overwrite_a_session(self):
        self.model['mode'] = 'tun'
        old = {'mode': 'proxy', 'socksPort': 41234, 'httpPort': 41235}
        vpn.atomic_json(self.root / 'session.json', old)
        with patch.object(vpn, 'binary', return_value=self.core), \
             patch.object(vpn, 'can_tun', return_value=True), \
             patch.object(vpn, 'dns_authorized', return_value=True), \
             patch.object(vpn, 'tun_error', return_value='Restart the system'), \
             patch.object(vpn, 'service') as service:
            with self.assertRaisesRegex(vpn.VpnError, 'Restart the system'):
                vpn.connect(self.model)
        service.assert_not_called()
        self.assertEqual(vpn.read_json(self.root / 'session.json'), old)
        self.assertFalse((self.root / 'config.json').exists())

    def test_connect_persists_ports_and_failure_restores_them(self):
        old = {'mode': 'proxy', 'socksPort': 41234, 'httpPort': 41235}
        old_config = {'fixture': 'previous configuration'}
        vpn.atomic_json(self.root / 'session.json', old)
        vpn.atomic_json(self.root / 'config.json', old_config)
        ports = {'socksPort': 41236, 'httpPort': 41237}
        with patch.object(vpn, 'binary', return_value=self.core), \
             patch.object(vpn, 'status', return_value={'connected': False}), \
             patch.object(vpn, 'proxy_ports', return_value=ports), \
             patch.object(vpn.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)), \
             patch.object(vpn, 'service') as service, \
             patch.object(vpn, 'ready', return_value=True) as ready:
            vpn.connect(self.model)
            session = vpn.read_json(self.root / 'session.json')
            self.assertEqual({k: session[k] for k in ports}, ports)
            config = vpn.read_json(self.root / 'config.json')
            self.assertEqual([i['port'] for i in config['inbounds']], list(ports.values()))
            ready.side_effect = vpn.VpnError('Fixture startup failure')
            with self.assertRaisesRegex(vpn.VpnError, 'Fixture startup failure'):
                vpn.connect(self.model)
            self.assertEqual(vpn.read_json(self.root / 'session.json'), session)
            self.assertEqual(vpn.read_json(self.root / 'config.json'), config)
            self.assertEqual(service.call_args.args, ('stop',))


if __name__ == '__main__':
    unittest.main()
