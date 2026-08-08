.PHONY: build test smoke app verify clean

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

clean:
	swift package clean
	rm -rf dist
