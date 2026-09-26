#!/usr/bin/env python3
"""Local target registry. Registration stores configuration, never authenticates."""
import argparse
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import unicodedata
from lifecycle import SessionError, private_path, state_root, lock

DURATION = re.compile(r'(?:[0-9]+[smhdw]?)+\Z')


def duration(value):
    if not DURATION.fullmatch(str(value)):
        raise SessionError('Invalid duration. Use positive seconds (120000) or units (2h, 1h30m).')
    units = {'': 1, 's': 1, 'm': 60, 'h': 3600, 'd': 86400, 'w': 604800}
    seconds = sum(int(n) * units[u] for n, u in re.findall(r'([0-9]+)([smhdw]?)', str(value)))
    if not 0 < seconds <= 2147483647:
        raise SessionError('Duration must be positive and at most 2147483647 seconds.')
    return seconds


def target_id(value):
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,47}', value) or DURATION.fullmatch(value):
        raise SessionError('Use a target ID such as my-server; duration-only names are reserved.')
    return value


def connection(profile):
    data = {k: profile.get(k) for k in ('host', 'user')}
    data['port'] = profile.get('port', 22)
    if not isinstance(data['host'], str) or not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9.:-]*', data['host']):
        raise SessionError('Invalid host')
    if not isinstance(data['user'], str) or not re.fullmatch(r'[a-zA-Z0-9_][a-zA-Z0-9_.-]*', data['user']):
        raise SessionError('Invalid user')
    if type(data['port']) is not int or not 1 <= data['port'] <= 65535:
        raise SessionError('Invalid port')
    return data


def validate(profile, target):
    if not isinstance(profile, dict) or set(profile) - {'host', 'user', 'port', 'auth', 'name', 'params'}:
        raise SessionError('Target profile accepts connection fields, auth, name and params; never passwords.')
    profile = dict(profile)
    profile.update(connection(profile))
    profile.setdefault('auth', 'password')
    profile.setdefault('name', target)
    if profile['auth'] not in ('key', 'password'):
        raise SessionError('auth must be key or password')
    if not isinstance(profile['name'], str) or not profile['name'].strip() or any(ord(c) < 32 or ord(c) == 127 for c in profile['name']):
        raise SessionError('Display name must be nonempty and contain no control characters')
    if profile['auth'] == 'key':
        if not isinstance(profile.get('params'), str) or not Path(profile['params']).is_absolute():
            raise SessionError('Key target requires an absolute params path')
    elif 'params' in profile:
        raise SessionError('Password target must not contain key params')
    return profile


def load(target, root=None):
    root = root or state_root()
    path = root / 'targets' / (target_id(target) + '.json')
    if not path.exists():
        raise SessionError(f"Unknown target '{target}'. Run 'luffy tlist' or 'luffy target add --help'.")
    private_path(path)
    return validate(json.loads(path.read_text()), target)


def atomic_json(path, data):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    private_path(path.parent, directory=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def key_metadata(path):
    path = Path(path).expanduser().resolve()
    info = path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o022:
        raise SessionError('Key params must be your regular file, not writable by other users')
    # Same trusted local shell configuration consumed by fullpower.sh, no key data read.
    script = 'source "$1"; printf "%s\\0" "$SERVER" "${SSH_PORT:-22}" "$ADMIN_USER" "$ADMIN_KEY" "$ADMIN_ALIAS"'
    result = subprocess.run(['bash', '-eu', '-c', script, 'luffy-target', str(path)],
                            capture_output=True, text=True, check=True, timeout=10)
    fields = result.stdout.split('\0')
    if len(fields) != 6 or not all(fields[i] for i in (0, 2, 3, 4)):
        raise SessionError('Key params must provide SERVER, ADMIN_USER, ADMIN_KEY and ADMIN_ALIAS')
    return dict(host=fields[0], port=int(fields[1]), user=fields[2], params=str(path)), str(Path(fields[3]).expanduser().resolve())


def register(target, profile, root=None, update_name=False):
    root = root or state_root()
    target_id(target)
    profile = validate(profile, target)
    with lock(root, 'lifecycle.lock'):
        existing = root / 'targets' / (target + '.json')
        if existing.exists():
            previous = load(target, root)
            if {k: v for k, v in previous.items() if k != 'name'} != {k: v for k, v in profile.items() if k != 'name'}:
                raise SessionError(f"Target '{target}' already exists with different settings; not overwritten.")
            if update_name and previous['name'] != profile['name']:
                atomic_json(existing, profile)
                print(f"{target}: display name updated to {profile['name']}")
                return
            print(f'{target}: already registered')
            return
        if profile['auth'] == 'key':
            metadata, key = key_metadata(profile['params'])
            if connection(metadata) != connection(profile):
                raise SessionError('Key params changed; register with their current values')
            for path in (root / 'targets').glob('*.json'):
                other = load(path.stem, root)
                if other['auth'] == 'key':
                    _, other_key = key_metadata(other['params'])
                    if Path(other['params']).resolve() == Path(profile['params']).resolve() or other_key == key:
                        raise SessionError(f"Key/params already registered as '{path.stem}'; use that target.")
        atomic_json(existing, profile)
    print(f"Registered {target} | {profile['name']} | {profile['auth']} | {profile['user']}@{profile['host']}:{profile['port']}")


def default_target(root=None):
    root = root or state_root()
    path = root / 'default-target.json'
    if path.exists():
        private_path(path)
        target = json.loads(path.read_text())['target']
        load(target, root)
        return target
    names = sorted(p.stem for p in (root / 'targets').glob('*.json'))
    if len(names) == 1:
        load(names[0], root)
        return names[0]
    raise SessionError('Choose a TARGET, or set one with: luffy target default TARGET. List: luffy tlist')


def listing(root=None):
    root = root or state_root()
    names = sorted(p.stem for p in (root / 'targets').glob('*.json'))
    try:
        default = default_target(root)
    except SessionError:
        default = None
    rows = [['TARGET', 'NAME', 'AUTH', 'ADDRESS', 'DEFAULT']]
    failed = False
    for target in names:
        try:
            p = load(target, root)
            rows.append([target, p['name'], p['auth'], f"{p['user']}@{p['host']}:{p['port']}", '*' if target == default else ''])
        except (SessionError, OSError, ValueError, KeyError) as exc:
            rows.append([target, 'INVALID: ' + str(exc), '', '', ''])
            failed = True
    def width(text):
        return sum(0 if unicodedata.combining(c) else 2 if unicodedata.east_asian_width(c) in ('W', 'F') else 1 for c in text)
    widths = [max(width(row[i]) for row in rows) for i in range(5)]
    for row in rows:
        print('  '.join(value + ' ' * (widths[i] - width(value)) for i, value in enumerate(row)).rstrip())
    if not names:
        print('No targets registered. Start with: luffy target add --help')
    print('Configuration list only. Live connection status: luffy fullpower status --all')
    return 2 if failed else 0


def main():
    parser = argparse.ArgumentParser(prog='luffy target', description=__doc__)
    subs = parser.add_subparsers(dest='operation', required=True)
    subs.add_parser('list')
    default = subs.add_parser('default')
    default.add_argument('target')
    add = subs.add_parser('add')
    add.add_argument('target')
    add.add_argument('--name', help='Human-readable display name')
    mode = add.add_mutually_exclusive_group(required=True)
    mode.add_argument('--password', action='store_true')
    mode.add_argument('--params', type=Path, help='Existing key-mode params file')
    add.add_argument('--host')
    add.add_argument('--user')
    add.add_argument('--port', type=int, default=22)
    args = parser.parse_args()
    try:
        if args.operation == 'list':
            return listing()
        if args.operation == 'default':
            with lock(state_root(), 'lifecycle.lock'):
                load(args.target)
                atomic_json(state_root() / 'default-target.json', {'target': args.target})
            print(f'Default target: {args.target}')
            return 0
        if args.params:
            if args.host or args.user or args.port != 22:
                raise SessionError('For key targets, host/user/port are read from --params')
            profile, _ = key_metadata(args.params)
            profile['auth'] = 'key'
        else:
            profile = dict(host=args.host, user=args.user, port=args.port, auth='password')
        profile['name'] = args.name or args.target
        register(args.target, profile, update_name=args.name is not None)
        return 0
    except (SessionError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print(f'luffy target: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
