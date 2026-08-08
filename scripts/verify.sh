#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"

swift test
swift build -c release --product mpc-midi-converter
"$repo_root/scripts/smoke-test.sh"
"$repo_root/scripts/build-app.sh"

app="$repo_root/dist/MPC MIDI Converter.app"
archive="$repo_root/dist/MPC MIDI Converter.zip"
plutil -lint "$app/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$app"
test -x "$app/Contents/MacOS/MPCMidiConverterApp"
test -f "$app/Contents/Resources/AppIcon.icns"
test -f "$app/Contents/Resources/Profiles/bfd-pop-113.json"
if zipinfo -1 "$archive" | rg -q '(^__MACOSX/|/\._)'; then
    echo "Archive contains unexpected AppleDouble entries." >&2
    exit 1
fi
archive_check_dir="$(mktemp -d -t mpc-midi-converter)"
trap 'rm -rf "$archive_check_dir"' EXIT
ditto -x -k "$archive" "$archive_check_dir"
codesign --verify --deep --strict "$archive_check_dir/MPC MIDI Converter.app"

echo "All verification checks passed."
