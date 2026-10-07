#!/usr/bin/env python3
"""Reject thin executables, unsigned helpers or an unsafe update configuration."""
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['SUFeedURL'].startswith('https://'), 'Update feed must use HTTPS'
assert info['SUPublicEDKey'], 'Missing update verification key'
assert (app / 'Contents/Resources/Sparkle-LICENSE.txt').is_file(), 'Missing third-party licenses'
assert info['LSMinimumSystemVersion'] == '14.0', 'Unexpected minimum macOS'
count = 0
for path in app.rglob('*'):
    if path.is_symlink() or not path.is_file():
        continue
    kind = subprocess.check_output(['file', '-b', str(path)], text=True)
    if 'Mach-O' not in kind:
        continue
    arches = set(subprocess.check_output(['lipo', '-archs', str(path)], text=True).split())
    assert {'arm64', 'x86_64'} <= arches, f'Thin executable: {path}: {arches}'
    sig = subprocess.run(['codesign', '-dvv', str(path)], capture_output=True, text=True, check=True).stderr
    assert 'Authority=Developer ID Application:' in sig, f'Not Developer ID signed: {path}'
    assert 'Timestamp=' in sig, f'Missing trusted timestamp: {path}'
    assert 'runtime' in sig, f'Missing hardened runtime: {path}'
    count += 1
assert count >= 6, f'Expected app, daemon and Sparkle helpers; only found {count}'
print(f'Universal architectures + Developer ID + timestamp + hardened runtime verified for {count} Mach-O files.')
