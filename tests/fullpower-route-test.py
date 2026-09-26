#!/usr/bin/env python3
"""Real registry/parser with inert authentication backends; no real SSH or keys."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class Routing(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='luffy-route-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.state = self.root / 'state'
        self.scripts = self.root / 'scripts'
        self.scripts.mkdir()
        source = Path(__file__).parents[1] / 'scripts'
        shutil.copy2(source.parent / 'VERSION', self.root / 'VERSION')
        for name in ('luffy-arm', 'fullpower-route.sh', 'power.py', 'targets.py', 'lifecycle.py'):
            shutil.copy2(source / name, self.scripts / name)
        (self.scripts / 'fullpower.sh').write_text(
            '#!/bin/bash\nprintf "key|%s\\n" "$LUFFY_ARM_PARAMS"\nprintf "%s\\n" "$@"\n')
        (self.scripts / 'session.py').write_text('''import json
from lifecycle import SessionError
class Session:
    def __init__(self, target, root=None, recorded=False): self.target=target
    def on(self, password, seconds=None):
        if not password: raise SessionError('Add --password')
        print(json.dumps([self.target, 'on', password, seconds])); return 0
    def off(self): print(json.dumps([self.target, 'off'])); return 0
    def status(self): print(json.dumps([self.target, 'status'])); return 0
''')
        (self.scripts / 'luffy').symlink_to(self.scripts / 'luffy-arm')
        self.params = self.root / 'params.sh'
        self.params.write_text('SERVER=lab.invalid\nSSH_PORT=22\nADMIN_USER=test-user\n'
                               'ADMIN_KEY=/tmp/luffy-fictional-test-key\nADMIN_ALIAS=test-admin\n')
        self.env = dict(os.environ, LUFFY_ARM_STATE_DIR=str(self.state), LUFFY_ARM_PARAMS=str(self.params))
        self.assertEqual(self.invoke('target', 'add', 'lab', '--params', str(self.params), '--name', 'Test Lab').returncode, 0)
        self.assertEqual(self.invoke('target', 'add', 'cluster', '--password', '--host', 'cluster.invalid', '--user', 'test-user').returncode, 0)
        self.assertEqual(self.invoke('target', 'default', 'lab').returncode, 0)

    def invoke(self, *args, alias='luffy'):
        return subprocess.run(['bash', str(self.scripts / alias), *args], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def test_key_target_plus_duration_and_default_compatibility(self):
        for args in [('on', 'lab', '120000'), ('on', '120000'), ('on', 'lab', '1d9h20m')]:
            with self.subTest(args=args):
                result = self.invoke('fullpower', *args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('Target: lab', result.stdout)
                self.assertEqual(result.stdout.splitlines()[-2:], ['on', '120000'])
                self.assertIn('key|' + str(self.params.resolve()), result.stdout)

    def test_password_duration_flag_orders_and_both_aliases(self):
        for alias in ('luffy', 'luffy-arm'):
            for args in [('on', 'cluster', '--password', '120000'),
                         ('on', 'cluster', '120000', '--password'),
                         ('on', '--password', 'cluster', '120000')]:
                with self.subTest(args=args, alias=alias):
                    result = self.invoke('fullpower', *args, alias=alias)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(json.loads(result.stdout.splitlines()[-1]), ['cluster', 'on', True, 120000])

    def test_switches_and_shortcuts(self):
        for op in ('off', 'status'):
            result = self.invoke('fullpower', op, 'cluster')
            self.assertEqual(json.loads(result.stdout.splitlines()[-1]), ['cluster', op])
        result = self.invoke('fullpower-on', 'lab', '3600')
        self.assertEqual(result.stdout.splitlines()[-2:], ['on', '3600'])
        result = self.invoke('fullpower-off', 'cluster')
        self.assertEqual(json.loads(result.stdout.splitlines()[-1]), ['cluster', 'off'])

    def test_missing_flag_and_wrong_mode_fail(self):
        self.assertIn('Add --password', self.invoke('fullpower', 'on', 'cluster', '120000').stderr)
        result = self.invoke('fullpower', 'on', 'lab', '--password')
        self.assertEqual(result.returncode, 2)
        self.assertNotIn('key|', result.stdout)

    def test_invalid_duration_or_extra_args_never_reach_backend(self):
        for args in [('on', 'lab', '0'), ('on', 'lab', '-1'), ('on', 'lab', '12x'),
                     ('on', 'cluster', '--password', '9999999999999'),
                     ('on', 'lab', '20', '30'), ('status', 'lab', '20'),
                     ('off', 'cluster', '--password'), ('on', '--all'),
                     ('on', 'cluster', '--password=secret')]:
            with self.subTest(args=args):
                result = self.invoke('fullpower', *args)
                self.assertEqual(result.returncode, 2)
                self.assertNotIn('key|', result.stdout)
                self.assertNotIn('["cluster"', result.stdout)

    def test_unknown_target_has_discovery_hint_no_fallback(self):
        result = self.invoke('fullpower', 'on', 'not-registered', '120000')
        self.assertEqual(result.returncode, 2)
        self.assertIn('luffy tlist', result.stderr)
        self.assertNotIn('key|', result.stdout)
        self.assertNotIn('No such file', result.stderr)

    def test_list_contains_equal_target_rows_and_default_without_authentication(self):
        result = self.invoke('tlist')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(result.stdout, r'lab\s+Test Lab\s+key\s+test-user@lab.invalid:22\s+\*')
        self.assertRegex(result.stdout, r'cluster\s+cluster\s+password')
        self.assertNotIn('key|', result.stdout)

    def test_default_can_be_any_target_and_is_required_when_ambiguous(self):
        self.invoke('target', 'default', 'cluster')
        result = self.invoke('fullpower', 'on', '--password', '120000')
        self.assertEqual(json.loads(result.stdout.splitlines()[-1]), ['cluster', 'on', True, 120000])
        (self.state / 'default-target.json').unlink()
        result = self.invoke('fullpower', 'on', '120000')
        self.assertEqual(result.returncode, 2)
        self.assertIn('Choose a TARGET', result.stderr)
        self.assertNotIn('key|', result.stdout)

    def test_all_targets_each_key_once(self):
        for op in ('status', 'off'):
            result = self.invoke('fullpower', op, '--all')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('["cluster", "' + op + '"]', result.stdout)
            self.assertEqual(result.stdout.count('key|'), 1 if op == 'status' else 2)
            self.assertNotIn('Legacy unregistered', result.stdout)

    def test_registration_idempotent_and_no_overwrite(self):
        path = self.state / 'targets/cluster.json'
        original = path.read_bytes()
        result = self.invoke('target', 'add', 'cluster', '--password', '--host', 'cluster.invalid', '--user', 'test-user')
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.invoke('target', 'add', 'cluster', '--password', '--host', 'other.invalid', '--user', 'test-user')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(path.read_bytes(), original)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_duplicate_key_target_rejected(self):
        result = self.invoke('target', 'add', 'duplicate', '--params', str(self.params))
        self.assertEqual(result.returncode, 2)
        self.assertIn('already registered', result.stderr)
        self.assertFalse((self.state / 'targets/duplicate.json').exists())

    def test_second_key_target_uses_its_own_params(self):
        second = self.root / 'second.sh'
        second.write_text(self.params.read_text().replace('lab.invalid', 'second.invalid').replace('fictional-test-key', 'second-test-key'))
        self.assertEqual(self.invoke('target', 'add', 'second', '--params', str(second)).returncode, 0)
        result = self.invoke('fullpower', 'on', 'second', '60')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('key|' + str(second.resolve()), result.stdout)
        self.assertNotIn('key|' + str(self.params.resolve()), result.stdout)
        result = self.invoke('fullpower', 'status', '--all')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count('key|'), 2)

    def test_display_name_update_preserves_connection_and_default(self):
        result = self.invoke('target', 'add', 'lab', '--params', str(self.params), '--name', '实验室服务器')
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.invoke('tlist')
        self.assertIn('实验室服务器', result.stdout)
        self.assertIn('test-user@lab.invalid', result.stdout)
        self.assertEqual(json.loads((self.state / 'default-target.json').read_text())['target'], 'lab')

    def test_edited_params_cannot_silently_select_another_host(self):
        self.params.write_text(self.params.read_text().replace('lab.invalid', 'wrong.invalid'))
        result = self.invoke('fullpower', 'on', 'lab', '120000')
        self.assertEqual(result.returncode, 2)
        self.assertIn('refusing', result.stderr)
        self.assertNotIn('key|', result.stdout)
        result = self.invoke('fullpower', 'off', '--all')
        self.assertEqual(result.returncode, 4)
        self.assertNotIn('key|', result.stdout)


if __name__ == '__main__':
    unittest.main()
