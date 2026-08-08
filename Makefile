.DEFAULT_GOAL := local

.PHONY: local build test smoke app verify release clean

local: app

build:
	swift build

test:
	swift test

smoke:
	./scripts/smoke-test.sh

app:
	./scripts/build-app.sh

verify:
	./scripts/verify.sh

release: verify
	cd dist && shasum -a 256 "MPC-MIDI-Converter-macOS-$$(uname -m).zip" > "MPC-MIDI-Converter-macOS-$$(uname -m).zip.sha256"

clean:
	swift package clean
	rm -rf dist
