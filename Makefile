.PHONY: build test app run clean

build:
	swift build

test:
	swift test

app:
	scripts/bundle.sh release

run: app
	-pkill -x Shepherd
	open build/Shepherd.app

clean:
	rm -rf .build build
