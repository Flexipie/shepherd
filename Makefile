.PHONY: build test app run demo perf fixture clean

build:
	swift build

test:
	swift test

app:
	scripts/bundle.sh release

run: app
	-pkill -x Shepherd
	open build/Shepherd.app

# The app on a made-up herd, beside any Shepherd already running
demo: app
	open -n build/Shepherd.app --args --demo

# Idle budget check against fake herdr: fails if idle CPU or footprint is over docs/PRD.md
perf:
	scripts/perf.sh

# Records a sanitised fixture from the running herdr: make fixture NAME=basic SECONDS=10
fixture:
	swift run RecordFixture $(NAME) $(SECONDS)

clean:
	rm -rf .build build
