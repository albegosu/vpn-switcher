DERIVED := build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/VPNSwitcher.app
SWIFT_SOURCES := $(shell find VPNSwitcher -name '*.swift')

.PHONY: gen build run test typecheck install clean

gen:
	xcodegen generate

build: gen
	xcodebuild -project VPNSwitcher.xcodeproj -scheme VPNSwitcher -configuration Debug \
		-derivedDataPath $(DERIVED) build

run: build
	-pkill -x VPNSwitcher
	open $(APP)

install: build
	-pkill -x VPNSwitcher
	rm -rf /Applications/VPNSwitcher.app
	cp -R $(APP) /Applications/VPNSwitcher.app
	open /Applications/VPNSwitcher.app

test: gen
	xcodebuild -project VPNSwitcher.xcodeproj -scheme VPNSwitcher \
		-derivedDataPath $(DERIVED) test

# Verificación rápida sin Xcode (solo Command Line Tools): no produce la .app,
# pero valida tipos y concurrencia estricta de todo el target principal.
typecheck:
	swiftc -typecheck -swift-version 6 -target arm64-apple-macos15.0 \
		-parse-as-library $(SWIFT_SOURCES)

clean:
	rm -rf build VPNSwitcher.xcodeproj
