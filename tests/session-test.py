#!/usr/bin/env python3
"""Local-only session routing and lifecycle tests; never contacts a server."""
import importlib.util
import io
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
import lifecycle
spec = importlib.util.spec_from_file_location('session', Path(__file__).parents[1] / 'scripts/session.py')
mod = importlib.util.module_from_spec(spec)
sys.modules['session'] = mod
spec.loader.exec_module(mod)


class Sessions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='luffy-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        environment = patch.dict(os.environ, {'LUFFY_ARM_STATE_DIR': str(self.root),
                                              'LUFFY_ARM_PARAMS': str(self.root / 'missing-params')})
        environment.start()
        self.addCleanup(environment.stop)
        (self.root / 'targets').mkdir(mode=0o700)
        self.sockets = []
        for name in ('one', 'two'):
            path = self.root / 'targets' / (name + '.json')
            path.write_text(json.dumps({'host': name + '.invalid', 'user': 'test-user', 'port': 22}))
            path.chmod(0o600)
        self.first = mod.Session('one', self.root)
        self.second = mod.Session('two', self.root)

    def make_socket(self, session):
        directory = self.root / session.target
        directory.mkdir(mode=0o700)
        path = directory / 'control'
        connection = socket.socket(socket.AF_UNIX)
        connection.bind(str(path))
        connection.listen(20)
        self.addCleanup(connection.close)
        with session.lock():
            session.save(path, owned=False)
        return path

    def success(self, *args, **kwargs):
        return subprocess.CompletedProcess(args[0], 0, 'test-user\n', '')

    def test_no_record_does_not_launch_ssh(self):
        with patch.object(mod.subprocess, 'run') as runner:
            self.assertEqual(self.first.status(), 3)
            runner.assert_not_called()

    def test_target_mismatch_blocks_command(self):
        self.make_socket(self.first)
        changed = self.first.read()
        changed['profile']['host'] = 'two.invalid'
        self.first.record.write_text(json.dumps(changed))
        with patch.object(mod.subprocess, 'run') as runner:
            with self.assertRaises(mod.SessionError):
                self.first.run('pwd')
            runner.assert_not_called()

    def test_wrong_identity_blocks_command(self):
        self.make_socket(self.first)
        with patch.object(mod.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'wrong\n', '')), patch.object(mod.subprocess, 'call') as runner:
            with self.assertRaises(mod.SessionError):
                self.first.run('pwd')
            runner.assert_not_called()

    def test_closed_socket_cannot_reauthenticate(self):
        path = self.make_socket(self.first)
        path.unlink()
        with patch.object(mod.subprocess, 'run') as runner:
            self.assertEqual(self.first.status(), 3)
            with self.assertRaises(FileNotFoundError):
                self.first.run('pwd')
            runner.assert_not_called()

    def test_on_requires_terminal(self):
        with patch.object(mod.sys.stdin, 'isatty', return_value=False), patch.object(mod.subprocess, 'Popen') as runner:
            with self.assertRaises(mod.SessionError):
                self.first.on(True)
            runner.assert_not_called()

    def test_on_requires_explicit_password_option(self):
        with patch.object(mod.subprocess, 'Popen') as runner:
            with self.assertRaisesRegex(mod.UsageHint, 'luffy fullpower on one --password'):
                self.first.on(False)
            runner.assert_not_called()
        self.assertFalse(self.first.record.exists())

    def test_missing_password_flag_prints_hint_without_changing_session(self):
        self.make_socket(self.first)
        original = self.first.record.read_bytes()
        output = io.StringIO()
        with patch.object(mod, 'Session', return_value=self.first), \
                patch.object(mod.sys, 'argv', ['session.py', 'on', 'one']), \
                patch.object(mod.sys, 'stderr', output), \
                patch.object(mod.subprocess, 'Popen') as launcher, \
                patch.object(mod.subprocess, 'run') as runner:
            self.assertEqual(mod.main(), 2)
            launcher.assert_not_called()
            runner.assert_not_called()
        self.assertIn('one uses password login. Add --password:', output.getvalue())
        self.assertIn('luffy fullpower on one --password', output.getvalue())
        self.assertNotIn('NOT VERIFIED', output.getvalue())
        self.assertEqual(self.first.record.read_bytes(), original)

    def test_second_on_does_not_start_competing_login(self):
        with self.first.lock():
            self.first.save(self.root / 'missing', owned=True)
        with patch.object(mod.sys.stdin, 'isatty', return_value=True), patch.object(mod.sys.stdout, 'isatty', return_value=True), patch.object(mod.subprocess, 'Popen') as runner:
            with self.assertRaises(mod.SessionError):
                self.first.on(True)
            runner.assert_not_called()
        self.assertEqual(self.first.status(), 4)

    def test_private_socket_parent_required(self):
        path = self.make_socket(self.first)
        path.parent.chmod(0o755)
        with self.assertRaises(mod.SessionError):
            self.first.verify(path)

    def test_two_targets_and_off_isolation(self):
        one = self.make_socket(self.first)
        two = self.make_socket(self.second)
        def execute(command, **kwargs):
            if '-O' in command:
                self.assertEqual(command[-1], 'one.invalid')
                one.unlink()
            return self.success(command)
        with patch.object(mod.subprocess, 'run', side_effect=execute), patch.object(mod.subprocess, 'call', return_value=0) as runner:
            self.assertEqual(self.first.status(), 0)
            self.assertEqual(self.second.status(), 0)
            self.second.run('pwd')
            command = runner.call_args[0][0]
            self.assertEqual(command[-2:], ['two.invalid', 'pwd'])
            self.assertIn(str(two), command)
            for option in ['ProxyCommand=false', 'BatchMode=yes', 'PasswordAuthentication=no', 'PubkeyAuthentication=no']:
                self.assertIn(option, command)
            self.first.off()
            self.assertTrue(two.exists())
            self.assertTrue(self.second.record.exists())
            self.assertFalse(self.first.record.exists())
            self.assertEqual(self.second.status(), 0)

    def test_on_lifecycle_and_authentication_arguments(self):
        child = unittest.mock.Mock()
        child.poll.return_value = 0
        child.returncode = 0
        def detached():
            path = Path(self.first.read()['socket'])
            connection = socket.socket(socket.AF_UNIX)
            connection.bind(str(path))
            connection.listen(20)
            self.addCleanup(connection.close)
            self.addCleanup(lambda: path.parent.rmdir())
            self.addCleanup(path.unlink)
            return 0
        child.wait.side_effect = detached
        with patch.object(mod.sys.stdin, 'isatty', return_value=True), patch.object(mod.sys.stdout, 'isatty', return_value=True), patch.object(mod.subprocess, 'run', side_effect=self.success), patch.object(mod.subprocess, 'Popen', return_value=child) as runner:
            self.assertEqual(self.first.on(True), 0)
            command = runner.call_args[0][0]
            for option in ['IdentityAgent=none', 'PubkeyAuthentication=no', 'ControlPersist=no', 'PreferredAuthentications=keyboard-interactive,password']:
                self.assertIn(option, command)
            self.assertNotIn('stdin', runner.call_args[1])
            self.assertNotIn('stdout', runner.call_args[1])
            self.assertEqual(runner.call_args[1]['env']['SSH_ASKPASS_REQUIRE'], 'never')
            self.assertIn('-f', command)
            self.assertTrue(self.first.record.exists())
            self.assertTrue(self.first.read()['background'])
            self.assertIsNone(self.first.read()['launcher_pid'])
            before = self.first.record.read_bytes()
            self.assertEqual(self.first.on(True), 0)
            runner.assert_called_once()
            self.assertEqual(self.first.record.read_bytes(), before)

    def test_failed_login_leaves_no_record_or_directory(self):
        child = unittest.mock.Mock()
        child.wait.return_value = 255
        child.poll.return_value = 255
        with patch.object(mod.sys.stdin, 'isatty', return_value=True), patch.object(mod.sys.stdout, 'isatty', return_value=True), patch.object(mod.subprocess, 'Popen', return_value=child) as runner:
            with self.assertRaises(mod.SessionError):
                self.first.on(True)
        command = runner.call_args[0][0]
        path = Path(command[command.index('-S') + 1])
        self.assertFalse(self.first.record.exists())
        self.assertFalse(path.parent.exists())

    def test_kernel_locks_block_concurrent_on_and_shutdown(self):
        with self.first.lock(), patch.object(mod.sys.stdin, 'isatty', return_value=True), patch.object(mod.sys.stdout, 'isatty', return_value=True), patch.object(mod.subprocess, 'Popen') as runner:
            with self.assertRaisesRegex(mod.SessionError, 'in progress'):
                self.first.on(True)
            runner.assert_not_called()
        with lifecycle.lock(self.root, 'lifecycle.lock', shared=True):
            with self.assertRaises(mod.SessionError):
                lifecycle.all_targets('off', self.root)
        # Locks are released, not left as stale PID blockers.
        self.assertEqual(lifecycle.all_targets('off', self.root), 0)

    def test_all_off_closes_recorded_targets_even_with_changed_or_deleted_profiles(self):
        one = self.make_socket(self.first)
        two = self.make_socket(self.second)
        (self.root / 'targets/one.json').unlink()
        (self.root / 'targets/two.json').write_text('{}')
        unrelated = self.root / 'unrelated'
        unrelated.write_text('preserve')
        def execute(command, **kwargs):
            self.assertIn('-O', command)  # OFF does not depend on remote id/availability.
            Path(command[command.index('-S') + 1]).unlink()
            return self.success(command)
        with patch.object(mod.subprocess, 'run', side_effect=execute) as runner:
            self.assertEqual(lifecycle.all_targets('off', self.root), 0)
            self.assertEqual(runner.call_count, 2)
        self.assertFalse(one.exists())
        self.assertFalse(two.exists())
        self.assertFalse(self.first.record.exists())
        self.assertFalse(self.second.record.exists())
        self.assertEqual(unrelated.read_text(), 'preserve')

    def test_all_off_continues_after_error_and_preserves_failed_record(self):
        one = self.make_socket(self.first)
        two = self.make_socket(self.second)
        def execute(command, **kwargs):
            path = Path(command[command.index('-S') + 1])
            if path == one:
                raise subprocess.TimeoutExpired(command, 15)
            path.unlink()
            return self.success(command)
        with patch.object(mod.subprocess, 'run', side_effect=execute):
            self.assertEqual(lifecycle.all_targets('off', self.root), 4)
        self.assertTrue(one.exists())
        self.assertTrue(self.first.record.exists())
        self.assertFalse(two.exists())
        self.assertFalse(self.second.record.exists())

    def test_off_missing_socket_cleans_owned_empty_directory(self):
        directory = Path(tempfile.mkdtemp(prefix='luffy-session-', dir=self.root))
        with self.first.lock():
            self.first.save(directory / 'control', owned=True, background=True)
        self.assertEqual(self.first.off(), 0)
        self.assertFalse(directory.exists())
        self.assertFalse(self.first.record.exists())

    def test_off_cleans_refused_stale_socket_without_ssh(self):
        directory = self.root / 'stale'
        directory.mkdir(mode=0o700)
        path = directory / 'control'
        with socket.socket(socket.AF_UNIX) as connection:
            connection.bind(str(path))
        with self.first.lock():
            self.first.save(path, owned=False)
        with patch.object(mod.subprocess, 'run') as runner:
            self.assertEqual(self.first.off(), 0)
            runner.assert_not_called()
        self.assertFalse(path.exists())
        self.assertFalse(self.first.record.exists())

    def test_all_off_reports_alternate_credentials_and_key_failures(self):
        (self.root / 'params').touch()
        with patch.dict(os.environ, {'LUFFY_ARM_PARAMS': str(self.root / 'params')}):
            for key_rc in (0, 3, 4):
                with self.subTest(key_rc=key_rc), patch.object(lifecycle, 'key_command', side_effect=[0, key_rc]) as key:
                    self.assertEqual(lifecycle.all_targets('off', self.root), 0 if key_rc == 0 else 4)
                    self.assertEqual(key.call_args_list, [unittest.mock.call('close-safe'), unittest.mock.call('off')])

    def test_no_credentials_in_profile(self):
        path = self.root / 'targets/one.json'
        data = json.loads(path.read_text())
        data['password'] = 'not-a-real-secret'
        path.write_text(json.dumps(data))
        with self.assertRaises(mod.SessionError):
            mod.Session('one', self.root)

    def test_expired_session_cannot_run_even_if_timer_has_not_cleaned_up(self):
        self.make_socket(self.first)
        data = self.first.read()
        data['expires_at'] = 1
        self.first.record.write_text(json.dumps(data))
        with patch.object(mod.subprocess, 'run') as verify, patch.object(mod.subprocess, 'call') as execute:
            with self.assertRaisesRegex(mod.SessionError, 'expired'):
                self.first.run('pwd')
            verify.assert_not_called()
            execute.assert_not_called()

    def test_registered_metadata_does_not_invalidate_existing_connection(self):
        self.make_socket(self.first)
        path = self.root / 'targets/one.json'
        profile = json.loads(path.read_text())
        profile.update(auth='password', name='First server')
        path.write_text(json.dumps(profile))
        self.assertEqual(mod.Session('one', self.root).read()['profile'], self.first.profile)


if __name__ == '__main__':
    unittest.main()
