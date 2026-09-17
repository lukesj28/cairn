APP_NAME = Cairn
BUILD_CONFIG = release
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
SOURCES = $(shell find Sources -name '*.swift')

.PHONY: all test run clean

all: $(APP_NAME).app

$(APP_NAME).app: $(SOURCES) Info.plist Package.swift
	swift build -c $(BUILD_CONFIG) --product $(APP_NAME)
	@mkdir -p $@/Contents/MacOS
	@mkdir -p $@/Contents/Resources
	@cp Info.plist $@/Contents/
	@cp .build/$(BUILD_CONFIG)/$(APP_NAME) $@/Contents/MacOS/$(APP_NAME)
	codesign --force --deep --sign - $@
	@echo "Build complete. Run with: make run"

test:
	DEVELOPER_DIR=$(DEVELOPER_DIR) swift test

run: $(APP_NAME).app
	open $(APP_NAME).app

clean:
	rm -rf $(APP_NAME).app .build build
