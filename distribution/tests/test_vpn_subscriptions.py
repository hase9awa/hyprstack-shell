#!/usr/bin/env python3
"""Subscription headers and redirects against loopback servers with invented IDs."""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'shell/assets'))
import vpn


class SubscriptionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='hs-subscription-test-')
        self.root_patch = patch.object(vpn, 'ROOT', Path(self.temporary.name))
        self.root_patch.start()
        self.settings = {'sendHwid': False, 'userAgent': ''}
        self.received = []
        owner = self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                owner.received.append({k.lower(): v for k, v in self.headers.items()})
                if self.path in ('/same', '/different'):
                    self.send_response(302)
                    target = owner.first if self.path == '/same' else owner.second
                    host = '127.0.0.1' if self.path == '/same' else 'localhost'
                    self.send_header('Location', f'http://{host}:{target.server_port}/ok')
                elif self.path == '/requires':
                    self.send_response(404)
                    self.send_header('X-Hwid-Not-Supported', 'true')
                else:
                    self.send_response(200)
                self.end_headers()
                self.wfile.write(b'fixture subscription')
        self.first = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.second = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.workers = []
        for server in (self.first, self.second):
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            self.workers.append(worker)
        self.url = f'http://127.0.0.1:{self.first.server_port}'

    def tearDown(self):
        for server in (self.first, self.second):
            server.shutdown()
            server.server_close()
        for worker in self.workers:
            worker.join(timeout=2)
        self.root_patch.stop()
        self.temporary.cleanup()

    def request(self, path='/ok', subscription=True, limit=vpn.MAX_IMPORT):
        with patch.object(vpn, 'model', side_effect=lambda: self.settings), \
             patch.object(vpn, 'panel_version', return_value='fixture'), \
             patch.object(vpn, 'hwid', return_value='fixture-device-id'):
            return vpn.download(self.url + path, subscription=subscription, limit=limit)

    def test_device_id_is_opt_in_and_downloads_keep_their_own_headers(self):
        self.request()
        self.assertEqual(self.received[-1]['user-agent'], 'hyprstack/fixture')
        self.assertNotIn('x-hwid', self.received[-1])
        self.settings.update(sendHwid=True, userAgent='custom-agent/2')
        self.request()
        self.assertEqual(self.received[-1]['x-hwid'], 'fixture-device-id')
        self.assertEqual(self.received[-1]['user-agent'], 'custom-agent/2')
        self.request(subscription=False)
        self.assertNotIn('x-hwid', self.received[-1])
        self.assertEqual(self.received[-1]['user-agent'], 'Hyprstack-VPN/1')

    def test_same_origin_keeps_device_id_and_different_origin_removes_it(self):
        self.settings['sendHwid'] = True
        self.request('/same')
        self.assertEqual(self.received[-1]['x-hwid'], 'fixture-device-id')
        self.request('/different')
        for name in ('x-hwid', 'hwid', 'x-device-os'):
            self.assertNotIn(name, self.received[-1])

    def test_missing_id_suggests_the_setting_when_it_is_off(self):
        with self.assertRaisesRegex(vpn.VpnError, 'Enable hardware ID'):
            self.request('/requires')

    def test_redirect_download_still_enforces_the_size_limit(self):
        with self.assertRaisesRegex(vpn.VpnError, 'too large'):
            self.request('/same', limit=4)

    def test_machine_id_is_scoped_to_the_app(self):
        machine = '00000000000000000000000000000001'
        with patch.object(vpn.Path, 'read_text', return_value=machine):
            first = vpn.hwid()
            self.assertEqual(first, vpn.hwid())
        self.assertEqual(len(first), 64)
        self.assertNotEqual(first, hashlib.sha256(machine.encode()).hexdigest())
        with patch.object(vpn.Path, 'read_text', return_value='uninitialized'):
            self.assertIsNone(vpn.hwid())

    def test_settings_persist_and_reject_invalid_http_header_characters(self):
        with patch.object(vpn, 'status', return_value={'connected': False}):
            vpn.dispatch('settings', {'sendHwid': True, 'userAgent': 'custom/2'})
            self.assertTrue(vpn.model()['sendHwid'])
            self.assertEqual(vpn.model()['userAgent'], 'custom/2')
            for invalid in ('bad\r\nInjected: yes', 'неверный'):
                with self.assertRaisesRegex(vpn.VpnError, 'printable ASCII'):
                    vpn.dispatch('settings', {'sendHwid': False, 'userAgent': invalid})
            self.assertEqual(vpn.model()['userAgent'], 'custom/2')


if __name__ == '__main__':
    unittest.main()
