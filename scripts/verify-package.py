"""Validate packaged app filters, independent settings keys, sandbox access and icon sizes."""
from pathlib import Path
import plistlib
import struct
import sys

root = Path(sys.argv[1]) / 'var/jb/Library'
bundle = root / 'PreferenceBundles/OBDelevenUpdateBypassPrefs.bundle'

def read(path):
    return plistlib.loads(path.read_bytes())

targets = {'com.voltasit.obdeleven.ios.basic', 'com.voltasit.obdeleven.ios'}
assert set(read(root / 'MobileSubstrate/DynamicLibraries/OBDelevenUpdateBypass.plist')['Filter']['Bundles']) == targets
assert set(read(root / 'libSandy/OBDelevenUpdateBypass_Preferences.plist')['AllowedProcesses']) == targets
entry = read(root / 'PreferenceLoader/Preferences/OBDelevenUpdateBypassPrefs.plist')['entry']
assert entry['label'] == 'OBD11 & OBD11 VAG Bypass'
assert entry['icon'] == 'icon.png'
items = read(bundle / 'Root.plist')['items']
keys = [item['key'] for item in items if 'key' in item]
assert set(keys) == {'enabled', 'spoofedVersion', 'vagEnabled', 'vagSpoofedVersion'}
assert len(keys) == len(set(keys))
actions = {item['action'] for item in items if 'action' in item}
assert actions == {'resetWorkingDefaults', 'resetVAGDefaults', 'respring', 'openGitHub'}
for name, pixels in [('icon.png', 29), ('icon@2x.png', 58), ('icon@3x.png', 87)]:
    data = (bundle / name).read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack('>II', data[16:24]) == (pixels, pixels)
binary = (root / 'MobileSubstrate/DynamicLibraries/OBDelevenUpdateBypass.dylib').read_bytes()
for value in [*targets, 'vagEnabled', 'vagSpoofedVersion', 'x-mobile-app-version', 'x-mobile-app-build', '2147483647']:
    assert value.encode() in binary, value
print('Dual-app package checks passed.')
