import base64
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

loader = importlib.machinery.SourceFileLoader('updates', str(Path(__file__).parents[1] / 'sign-updates'))
spec = importlib.util.spec_from_loader(loader.name, loader)
updates = importlib.util.module_from_spec(spec)
loader.exec_module(updates)


class UpdateTests(unittest.TestCase):
    def test_missing_and_invalid_public_key(self):
        for value in ('', 'placeholder', base64.b64encode(b'short').decode()):
            with self.subTest(value=value), self.assertRaises(ValueError):
                updates.public_key(value)
        self.assertEqual(updates.public_key(base64.b64encode(bytes(32)).decode()), bytes(32))

    def test_missing_private_key_stops_before_reading_artifacts(self):
        with patch.dict(os.environ, {'SPARKLE_PUBLIC_KEY': base64.b64encode(bytes(32)).decode(),
                                     'SPARKLE_PRIVATE_KEY': ''}), patch.object(updates.sys, 'argv', ['sign-updates', 'v0.0.8']):
            with self.assertRaisesRegex(ValueError, 'SPARKLE_PRIVATE_KEY is required'):
                updates.main()

    def test_private_key_uses_stdin_and_is_removed_from_child_environment(self):
        with patch.dict(os.environ, {'SPARKLE_PRIVATE_KEY': 'sensitive'}), patch.object(updates.subprocess, 'run') as run:
            run.return_value.returncode = 0
            updates.sparkle_tool(Path('/tools/sign_update'), ['--verify', 'artifact'], 'sensitive')
            args, kwargs = run.call_args
            self.assertNotIn('sensitive', args[0])
            self.assertEqual(kwargs['input'], 'sensitive\n')
            self.assertNotIn('SPARKLE_PRIVATE_KEY', kwargs['env'])
            self.assertEqual(args[0][-2:], ['--ed-key-file', '-'])

    def test_tool_failure_does_not_expose_output_or_secret(self):
        with patch.object(updates.subprocess, 'run') as run:
            run.return_value.returncode = 1
            run.return_value.stderr = 'sensitive'
            with self.assertRaisesRegex(ValueError, '^Sparkle sign_update failed$'):
                updates.sparkle_tool(Path('/tools/sign_update'), [], 'sensitive')

    def test_metadata_rejects_tampering(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'slime-0.0.8-arm64.dmg'
            archive.write_bytes(b'archive')
            bundle = {'CFBundleVersion': '8', 'CFBundleShortVersionString': '0.0.8', 'LSMinimumSystemVersion': '26.0'}
            url = 'https://github.com/chriscco/slime/releases/download/v0.0.8/' + archive.name
            signature = base64.b64encode(bytes(64)).decode()
            xml = f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>8</sparkle:version><sparkle:shortVersionString>0.0.8</sparkle:shortVersionString><sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion><sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements><enclosure url="{url}" length="7" sparkle:edSignature="{signature}" type="application/octet-stream" /></item></channel></rss>'''
            self.assertEqual(updates.validate_appcast(ET.fromstring(xml), archive, bundle, url), signature)
            for original, bad in [('>8<', '>9<'), ('>26.0<', '>14.0<'), ('>arm64<', '>x86_64<'), ('length="7"', 'length="8"'), ('https://', 'http://'), (signature, 'invalid')]:
                with self.subTest(original=original), self.assertRaises(ValueError):
                    updates.validate_appcast(ET.fromstring(xml.replace(original, bad)), archive, bundle, url)
            with self.assertRaises(ValueError):
                updates.validate_appcast(ET.fromstring(xml.replace(f' sparkle:edSignature="{signature}"', '')), archive, bundle, url)


@unittest.skipUnless((updates.TOOLS / 'sign_update').exists(), 'resolve pinned Sparkle tools first')
class OfficialSigningTests(unittest.TestCase):
    def test_real_signatures_refuse_changed_archive_feed_and_wrong_key(self):
        # Ephemeral CryptoKit seeds never enter Keychain, files, argv, or logs.
        generated = updates.subprocess.run(['swift', '-e',
            'import Foundation; import CryptoKit; for _ in 0..<2 { print(Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()) }'],
            capture_output=True, text=True, check=True).stdout.splitlines()
        tool = updates.TOOLS / 'sign_update'
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'fixture.dmg'
            archive.write_bytes(b'fixture archive contents')
            result = updates.subprocess.run([str(tool), '-p', str(archive), '--ed-key-file', '-'],
                input=generated[0] + '\n', text=True, capture_output=True, check=True)
            signature = result.stdout.strip()
            updates.sparkle_tool(tool, ['--verify', archive, signature], generated[0])
            with self.assertRaises(ValueError):
                updates.sparkle_tool(tool, ['--verify', archive, signature], generated[1])
            archive.write_bytes(b'changed archive contents')
            with self.assertRaises(ValueError):
                updates.sparkle_tool(tool, ['--verify', archive, signature], generated[0])
            feed = Path(directory) / 'appcast.xml'
            feed.write_text('<?xml version="1.0"?><rss version="2.0"><channel><title>fixture</title></channel></rss>')
            updates.sparkle_tool(tool, [feed], generated[0])
            updates.sparkle_tool(tool, ['--verify', feed], generated[0])
            feed.write_text(feed.read_text().replace('<title>fixture</title>', '<title>changed</title>'))
            with self.assertRaises(ValueError):
                updates.sparkle_tool(tool, ['--verify', feed], generated[0])


if __name__ == '__main__':
    unittest.main()
