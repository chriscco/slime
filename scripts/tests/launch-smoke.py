#!/usr/bin/env python3
"""CI startup smoke check, not Accessibility or Screen Recording acceptance."""
import pathlib
import plistlib
import re
import subprocess

bundle = pathlib.Path('build/slime.app/Contents')
with (bundle / 'Info.plist').open('rb') as source:
    minimum = plistlib.load(source)['LSMinimumSystemVersion']
assert minimum == '15.0', minimum
binary = bundle / 'MacOS/slime'
load_commands = subprocess.check_output(['vtool', '-show-build', str(binary)], text=True)
minimums = re.findall(r'^\s*minos\s+(\S+)', load_commands, re.MULTILINE)
assert minimums and all(value == minimum for value in minimums), load_commands
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle.parent)], check=True)
# Argument-domain defaults leave the runner's persistent preferences untouched.
with subprocess.Popen([str(binary), '-enabled', 'NO'], stdout=subprocess.PIPE,
                      stderr=subprocess.STDOUT, text=True) as process:
    try:
        output, _ = process.communicate(timeout=5)
        raise AssertionError(f'Application exited early ({process.returncode}): {output}')
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            output, _ = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
            raise AssertionError('Application did not terminate after startup smoke check')
print('Signed bundle targets macOS 15 and stayed running for 5 seconds; TCC not exercised.')
