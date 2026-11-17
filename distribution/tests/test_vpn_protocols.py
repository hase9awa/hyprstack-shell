#!/usr/bin/env python3
"""Naive imports; optional real HTTP/2 and HTTP/3 transport with a local TLS server.

HYPRSTACK_TEST_NAIVE_CORE=/path/to/sing-box python3 distribution/tests/test_vpn_protocols.py
"""
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'shell/assets'))
import vpn
from vpn_profiles import parse, ProfileError


def free_port():
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0))
        return reservation.getsockname()[1]


class NaiveImports(unittest.TestCase):
    def test_https_quic_credentials_ipv6_and_headers(self):
        for scheme in ('naive+https', 'naive+quic', 'naive'):
            profile = parse(scheme + '://a%40b:p%3Aa%2Fss@[::1]?sni=example.com&extra-headers=X-Test%3A%20yes%0D%0AX-Other%3A%20value#Demo%20name')[0]
            self.assertEqual((profile['type'], profile['engine'], profile['name']), ('naive', 'sing-box', 'Demo name'))
            outbound = profile['outbound']
            self.assertEqual((outbound['server'], outbound['server_port']), ('::1', 443))
            self.assertEqual((outbound['username'], outbound['password']), ('a@b', 'p:a/ss'))
            self.assertEqual(outbound.get('quic', False), scheme == 'naive+quic')
            self.assertEqual(outbound['tls'], {'enabled': True, 'server_name': 'example.com'})
            self.assertEqual(outbound['extra_headers'], {'X-Test': 'yes', 'X-Other': 'value'})

    def test_native_json_original_client_json_and_mixed_subscription(self):
        self.assertEqual(parse(json.dumps({'type': 'naive', 'server': 'example.com', 'tls': {'enabled': True}}))[0]['engine'], 'sing-box')
        self.assertEqual(parse(json.dumps({'proxy': 'quic://u:p@example.com', 'extra-headers': 'X-Test: yes'}))[0]['outbound']['extra_headers'], {'X-Test': 'yes'})
        text = 'naive+https://u:p@example.com#Naive\ntrojan://secret@example.com#Trojan'
        for value in (text, base64.b64encode(text.encode()).decode()):
            self.assertEqual([p['type'] for p in parse(value)], ['naive', 'trojan'])

    def test_invalid_security_options_are_not_silently_accepted(self):
        for link in ('naive+https://example.com?insecure=1', 'naive+https://example.com:0',
                     'naive+https://example.com?extra-headers=invalid'):
            with self.assertRaises(ProfileError):
                parse(link)

    def test_runtime_detection_distinguishes_missing_cronet_and_cgo(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'sing-box'
            with patch.object(vpn.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'with_naive_outbound\nCGO: disabled')):
                self.assertFalse(vpn.naive_runtime_ready(path))
            with patch.object(vpn.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'with_naive_outbound\nCGO: enabled')):
                self.assertTrue(vpn.naive_runtime_ready(path))


@unittest.skipUnless(os.environ.get('HYPRSTACK_TEST_NAIVE_CORE'), 'set HYPRSTACK_TEST_NAIVE_CORE for transport tests')
class NaiveTransport(unittest.TestCase):
    def test_http2_http3_authentication_and_certificate_verification(self):
        core = str(Path(os.environ['HYPRSTACK_TEST_NAIVE_CORE']).resolve())
        processes = []
        logs = []
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'naive-transport-fixture')
        target = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        worker = threading.Thread(target=target.serve_forever, daemon=True)
        worker.start()
        with tempfile.TemporaryDirectory(prefix='hs-naive-transport-') as tmp:
            directory = Path(tmp)
            def openssl(*args):
                subprocess.run(['openssl', *args], cwd=directory, capture_output=True, check=True)
            openssl('req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', '-subj', '/CN=Naive fixture CA', '-keyout', 'ca.key', '-out', 'ca.crt')
            openssl('req', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=localhost', '-keyout', 'server.key', '-out', 'server.csr')
            (directory / 'extensions').write_text('subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n')
            openssl('x509', '-req', '-in', 'server.csr', '-CA', 'ca.crt', '-CAkey', 'ca.key', '-CAcreateserial', '-days', '2', '-extfile', 'extensions', '-out', 'server.crt')
            def start(name, config, port):
                path = directory / (name + '.json')
                path.write_text(json.dumps(config))
                log = (directory / (name + '.log')).open('w+')
                logs.append(log)
                process = subprocess.Popen([core, 'run', '-c', str(path)], stdout=log, stderr=log)
                processes.append(process)
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        log.seek(0)
                        self.fail(log.read()[-1800:])
                    try:
                        with socket.create_connection(('127.0.0.1', port), timeout=.1):
                            return
                    except OSError:
                        time.sleep(.03)
                self.fail('Private Naive core did not start')
            try:
                server_port = free_port()
                start('server', {'inbounds': [{'type': 'naive', 'listen': '127.0.0.1', 'listen_port': server_port,
                    'users': [{'username': 'fixture', 'password': 'fixture-pass'}],
                    'tls': {'enabled': True, 'certificate_path': str(directory / 'server.crt'), 'key_path': str(directory / 'server.key')}}],
                    'outbounds': [{'type': 'direct'}]}, server_port)
                for label, quic, password, trust in [('http2', False, 'fixture-pass', True), ('http3', True, 'fixture-pass', True),
                        ('bad-password', False, 'incorrect', True), ('untrusted', False, 'fixture-pass', False)]:
                    profile = parse(f'naive+{"quic" if quic else "https"}://fixture:{password}@127.0.0.1:{server_port}')[0]
                    if trust:
                        profile['outbound']['tls']['certificate_path'] = str(directory / 'ca.crt')
                    port = free_port()
                    config = vpn.configuration(profile, port=port, http_port=0)
                    # Force the loopback fixture through the proxy, rather than the LAN bypass.
                    config['route']['rules'] = []
                    start(label, config, port)
                    result = subprocess.run(['curl', '--silent', '--max-time', '4', '--noproxy', '',
                        '--proxy', f'socks5h://127.0.0.1:{port}', f'http://127.0.0.1:{target.server_port}/'], capture_output=True)
                    if password == 'fixture-pass' and trust:
                        self.assertEqual((result.returncode, result.stdout), (0, b'naive-transport-fixture'), label)
                    else:
                        self.assertNotEqual(result.returncode, 0, label + ' must fail')
                    processes[-1].terminate()
                    processes[-1].wait(timeout=5)
            finally:
                for process in processes:
                    if process.poll() is None:
                        process.terminate()
                        process.wait(timeout=5)
                for log in logs:
                    log.close()
                target.shutdown()
                target.server_close()
                worker.join(timeout=2)


if __name__ == '__main__':
    unittest.main()
