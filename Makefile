APP_NAME = Cairn
BUILD_CONFIG = release
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
SOURCES = $(shell find Sources -name '*.swift')
RESOURCES = $(shell find Sources/$(APP_NAME)/Resources -type f 2>/dev/null)

.PHONY: all test run clean

all: $(APP_NAME).app

$(APP_NAME).app: $(SOURCES) $(RESOURCES) Info.plist Package.swift
	DEVELOPER_DIR=$(DEVELOPER_DIR) swift build -c $(BUILD_CONFIG) --product $(APP_NAME)
	@mkdir -p $@/Contents/MacOS
	@mkdir -p $@/Contents/Resources
	@cp Info.plist $@/Contents/
	@cp .build/$(BUILD_CONFIG)/$(APP_NAME) $@/Contents/MacOS/$(APP_NAME)
	@if [ -f Sources/$(APP_NAME)/Resources/AppIcon.icns ]; then cp Sources/$(APP_NAME)/Resources/AppIcon.icns $@/Contents/Resources/; fi
	@if DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun --find actool >/dev/null 2>&1; then \
		DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun actool Sources/$(APP_NAME)/Resources/Assets.xcassets \
			--compile $@/Contents/Resources \
			--platform macosx \
			--minimum-deployment-target 12.0 \
			--app-icon AppIcon \
			--output-partial-info-plist /tmp/cairn-actool-partial.plist >/dev/null 2>&1; \
		rm -f /tmp/cairn-actool-partial.plist; \
	fi
	@if [ -d .build/$(BUILD_CONFIG)/$(APP_NAME)_$(APP_NAME).bundle ]; then \
		cp -R .build/$(BUILD_CONFIG)/$(APP_NAME)_$(APP_NAME).bundle $@/Contents/Resources/; \
	fi
	codesign --force --deep --sign - $@
	@echo "Build complete. Run with: make run"

test:
	DEVELOPER_DIR=$(DEVELOPER_DIR) swift test

run: $(APP_NAME).app
	open $(APP_NAME).app

clean:
	rm -rf $(APP_NAME).app .build build
