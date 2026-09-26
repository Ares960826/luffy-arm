#!/usr/bin/env python3
"""One CLI grammar for registered key and password targets."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
from lifecycle import SessionError, state_root, lock, key_command, key_lock_name, all_targets
import targets


def execute(operation, target, seconds=None, password=False, root=None):
    from session import Session
    root = root or state_root()
    with lock(root, 'lifecycle.lock', shared=True):
        profile = targets.load(target, root)
        print(f"Target: {target} | {profile['name']} | {profile['auth']}", flush=True)
        if profile['auth'] == 'key':
            if password:
                raise SessionError(f'{target} uses a key. Omit --password.')
            metadata, _ = targets.key_metadata(profile['params'])
            if targets.connection(metadata) != targets.connection(profile):
                raise SessionError('Key params host/user/port changed; refusing to silently switch server')
            with lock(root, key_lock_name(profile['params'])):
                return key_command(operation, () if seconds is None else (str(seconds),), params=profile['params'])
        session = Session(target, root)
        if operation == 'on':
            return session.on(password, seconds)
        return getattr(session, operation)()


def main(argv=None):
    parser = argparse.ArgumentParser(prog='luffy fullpower',
        usage='%(prog)s on [TARGET] [DURATION] [--password] | off/status [TARGET | --all]',
        description='DURATION: positive seconds or units such as 2h. Repeated ON never renews expiry.')
    parser.add_argument('operation', choices=['on', 'off', 'status'], nargs='?', default='status')
    parser.add_argument('items', nargs='*', metavar='TARGET/DURATION')
    parser.add_argument('--password', action='store_true')
    parser.add_argument('--all', action='store_true')
    args = parser.parse_intermixed_args(argv)
    try:
        if args.all:
            if args.operation == 'on' or args.items or args.password:
                raise SessionError('--all supports only off/status, without target or duration')
            return all_targets(args.operation, state_root())
        if args.operation != 'on' and (args.password or len(args.items) > 1):
            raise SessionError('Duration and --password apply only to ON')
        items = list(args.items)
        target = None
        seconds = None
        if items and not targets.DURATION.fullmatch(items[0]):
            target = targets.target_id(items.pop(0))
        if items:
            if args.operation != 'on' or len(items) != 1:
                raise SessionError('Use: luffy fullpower on TARGET [DURATION] [--password]')
            seconds = targets.duration(items[0])
        if target is None:
            try:
                target = targets.default_target()
            except SessionError:
                if list((state_root() / 'targets').glob('*.json')):
                    raise
                params = Path(os.environ.get('LUFFY_ARM_PARAMS', str(Path.home() / '.config/luffy-arm/params.sh')))
                if not params.exists() or args.password:
                    raise
                print('Legacy unregistered key configuration. Register it with: luffy target add NAME --params PATH', flush=True)
                with lock(state_root(), 'lifecycle.lock', shared=True), lock(state_root(), key_lock_name(params)):
                    return key_command(args.operation, () if seconds is None else (str(seconds),), params=str(params))
        return execute(args.operation, target, seconds, args.password)
    except (SessionError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print(f'luffy fullpower: {exc}', file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print('Login cancelled.', file=sys.stderr)
        return 130


if __name__ == '__main__':
    sys.exit(main())
