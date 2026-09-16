APP_NAME = Cairn
BUNDLE_ID = com.lucassanjuan.Cairn
SOURCES = $(wildcard Sources/*.swift)
SWIFTC = swiftc
SWIFTC_FLAGS = -sdk $$(xcrun --show-sdk-path --sdk macosx) -target arm64-apple-macos12.0 -parse-as-library

all: $(APP_NAME).app

$(APP_NAME).app: $(SOURCES) Info.plist
	@mkdir -p $@/Contents/MacOS
	@mkdir -p $@/Contents/Resources
	@cp Info.plist $@/Contents/
	$(SWIFTC) $(SWIFTC_FLAGS) $(SOURCES) -o $@/Contents/MacOS/$(APP_NAME)
	codesign --force --deep --sign - $@
	@echo "Build complete. Run with: open $(APP_NAME).app"

clean:
	rm -rf $(APP_NAME).app
