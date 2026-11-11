"""Run after xcodegen; configure OAuth callback without exposing configuration values."""
import pathlib
import plistlib

root = pathlib.Path(__file__).resolve().parents[1]
config = root / 'AllPlus/GoogleService-Info.plist'
info_path = root / 'AllPlus/Info.plist'
if config.exists():
    settings = plistlib.loads(config.read_bytes())
    if settings.get('BUNDLE_ID') != 'com.study.allplus':
        raise SystemExit('Firebase Bundle ID must match com.study.allplus. Update project.yml and this check if intentionally changing it.')
    if not settings.get('REVERSED_CLIENT_ID') or not settings.get('CLIENT_ID'):
        raise SystemExit('Enable Google sign-in and download a fresh GoogleService-Info.plist.')
    info = plistlib.loads(info_path.read_bytes())
    info['CFBundleURLTypes'] = [{'CFBundleTypeRole': 'Editor', 'CFBundleURLSchemes': [settings['REVERSED_CLIENT_ID']]}]
    info['GIDClientID'] = settings['CLIENT_ID']
    info_path.write_bytes(plistlib.dumps(info))
    print('Firebase and OAuth callback configured.')
else:
    print('No Firebase config: local-only build. Google login will be disabled.')
