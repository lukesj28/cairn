APP_NAME = Cairn
SOURCES = $(wildcard Sources/*.swift)
CHECKS = Tests/GeometryChecks.swift
BUILD_DIR = build
SWIFTC = swiftc
SDK = $$(xcrun --show-sdk-path --sdk macosx)
TARGET = arm64-apple-macos12.0
SWIFTC_FLAGS = -sdk $(SDK) -target $(TARGET)

.PHONY: all check run clean

all: $(APP_NAME).app

$(APP_NAME).app: $(SOURCES) Info.plist
	@mkdir -p $@/Contents/MacOS
	@mkdir -p $@/Contents/Resources
	@cp Info.plist $@/Contents/
	$(SWIFTC) $(SWIFTC_FLAGS) -O -parse-as-library $(SOURCES) -o $@/Contents/MacOS/$(APP_NAME)
	codesign --force --deep --sign - $@
	@echo "Build complete. Run with: make run"

check: $(BUILD_DIR)/geometry-checks
	$(BUILD_DIR)/geometry-checks

$(BUILD_DIR)/geometry-checks: Sources/ScreenGeometry.swift $(CHECKS)
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) $(SWIFTC_FLAGS) Sources/ScreenGeometry.swift $(CHECKS) -o $@

run: $(APP_NAME).app
	open $(APP_NAME).app

clean:
	rm -rf $(APP_NAME).app $(BUILD_DIR)
