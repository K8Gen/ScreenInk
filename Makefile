APP := build/ScreenInk.app

.PHONY: install build run test selftest check screenshots icon clean

install: ## Install the build toolchain (Command Line Tools) if missing
	scripts/install-toolchain.sh

build: ## Build the arm64 app bundle into build/
	scripts/build-app.sh

run: build ## Build, then (re)launch the app
	@pkill -x ScreenInk || true
	open $(APP)

test: ## Unit tests
	scripts/test.sh

selftest: build ## Off-screen rendering self-test; PNGs go to build/selftest
	$(APP)/Contents/MacOS/ScreenInk --self-test build/selftest

check: test selftest ## Everything CI runs

screenshots: build ## Re-render the README images into docs/images
	$(APP)/Contents/MacOS/ScreenInk --screenshots docs/images

icon: ## Re-draw Resources/AppIcon.icns and docs/images/icon.png
	swift scripts/make-icon.swift .

clean:
	rm -rf build .build
