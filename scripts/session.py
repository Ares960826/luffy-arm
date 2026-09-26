#!/usr/bin/env python3
"""Per-target, user-authenticated SSH sessions. Password input belongs to SSH only."""
import argparse
import contextlib
import json
import os
from pathlib import Path
import re
import select
import socket as socketlib
import stat
import subprocess
import sys
import tempfile
import time
import uuid
from lifecycle import SessionError, private_path, state_root, lock as lifecycle_lock
import targets


class UsageHint(SessionError):
    pass


def check_socket(path):
    if not path.is_absolute():
        raise SessionError('Socket path must be absolute')
    private_path(path.parent, directory=True)
    info = path.lstat()
    if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid():
        raise SessionError('Socket is not owned by this user or is not a socket')


class Session:
    def __init__(self, target, root=None, recorded=False):
        if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,47}', target):
            raise SessionError('Invalid target ID')
        self.target = target
        self.root = root or state_root()
        self.states = self.root / 'sessions'
        self.record = self.states / (target + '.json')
        profile = self.root / 'targets' / (target + '.json')
        if recorded:
            private_path(self.states, directory=True)
            private_path(self.record)
            registered = json.loads(self.record.read_text())
            if not isinstance(registered, dict):
                raise SessionError('Invalid session record')
            self.profile = registered['profile']
        else:
            registered = targets.load(target, self.root)
            if registered['auth'] != 'password':
                raise SessionError(f'{target} is a key target; use luffy fullpower on/status/off {target}')
            self.profile = targets.connection(registered)
        if not isinstance(self.profile, dict) or set(self.profile) - {'host', 'user', 'port'}:
            raise SessionError('Target profile accepts only host, user and port; never passwords')
        host, user = self.profile.get('host', ''), self.profile.get('user', '')
        if not isinstance(host, str) or not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9.:-]*', host):
            raise SessionError('Invalid host')
        if not isinstance(user, str) or not re.fullmatch(r'[a-zA-Z0-9_][a-zA-Z0-9_.-]*', user):
            raise SessionError('Invalid user')
        port = self.profile.setdefault('port', 22)
        if type(port) is not int or not 1 <= port <= 65535:
            raise SessionError('Invalid port')

    @contextlib.contextmanager
    def lock(self):
        with lifecycle_lock(self.states, self.target + '.lock'):
            yield

    def read(self):
        private_path(self.record)
        data = json.loads(self.record.read_text())
        if not isinstance(data, dict) or not isinstance(data.get('socket'), str) or not Path(data['socket']).is_absolute():
            raise SessionError('Invalid session record/socket')
        if data.get('target') != self.target or data.get('profile') != self.profile:
            raise SessionError('Session target/profile changed; refusing to reuse it')
        return data

    def save(self, socket, owned, background=False, seconds=None):
        data = {'target': self.target, 'profile': self.profile,
                'socket': str(socket), 'owned': owned,
                'launcher_pid': os.getpid() if owned and not background else None,
                'background': background, 'generation': uuid.uuid4().hex,
                'expires_at': None if seconds is None else time.time() + seconds,
                'expires_monotonic': None if seconds is None else time.monotonic() + seconds}
        # Caller holds the per-target lock; readers see an atomic update.
        fd, tmp = tempfile.mkstemp(dir=self.states, prefix=self.target + '.')
        try:
            with os.fdopen(fd, 'w') as handle:
                json.dump(data, handle)
                handle.write('\n')
            os.replace(tmp, self.record)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)

    def base(self, socket):
        # Do not inherit another target's identities, proxies or master settings.
        return ['ssh', '-F', '/dev/null', '-S', str(socket),
                '-l', self.profile['user'], '-p', str(self.profile['port']),
                '-o', 'StrictHostKeyChecking=yes', '-o', 'UpdateHostKeys=no',
                '-o', 'ForwardAgent=no', '-o', 'ForwardX11=no',
                '-o', 'ClearAllForwardings=yes', '-o', 'ConnectTimeout=8',
                '-o', 'ConnectionAttempts=1']

    def reuse(self, socket):
        return self.base(socket) + [
            '-o', 'ControlMaster=no', '-o', 'ProxyCommand=false',
            '-o', 'BatchMode=yes', '-o', 'PubkeyAuthentication=no',
            '-o', 'PasswordAuthentication=no', '-o', 'KbdInteractiveAuthentication=no',
            '-o', 'GSSAPIAuthentication=no', '-o', 'HostbasedAuthentication=no',
            self.profile['host']]

    def verify(self, socket):
        check_socket(socket)
        result = subprocess.run(self.reuse(socket) + ['id -un'],
                                capture_output=True, text=True, timeout=15)
        if result.returncode or result.stdout.strip() != self.profile['user']:
            raise SessionError('Session identity/transport not verified; no login fallback. '
                               + result.stderr.strip())

    @staticmethod
    def launcher_alive(data):
        pid = data.get('launcher_pid')
        if type(pid) is not int or pid <= 0:
            return False
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False

    def status(self):
        data = None
        try:
            data = self.read()
            if self.expired(data):
                print(f'{self.target}: EXPIRED | commands blocked; cleanup pending or complete. Use OFF if needed.')
                return 4
            self.verify(Path(data['socket']))
        except FileNotFoundError:
            if data and self.launcher_alive(data):
                print(f'{self.target}: SESSION STARTING/UNKNOWN; check the user login terminal')
                return 4
            print(f'{self.target}: SESSION OFF (no recorded socket); user runs: '
                  f'luffy fullpower on {self.target} --password')
            return 3
        mode = 'background; terminal may close' if data.get('background') else 'existing foreground/external session'
        print(f'{self.target}: SESSION ON | {mode} | {self.profile["user"]}@{self.profile["host"]}'
              ' | permissions follow the remote account')
        print(f'   Lifetime: {self.lifetime(data)}')
        return 0

    @staticmethod
    def expired(data):
        return ((data.get('expires_at') is not None and time.time() >= data['expires_at']) or
                (data.get('expires_monotonic') is not None and time.monotonic() >= data['expires_monotonic']))

    @staticmethod
    def lifetime(data):
        if data.get('expires_at') is None:
            return 'until OFF or disconnect (no timer)'
        remaining = max(0, int(data['expires_at'] - time.time()))
        deadline = time.strftime('%Y-%m-%d %H:%M:%S %Z', time.localtime(data['expires_at']))
        return f'{remaining}s remaining; expires {deadline}'

    def attach(self, socket):
        # Explicit migration of a user-authenticated, user-selected connection only.
        with self.lock():
            if self.record.exists():
                old = self.read()
                if self.launcher_alive(old) and not Path(old['socket']).exists():
                    raise SessionError('A login is starting; check its terminal first')
                if old['socket'] != str(socket) and Path(old['socket']).exists():
                    raise SessionError('Another session is recorded; close it explicitly first')
            self.verify(socket)
            self.save(socket, owned=False)
        return self.status()

    def on(self, password, seconds=None):
        if seconds is not None:
            seconds = targets.duration(seconds)
        if not password:
            raise UsageHint(
                f'{self.target} uses password login. Add --password:\n'
                f'  luffy fullpower on {self.target} --password{(" " + str(seconds)) if seconds is not None else ""}\n'
                'Enter your password only at the SSH prompt, not in the command.')
        if not sys.stdin.isatty() or not sys.stdout.isatty():
            raise SessionError('ON requires the user in an interactive local terminal')
        with self.lock():
            if self.record.exists():
                old = self.read()
                old_socket = Path(old['socket'])
                if old_socket.exists() and self.socket_listening(old_socket) and not self.expired(old):
                    print(f'{self.target}: reusing existing connection; no password needed, '
                          'no new process or lifetime renewal.')
                    return self.status()
                if self.launcher_alive(old):
                    raise SessionError('A login is already starting; check its terminal first')
                if old_socket.exists():
                    self.close_socket(old_socket)
                self.cleanup(old)
                # Missing socket cannot authenticate; replacing only this target is safe.
            socket = Path(tempfile.mkdtemp(prefix='luffy-session-', dir='/tmp')) / 'control'
            self.save(socket, owned=True)
            command = self.base(socket) + [
                '-f', '-M', '-N', '-o', 'ControlPersist=no', '-o', 'BatchMode=no',
                '-o', 'PubkeyAuthentication=no', '-o', 'IdentityAgent=none',
                '-o', 'PreferredAuthentications=keyboard-interactive,password',
                '-o', 'KbdInteractiveAuthentication=yes', '-o', 'PasswordAuthentication=yes',
                '-o', 'ServerAliveInterval=30', '-o', 'ServerAliveCountMax=3',
                self.profile['host']]
            print(f'Target: {self.target} | {self.profile["user"]}@{self.profile["host"]}\n'
                  'Enter the account password only at the SSH prompt.\n'
                  'After authentication, SSH runs in the background; this terminal may close.', flush=True)
            child = None
            try:
                # Inherits the human terminal. No password pipe, capture, storage or askpass.
                environment = os.environ.copy()
                environment['SSH_ASKPASS_REQUIRE'] = 'never'
                child = subprocess.Popen(command, env=environment)
                rc = child.wait()
                if rc:
                    raise SessionError(f'SSH login failed or was cancelled (exit {rc})')
                self.verify(socket)
                self.save(socket, owned=True, background=True, seconds=seconds)
                if seconds is not None:
                    self.start_timer(self.read())
            except BaseException:
                if child is not None and child.poll() is None:
                    child.terminate()
                    try:
                        child.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait()
                # A late interrupt may follow SSH's fork. Keep a socket tracked until closed.
                if socket.exists():
                    self.close_socket(socket)
                self.cleanup(self.read())
                raise
        print(f'{self.target}: SESSION ON | background | identity verified. '
              f'Terminal may close. Stop: luffy fullpower off {self.target}')
        print(f'   Lifetime: {self.lifetime(self.read())}')
        return 0

    def start_timer(self, data):
        # One detached local timer only for a timed password session. No remote cron/job.
        reader, writer = os.pipe()
        try:
            child = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '_expire',
                                      self.target, data['generation'], str(self.root), str(writer)],
                                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL, start_new_session=True,
                                     pass_fds=(writer,))
            os.close(writer)
            writer = None
            ready, _, _ = select.select([reader], [], [], 5)
            if not ready or os.read(reader, 16) != b'ready':
                # This is our just-created child, not a PID from a stale state record.
                child.terminate()
                child.wait(timeout=5)
                raise SessionError('Could not start expiry timer; connection will be closed')
            data['timer_pid'] = child.pid
            targets.atomic_json(self.record, data)
        finally:
            os.close(reader)
            if writer is not None:
                os.close(writer)

    def close_socket(self, socket):
        # Local mux control works even when the remote host/network cannot answer id.
        check_socket(socket)
        if not self.socket_listening(socket):
            socket.unlink(missing_ok=True)
            return
        subprocess.run(self.base(socket) + ['-O', 'exit', self.profile['host']],
                       check=True, timeout=15, capture_output=True, text=True)
        for _ in range(50):
            if not socket.exists():
                return
            time.sleep(0.1)
        raise SessionError('Socket still exists; session closure not verified; record retained')

    @staticmethod
    def socket_listening(path):
        check_socket(path)
        with socketlib.socket(socketlib.AF_UNIX, socketlib.SOCK_STREAM) as connection:
            connection.settimeout(2)
            try:
                connection.connect(str(path))
            except (ConnectionRefusedError, FileNotFoundError):
                return False
        return True

    def cleanup(self, data):
        socket = Path(data['socket'])
        if socket.exists():
            raise SessionError('Refusing to forget a live socket')
        self.record.unlink(missing_ok=True)
        if data.get('owned') and socket.name == 'control' and socket.parent.name.startswith('luffy-session-'):
            with contextlib.suppress(OSError):
                private_path(socket.parent, directory=True)
                socket.parent.rmdir()

    def run(self, command):
        data = self.read()
        if self.expired(data):
            raise SessionError('Session expired; run ON again in your terminal')
        socket = Path(data['socket'])
        self.verify(socket)
        return subprocess.call(self.reuse(socket) + [command])

    def off(self, expected_generation=None):
        with self.lock():
            try:
                data = self.read()
            except FileNotFoundError:
                print(f'{self.target}: no recorded session')
                return 0
            if expected_generation is not None and data.get('generation') != expected_generation:
                return 0
            socket = Path(data['socket'])
            if not socket.exists() and self.launcher_alive(data):
                raise SessionError('Login is starting; use Ctrl-C in its terminal to cancel')
            if socket.exists():
                self.close_socket(socket)
            self.cleanup(data)
        print(f'{self.target}: SESSION OFF | other targets, credentials and remote jobs unchanged')
        return 0


def expiry_worker(target, generation, root, ready_fd):
    try:
        session = Session(target, Path(root), recorded=True)
        data = session.read()
        if data.get('generation') != generation or data.get('expires_at') is None:
            return 1
        os.write(ready_fd, b'ready')
    finally:
        os.close(ready_fd)
    # OFF/replacement removes or changes the record, causing this timer to exit.
    failures = 0
    while True:
        try:
            private_path(session.record)
            current = json.loads(session.record.read_text())
            if current.get('generation') != generation:
                return 0
            if current.get('profile') != session.profile:
                return 1
            data = session.read()
            if data.get('generation') != generation:
                return 0
            if session.expired(data):
                with lifecycle_lock(session.root, 'lifecycle.lock', shared=True):
                    return session.off(expected_generation=generation)
            if not Path(data['socket']).exists():
                with lifecycle_lock(session.root, 'lifecycle.lock', shared=True):
                    return session.off(expected_generation=generation)
            failures = 0
        except FileNotFoundError:
            return 0
        except (SessionError, OSError, ValueError, KeyError, subprocess.SubprocessError):
            # A concurrent operation/temporarily busy socket is retried; no login fallback.
            if not session.record.exists():
                return 0
            failures += 1
            if failures >= 20:
                return 1  # Keep the expired record visible; do not leak an endless retry loop.
        time.sleep(0.5)


def main():
    if len(sys.argv) == 6 and sys.argv[1] == '_expire':
        return expiry_worker(sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]))
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='operation', required=True)
    for name in ('on', 'off', 'status', 'run', 'attach'):
        sub = commands.add_parser(name)
        sub.add_argument('target')
        if name == 'on':
            sub.add_argument('--password', action='store_true', help='Human types password into SSH')
            sub.add_argument('duration', nargs='?', help='Positive seconds or units such as 2h')
        if name == 'run':
            sub.add_argument('command', help='One quoted remote shell command')
        if name == 'attach':
            sub.add_argument('--socket', required=True, type=Path,
                             help='Explicitly selected existing authenticated control socket')
    args = parser.parse_args()
    try:
        with lifecycle_lock(state_root(), 'lifecycle.lock', shared=True):
            session = Session(args.target)
            if args.operation == 'on':
                return session.on(args.password, args.duration)
            if args.operation == 'run':
                # Long remote commands must not prevent OFF.
                pass
            elif args.operation == 'attach':
                return session.attach(args.socket)
            else:
                return getattr(session, args.operation)()
        return session.run(args.command)
    except UsageHint as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print('Login cancelled.', file=sys.stderr)
        return 130
    except (SessionError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print(f'{args.target}: SESSION NOT VERIFIED: {exc}', file=sys.stderr)
        return 4


if __name__ == '__main__':
    sys.exit(main())
