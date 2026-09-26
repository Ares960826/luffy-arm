#!/usr/bin/env python3
"""Process-level lifecycle tests with a local fake SSH mux, no remote authentication."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest

FAKE_SSH = r'''#!/usr/bin/env python3
import os, socket, subprocess, sys, time
from pathlib import Path
if sys.argv[1] == '--master':
    path = Path(sys.argv[2])
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(path)); server.listen(20); server.settimeout(.2)
        deadline = time.time() + 30
        while time.time() < deadline:
            try:
                client, _ = server.accept()
            except socket.timeout:
                continue
            with client:
                data = client.recv(100)
                if data == b'exit':
                    break
                if data:
                    client.sendall(b'test-user\n')
    path.unlink(missing_ok=True)
    sys.exit(0)
args = sys.argv[1:]
path = Path(args[args.index('-S') + 1])
if '-f' in args:
    with open(os.environ['LUFFY_TEST_STARTS'], 'a') as output:
        output.write('start\n')
    time.sleep(.25)  # Represents interactive authentication still in progress.
    subprocess.Popen([sys.executable, __file__, '--master', str(path)],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    deadline = time.time() + 5
    while not path.exists() and time.time() < deadline:
        time.sleep(.01)
    sys.exit(0 if path.exists() else 1)
with socket.socket(socket.AF_UNIX) as client:
    client.settimeout(3); client.connect(str(path))
    client.sendall(b'exit' if '-O' in args else b'id')
    if '-O' not in args:
        sys.stdout.write(client.recv(100).decode())
'''


class Background(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='luffy-bg-', dir='/tmp')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.scripts = Path(__file__).parents[1] / 'scripts'
        self.env = dict(os.environ, LUFFY_ARM_STATE_DIR=str(self.root),
                        LUFFY_ARM_PARAMS=str(self.root / 'absent'),
                        LUFFY_TEST_STARTS=str(self.root / 'starts'))
        self.env['PATH'] = str(self.root) + ':' + self.env['PATH']
        (self.root / 'ssh').write_text(FAKE_SSH)
        (self.root / 'ssh').chmod(0o700)
        (self.root / 'targets').mkdir(mode=0o700)
        for target in ('one', 'two'):
            profile = self.root / 'targets' / (target + '.json')
            profile.write_text(json.dumps(dict(host=target + '.invalid', user='test-user')))
            profile.chmod(0o600)
        self.addCleanup(self.shutdown)

    def launch(self, target, seconds=None):
        # Fake authentication only. The human-terminal guard is covered separately.
        code = ('import sys; sys.path.insert(0, sys.argv[1]); import power; '
                'sys.stdin.isatty=lambda: True; sys.stdout.isatty=lambda: True; '
                'sys.exit(power.main(["on",sys.argv[2],"--password"]+sys.argv[3:]))')
        args = [] if seconds is None else [str(seconds)]
        return subprocess.Popen([sys.executable, '-c', code, str(self.scripts), target, *args],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, env=self.env)

    def command(self, *args):
        return subprocess.run(['bash', str(self.scripts / 'luffy-arm'), *args],
                              capture_output=True, text=True, env=self.env, timeout=10)

    def shutdown(self):
        self.command('fullpower', 'off', '--all')

    def test_background_survives_launcher_and_duplicate_on_then_off_all(self):
        first = self.launch('one')
        stdout, stderr = first.communicate(timeout=10)
        self.assertEqual(first.returncode, 0, stderr)
        self.assertIn('background', stdout)
        second = self.launch('one')
        stdout, stderr = second.communicate(timeout=10)
        self.assertEqual(second.returncode, 0, stderr)
        self.assertIn('reusing', stdout)
        third = self.launch('two')
        third.communicate(timeout=10)
        self.assertEqual(third.returncode, 0)
        self.assertEqual((self.root / 'starts').read_text().splitlines(), ['start', 'start'])
        result = self.command('fullpower', 'status', '--all')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count('SESSION ON'), 2)
        records = [json.loads(path.read_text()) for path in (self.root / 'sessions').glob('*.json')]
        result = self.command('fullpower', 'off', '--all')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(list((self.root / 'sessions').glob('*.json')))
        for record in records:
            self.assertFalse(Path(record['socket']).exists())
            self.assertFalse(Path(record['socket']).parent.exists())

    def test_simultaneous_on_creates_only_one_master(self):
        first, second = self.launch('one'), self.launch('one')
        first.communicate(timeout=10)
        second.communicate(timeout=10)
        self.assertIn(0, [first.returncode, second.returncode])
        self.assertEqual((self.root / 'starts').read_text().splitlines(), ['start'])
        self.assertEqual(self.command('fullpower', 'status', 'one').returncode, 0)

    def wait_until(self, check, timeout=6):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if check():
                return
            time.sleep(.05)
        self.assertTrue(check(), 'Timed out waiting for lifecycle cleanup')

    @staticmethod
    def process_exited(pid):
        result = subprocess.run(['ps', '-p', str(pid), '-o', 'stat='], capture_output=True, text=True)
        return result.returncode != 0 or result.stdout.strip().startswith('Z')

    def test_absolute_duration_expires_without_further_cli_calls(self):
        child = self.launch('one', 2)
        stdout, stderr = child.communicate(timeout=10)
        self.assertEqual(child.returncode, 0, stderr)
        self.assertIn('expires', stdout)
        record = self.root / 'sessions/one.json'
        data = json.loads(record.read_text())
        self.assertIn('timer_pid', data)
        self.wait_until(lambda: not record.exists())
        self.assertFalse(Path(data['socket']).exists())
        self.assertFalse(Path(data['socket']).parent.exists())
        self.wait_until(lambda: self.process_exited(data['timer_pid']))

    def test_early_off_stops_timer_and_old_timer_cannot_close_replacement(self):
        first = self.launch('one', 2)
        first.communicate(timeout=10)
        self.assertEqual(first.returncode, 0)
        record = self.root / 'sessions/one.json'
        old = json.loads(record.read_text())
        self.assertEqual(self.command('fullpower', 'off', 'one').returncode, 0)
        second = self.launch('one', 8)
        second.communicate(timeout=10)
        self.assertEqual(second.returncode, 0)
        new = json.loads(record.read_text())
        duplicate = self.launch('one', 120000)
        duplicate.communicate(timeout=10)
        self.assertEqual(duplicate.returncode, 0)
        self.assertEqual(json.loads(record.read_text())['expires_at'], new['expires_at'])
        self.wait_until(lambda: self.process_exited(old['timer_pid']))
        time.sleep(max(0, old['expires_at'] - time.time()) + .2)
        self.assertEqual(self.command('fullpower', 'status', 'one').returncode, 0)
        self.assertEqual(self.command('fullpower', 'off', '--all').returncode, 0)
        self.wait_until(lambda: self.process_exited(new['timer_pid']))
        self.assertFalse(record.exists())

    def test_cli_all_off_reports_bad_record_without_crashing_and_cleans_other_target(self):
        child = self.launch('two')
        child.communicate(timeout=10)
        bad = self.root / 'sessions/one.json'
        bad.write_text(json.dumps({'profile': {'password': 'invalid-test-field'}}))
        bad.chmod(0o600)
        result = self.command('fullpower', 'off', '--all')
        self.assertEqual(result.returncode, 4)
        self.assertIn('INCOMPLETE: one', result.stdout)
        self.assertNotIn('Traceback', result.stderr)
        self.assertFalse((self.root / 'sessions/two.json').exists())
        bad.unlink()


if __name__ == '__main__':
    unittest.main()
