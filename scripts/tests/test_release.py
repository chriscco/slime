"""Release checks use temporary history and fake GitHub responses, never publication."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'check-release'


class ReleaseChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        loader = importlib.machinery.SourceFileLoader('release', str(SCRIPT))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        cls.release = importlib.util.module_from_spec(spec)
        loader.exec_module(cls.release)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.old_cwd = Path.cwd()
        os.chdir(self.temp.name)
        self.addCleanup(os.chdir, self.old_cwd)
        self.git('init', '-b', 'main', '-q')
        self.git('config', 'user.name', 'Release Test')
        self.git('config', 'user.email', 'release@example.invalid')
        self.git('commit', '--allow-empty', '-qm', 'initial')
        self.git('tag', 'v0.0.6')
        self.git('switch', '-qc', 'feature')
        self.git('commit', '--allow-empty', '-qm', 'feature')
        self.git('switch', '-q', 'main')
        self.git('merge', '--no-ff', 'feature', '-qm', 'Merge PR')
        self.sha = self.git('rev-parse', 'HEAD')
        self.git('tag', '-a', 'v0.0.7', '-m', 'release')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')
        Path('docs/releases').mkdir(parents=True)
        self.notes = Path('docs/releases/0.0.7.md')
        self.entry = '- Improve switching. ([#62](https://github.com/chriscco/slime/pull/62)) — @chriscco'
        self.notes.write_text('# slime v0.0.7\n\n## Changes\n\n' + self.entry + '\n')
        self.metadata = [{'number': 62, 'merge_commit_sha': self.sha,
                          'merged_at': '2026-10-16T00:00:00Z',
                          'base': {'ref': 'main'}, 'user': {'login': 'chriscco'}}]
        original = self.release.run

        def command(*args):
            return json.dumps([self.metadata]) if args[0] == 'gh' else original(*args)

        self.mock = patch.object(self.release, 'run', side_effect=command)
        self.mock.start()
        self.addCleanup(self.mock.stop)

    def git(self, *args):
        return subprocess.check_output(['git', *args], text=True).strip()

    def check(self, tag='v0.0.7'):
        return self.release.check_notes(tag, 'chriscco/slime')

    def test_valid_annotated_tag_and_author(self):
        self.assertEqual(self.check(), self.notes)

    def test_spec_pr_can_omit_notes_with_explicit_label(self):
        self.metadata[0]['labels'] = [{'name': 'release-notes:skip'}]
        self.notes.write_text('# slime v0.0.7\n\n## Changes\n')
        self.assertEqual(self.check(), self.notes)

    def test_unrelated_label_does_not_skip_required_entry(self):
        self.metadata[0]['labels'] = [{'name': 'documentation'}]
        self.notes.write_text('# slime v0.0.7\n')
        with self.assertRaisesRegex(ValueError, 'entries'):
            self.check()

    def test_exempt_spec_pr_must_not_appear_in_notes(self):
        self.metadata[0]['labels'] = [{'name': 'release-notes:skip'}]
        with self.assertRaisesRegex(ValueError, 'entries'):
            self.check()

    def test_invalid_tags(self):
        for tag in ['0.0.7', 'v0.0.7-rc1', 'v0.0.7;echo', 'v00.0.7', '../0.0.7']:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                self.check(tag)

    def test_off_main(self):
        self.git('update-ref', 'refs/remotes/origin/main', 'v0.0.6')
        with self.assertRaisesRegex(ValueError, 'main'):
            self.check()

    def test_missing_notes(self):
        self.notes.unlink()
        with self.assertRaisesRegex(ValueError, 'notes'):
            self.check()

    def test_wrong_heading_placeholder_or_missing_entry(self):
        for text in ['# slime v0.0.8\n' + self.entry,
                     '# slime v0.0.7\nTODO\n' + self.entry, '# slime v0.0.7\n']:
            self.notes.write_text(text)
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.check()

    def test_missing_extra_duplicate_or_wrong_author(self):
        for entry in [self.entry.replace('@chriscco', '@someone'),
                      self.entry + '\n' + self.entry,
                      self.entry.replace('62', '99'),
                      self.entry.replace('chriscco/slime', 'other/repo'),
                      self.entry.replace(' — @chriscco', '')]:
            self.notes.write_text('# slime v0.0.7\n' + entry + '\n')
            with self.subTest(entry=entry), self.assertRaises(ValueError):
                self.check()

    def test_metadata_must_match_merge_and_main(self):
        for key, value in [('merge_commit_sha', 'wrong'), ('merged_at', None),
                           ('base', {'ref': 'other'})]:
            saved = self.metadata[0][key]
            self.metadata[0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.check()
            self.metadata[0][key] = saved

    def test_bundle_version(self):
        plist = Path('Info.plist')
        for version in ['0.0.7', '0.0.6']:
            plist.write_bytes(plistlib.dumps({'CFBundleShortVersionString': version}))
            if version == '0.0.7':
                self.release.check_bundle('v0.0.7', plist)
            else:
                with self.assertRaisesRegex(ValueError, 'version'):
                    self.release.check_bundle('v0.0.7', plist)


class SigningPolicy(unittest.TestCase):
    def test_required_identity_and_explicit_identity_fail_closed(self):
        build_script = SCRIPT.with_name('build-app').read_text()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'scripts').mkdir()
            (root / 'Resources').mkdir()
            (root / 'docs/assets').mkdir(parents=True)
            (root / 'docs/assets/slime-banner.png').write_bytes(b'fixture')
            (root / 'scripts/sign-updates').write_text(SCRIPT.with_name('sign-updates').read_text())
            (root / '.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework').mkdir(parents=True)
            (root / '.build/artifacts/sparkle/Sparkle/LICENSE').write_bytes(b'Sparkle license fixture')
            (root / 'Resources/slime.icns').write_bytes(b'fixture')
            script = root / 'scripts/build-app'
            script.write_text(build_script)
            commands = root / 'commands'
            commands.mkdir()
            for name, body in {
                'swift': 'mkdir -p .build/debug; touch .build/debug/slime; chmod +x .build/debug/slime',
                'security': 'exit 0',
                'codesign': 'printf "%s\\n" "$*" >> "$SIGN_LOG"; exit "${SIGN_RESULT:-0}"',
            }.items():
                path = commands / name
                path.write_text('#!/bin/sh\n' + body + '\n')
                path.chmod(0o755)
            env = {**os.environ, 'PATH': f'{commands}:/usr/bin:/bin',
                   'SIGN_LOG': str(root / 'sign.log'), 'CONFIG': 'debug',
                   'SIGNING_IDENTITY': '', 'REQUIRE_SIGNING': '1',
                   'SPARKLE_PUBLIC_KEY': '', 'REQUIRE_UPDATES': '0'}
            result = subprocess.run(['sh', str(script)], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('refusing ad-hoc', result.stderr)
            self.assertFalse((root / 'sign.log').exists())
            env['SIGNING_IDENTITY'] = 'A' * 40
            result = subprocess.run(['sh', str(script)], env=env, capture_output=True)
            self.assertEqual(result.returncode, 0)
            self.assertIn('--sign ' + 'A' * 40, (root / 'sign.log').read_text())
            self.assertEqual((root / 'build/slime.app/Contents/Resources/Sparkle-LICENSE.txt').read_bytes(),
                             b'Sparkle license fixture')
            info = plistlib.loads((root / 'build/slime.app/Contents/Info.plist').read_bytes())
            self.assertNotIn('SUFeedURL', info)
            self.assertNotIn('SUPublicEDKey', info)
            for key in ('SUEnableAutomaticChecks', 'SUAutomaticallyUpdate', 'SUAllowsAutomaticUpdates', 'SUSendProfileInfo'):
                self.assertFalse(info[key])
            env['REQUIRE_UPDATES'] = '1'
            result = subprocess.run(['sh', str(script)], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('SPARKLE_PUBLIC_KEY is required', result.stderr)
            env['SPARKLE_PUBLIC_KEY'] = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
            result = subprocess.run(['sh', str(script)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            info = plistlib.loads((root / 'build/slime.app/Contents/Info.plist').read_bytes())
            self.assertEqual(info['SUPublicEDKey'], env['SPARKLE_PUBLIC_KEY'])
            self.assertTrue(info['SURequireSignedFeed'])
            self.assertTrue(info['SUVerifyUpdateBeforeExtraction'])
            env['SIGN_RESULT'] = '1'
            result = subprocess.run(['sh', str(script)], env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('--sign - ', (root / 'sign.log').read_text())
            env.update(SIGN_RESULT='0', SIGNING_IDENTITY='', REQUIRE_SIGNING='0')
            result = subprocess.run(['sh', str(script)], env=env, capture_output=True)
            self.assertEqual(result.returncode, 0)
            self.assertIn('--sign - ', (root / 'sign.log').read_text())


if __name__ == '__main__':
    unittest.main()
