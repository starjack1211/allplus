import json
import pathlib
import plistlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class ProjectChecks(unittest.TestCase):
    def test_firebase_bundle_and_google_configuration(self):
        config = plistlib.loads((ROOT / 'AllPlus/GoogleService-Info.plist').read_bytes())
        self.assertEqual(config['BUNDLE_ID'], 'com.study.allplus')
        self.assertTrue(config['CLIENT_ID'])
        self.assertTrue(config['REVERSED_CLIENT_ID'])
        info = plistlib.loads((ROOT / 'AllPlus/Info.plist').read_bytes())
        self.assertEqual(info['GIDClientID'], config['CLIENT_ID'])
        self.assertEqual(info['CFBundleURLTypes'][0]['CFBundleURLSchemes'], [config['REVERSED_CLIENT_ID']])

    def test_required_resources(self):
        assets = ROOT / 'AllPlus/Assets.xcassets/AppIcon.appiconset'
        content = json.loads((assets / 'Contents.json').read_text())
        for image in content['images']:
            self.assertTrue((assets / image['filename']).exists())
        self.assertFalse((ROOT / 'AllPlus/Samples.json').exists())
        for name in ['NSCameraUsageDescription', 'NSPhotoLibraryUsageDescription']:
            self.assertIn(name, plistlib.loads((ROOT / 'AllPlus/Info.plist').read_bytes()))

    def test_build_workflow_runs_tests_before_packaging(self):
        workflow = (ROOT / '.github/workflows/build-ipa.yml').read_text()
        self.assertLess(workflow.index('xcodebuild test'), workflow.index('xcodebuild build'))
        self.assertLess(workflow.index('python3 scripts/configure.py'), workflow.index('xcodebuild test'))
        self.assertIn('generic/platform=iOS', workflow)
        self.assertIn('CODE_SIGNING_ALLOWED=NO', workflow)
        self.assertIn('zip -qry ../AllPlus-unsigned.ipa Payload', workflow)

if __name__ == '__main__':
    unittest.main(verbosity=2)
