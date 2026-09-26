#!/usr/bin/env python3
"""Upgrade an isolated skill installation; never touch agent config or CLI links."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class Install(unittest.TestCase):
    def test_upgrade_removes_stale_product_and_ships_consistent_version(self):
        source = Path(__file__).resolve().parents[1]
        version = (source / 'VERSION').read_text().strip()
        self.assertEqual(json.loads((source / '.claude-plugin/plugin.json').read_text())['version'], version)
        with tempfile.TemporaryDirectory(prefix='luffy-install-') as temporary:
            root = Path(temporary)
            skills = root / 'skills'
            installed = skills / 'luffy-arm'
            installed.mkdir(parents=True)
            (installed / 'obsolete-single-server.sh').write_text('old product')
            state = root / 'state'
            state.mkdir()
            sentinel = state / 'params.sh'
            sentinel.write_text('preserve private config')
            env = dict(os.environ, LUFFY_ARM_DIR=str(skills), LUFFY_ARM_NO_CLI='1',
                       LUFFY_ARM_STATE_DIR=str(state))
            result = subprocess.run(['bash', str(source / 'install.sh')], env=env,
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((installed / 'obsolete-single-server.sh').exists())
            self.assertFalse((installed / 'tests').exists())
            self.assertFalse(list(installed.rglob('*.pyc')))
            self.assertEqual(sentinel.read_text(), 'preserve private config')
            result = subprocess.run(['bash', str(installed / 'scripts/luffy-arm'), 'version'],
                                    capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), 'luffy-arm ' + version)
            for skill in [installed, skills / 'luffy-arm-fullpower-on', skills / 'luffy-arm-fullpower-off']:
                self.assertIn('  version: "' + version + '"', (skill / 'SKILL.md').read_text())
            for name in ('targets.py', 'power.py', 'session.py', 'lifecycle.py', 'fullpower-route.sh'):
                self.assertEqual((installed / 'scripts' / name).read_bytes(), (source / 'scripts' / name).read_bytes())


if __name__ == '__main__':
    unittest.main()
