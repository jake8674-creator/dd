#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
report="$root/../ios-report"
mkdir -p "$report"
app="$report/FrameFitPad.app"
mkdir -p "$app"
arch="$(uname -m)"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
mapfile_available=no
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find "$root/FrameFitPad.swiftpm/Sources" -name '*.swift' -type f | sort)
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$sdk" -target "$arch-apple-ios17.0-simulator" -module-name FrameFitPad "${sources[@]}" -o "$app/FrameFitPad"
python3 - "$app/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
 plistlib.dump({'CFBundleIdentifier':'local.framefit.pad','CFBundleExecutable':'FrameFitPad','CFBundleName':'FrameFitPad','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'1','MinimumOSVersion':'17.0','UIDeviceFamily':[2],'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},'NSCameraUsageDescription':'Fitting camera','NSMotionUsageDescription':'Gravity reference','UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight']},f)
PY
codesign --force --sign - "$app"
xcrun simctl list devices available -j > "$report/devices.json"
device="$(python3 - "$report/devices.json" <<'PY'
import json,sys
for devices in json.load(open(sys.argv[1]))['devices'].values():
 for d in devices:
  if d.get('isAvailable') and 'iPad' in d['name']:
   print(d['udid']);sys.exit(0)
raise SystemExit('No available iPad simulator')
PY
)"
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
xcrun simctl install "$device" "$app"
xcrun simctl launch "$device" local.framefit.pad
sleep 4
xcrun simctl spawn "$device" launchctl list > "$report/processes.txt"
if ! grep -q 'local.framefit.pad' "$report/processes.txt"; then
  echo 'Application process disappeared after launch'
  exit 1
fi
xcrun simctl io "$device" screenshot "$report/ipad-launch.png"
echo 'Apple SDK compilation and iPad simulator launch passed.'
