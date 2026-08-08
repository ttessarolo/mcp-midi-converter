#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
app_name="MPC MIDI Converter"
bundle="$repo_root/dist/$app_name.app"
contents="$bundle/Contents"
macos_dir="$contents/MacOS"
resources_dir="$contents/Resources"
icon_work="$repo_root/work/AppIcon.iconset"

cd "$repo_root"
swift build -c release --product MPCMidiConverterApp
bin_dir="$(swift build -c release --show-bin-path)"

if [[ -e "$bundle" ]]; then
    rm -rf "$bundle"
fi
mkdir -p "$macos_dir" "$resources_dir" "$icon_work"

cp "$bin_dir/MPCMidiConverterApp" "$macos_dir/MPCMidiConverterApp"
cp "$repo_root/Resources/Info.plist" "$contents/Info.plist"
mkdir -p "$resources_dir/Profiles"
cp "$repo_root/profiles/"*.json "$resources_dir/Profiles/"

icon_master="$repo_root/work/AppIcon-1024.png"
swift "$repo_root/scripts/generate-icon.swift" "$icon_master"

typeset -A icon_sizes
icon_sizes=(
    icon_16x16.png 16
    icon_16x16@2x.png 32
    icon_32x32.png 32
    icon_32x32@2x.png 64
    icon_128x128.png 128
    icon_128x128@2x.png 256
    icon_256x256.png 256
    icon_256x256@2x.png 512
    icon_512x512.png 512
    icon_512x512@2x.png 1024
)
for filename size in ${(kv)icon_sizes}; do
    sips -z "$size" "$size" "$icon_master" --out "$icon_work/$filename" >/dev/null
done
iconutil -c icns "$icon_work" -o "$resources_dir/AppIcon.icns"

plutil -lint "$contents/Info.plist" >/dev/null
codesign --force --sign - "$bundle" >/dev/null
codesign --verify --deep --strict "$bundle"

archive="$repo_root/dist/MPC-MIDI-Converter-macOS-$(uname -m).zip"
rm -f "$archive"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$bundle" "$archive"

echo "$bundle"
echo "$archive"
