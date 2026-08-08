#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
smoke_dir="$repo_root/work/smoke"
input="$smoke_dir/GM Groove.mid"
expected="$smoke_dir/expected.mid"
output="$smoke_dir/GM Groove-mpc.mid"

mkdir -p "$smoke_dir"
rm -f "$input" "$expected" "$output"
swift "$repo_root/scripts/generate-smoke-midi.swift" "$input" "$expected"

bin_dir="$(swift build -c release --show-bin-path)"
"$bin_dir/mpc-midi-converter" "$input"
cmp "$output" "$expected"

echo "Smoke conversion passed: $output"
