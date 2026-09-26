#!/usr/bin/env python3
"""Serialize Luffy lifecycle changes and close only registered Luffy resources."""
import argparse
import contextlib
import fcntl
import hashlib
import os
from pathlib import Path
import stat
import subprocess
import sys


class SessionError(Exception):
    pass


def private_path(path, directory=False):
    info = path.lstat()
    kind = stat.S_ISDIR if directory else stat.S_ISREG
    if not kind(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise SessionError(f"Expected an owner-only {'directory' if directory else 'file'}: {path}")


def state_root():
    return Path(os.environ.get('LUFFY_ARM_STATE_DIR', str(Path.home() / '.config/luffy-arm')))


@contextlib.contextmanager
def lock(root, name, shared=False):
    # Kernel locks disappear when the process exits; lock files contain no PIDs/secrets.
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    private_path(root, directory=True)
    path = root / name
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        private_path(path)
        try:
            fcntl.flock(fd, (fcntl.LOCK_SH if shared else fcntl.LOCK_EX) | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SessionError('Another Luffy ON/OFF is in progress. Finish or cancel its '
                               'password prompt, then retry; no competing operation was started.') from None
        yield
    finally:
        os.close(fd)


def key_lock_name(params=None):
    params = params or os.environ.get('LUFFY_ARM_PARAMS', str(Path.home() / '.config/luffy-arm/params.sh'))
    return 'key-' + hashlib.sha256(str(Path(params).resolve()).encode()).hexdigest()[:24] + '.lock'


def key_command(operation, args=(), params=None):
    env = dict(os.environ)
    if params is not None:
        env['LUFFY_ARM_PARAMS'] = str(params)
    return subprocess.call(['bash', str(Path(__file__).with_name('fullpower.sh')),
                            '--locked', operation, *args], env=env)


def all_targets(operation, root):
    from session import Session
    import targets as registry
    failures = []
    residual = False
    # Exclusive OFF prevents new ON calls from racing the enumeration/cleanup.
    with lock(root, 'lifecycle.lock', shared=operation == 'status'):
        states = root / 'sessions'
        targets = set()
        if states.exists():
            private_path(states, directory=True)
            targets.update(path.stem for path in states.glob('*.json'))
        if (root / 'targets').exists():
            targets.update(path.stem for path in (root / 'targets').glob('*.json'))
        handled_keys = set()
        for target in sorted(targets):
            try:
                # Recorded password sockets can be closed even after profile edits/deletion.
                if operation == 'off' and (states / (target + '.json')).exists():
                    rc = Session(target, root, recorded=True).off()
                    if rc:
                        failures.append(target)
                    continue
                profile = registry.load(target, root)
                if profile['auth'] == 'key':
                    params_path = str(Path(profile['params']).resolve())
                    if params_path in handled_keys:
                        continue
                    handled_keys.add(params_path)
                    metadata, _ = registry.key_metadata(params_path)
                    if registry.connection(metadata) != registry.connection(profile):
                        raise SessionError('Key params changed; target identity must be reconciled first')
                    print(f"Target: {target} | {profile['name']} | key", flush=True)
                    with lock(root, key_lock_name(params_path)):
                        if operation == 'off' and key_command('close-safe', params=params_path):
                            failures.append(target + ' safe connection')
                        rc = key_command(operation, params=params_path)
                    if operation == 'off' and rc == 4:
                        residual = True
                        continue
                    if rc:
                        failures.append(target)
                    continue
                else:
                    rc = getattr(Session(target, root), operation)()
                if rc not in (0, 3):
                    failures.append(target)
            except (SessionError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
                label = 'NOT CLOSED' if operation == 'off' else 'UNKNOWN'
                print(f'{target}: {label}: {exc}', file=sys.stderr)
                failures.append(target)
        params = Path(os.environ.get('LUFFY_ARM_PARAMS', str(Path.home() / '.config/luffy-arm/params.sh')))
        if params.exists() and str(params.resolve()) not in handled_keys:
            print('Legacy unregistered key configuration:', flush=True)
            with lock(root, key_lock_name(params)):
                if operation == 'off' and key_command('close-safe'):
                    failures.append('default safe connection')
                rc = key_command(operation)
                if operation == 'off' and rc == 4:
                    residual = True  # Dedicated key removed; another credential remains.
                elif rc:
                    failures.append('default key gate')
        if failures:
            print('INCOMPLETE: ' + ', '.join(failures) + '. Retry after resolving these entries.')
            return 4
        if operation == 'off':
            print('Luffy managed sessions closed; key-gate results shown above. '
                  'Other SSH connections, shared ssh-agent and remote jobs were not targeted.')
            return 4 if residual else 0
        return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('scope', choices=['key', 'all'])
    parser.add_argument('operation', choices=['on', 'off', 'status'], nargs='?', default='status')
    parser.add_argument('args', nargs='*')
    args = parser.parse_args()
    try:
        root = state_root()
        if args.scope == 'all':
            if args.operation == 'on' or args.args:
                parser.error('--all supports only off and status')
            return all_targets(args.operation, root)
        with lock(root, 'lifecycle.lock', shared=True), lock(root, key_lock_name()):
            return key_command(args.operation, args.args)
    except (SessionError, OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f'Luffy lifecycle: {exc}', file=sys.stderr)
        return 4
    except KeyboardInterrupt:
        return 130


if __name__ == '__main__':
    # session imports this module too; retain one shared exception/lock implementation.
    sys.modules.setdefault('lifecycle', sys.modules[__name__])
    sys.exit(main())
