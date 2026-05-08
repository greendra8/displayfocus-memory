.PHONY: build app run clean

APP_NAME := DisplayFocusMemory
APP_BUNDLE := build/DisplayFocusMemory.app
APP_CONTENTS := $(APP_BUNDLE)/Contents
APP_MACOS := $(APP_CONTENTS)/MacOS

build:
	swift build -c release

app: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_MACOS)"
	cp Info.plist "$(APP_CONTENTS)/Info.plist"
	cp ".build/release/$(APP_NAME)" "$(APP_MACOS)/$(APP_NAME)"
	chmod +x "$(APP_MACOS)/$(APP_NAME)"
	codesign --force --deep --sign - "$(APP_BUNDLE)"

run: app
	open "$(APP_BUNDLE)"

clean:
	rm -rf .build build
