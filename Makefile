APP_NAME = Cairn
BUILD_CONFIG ?= release
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

CODESIGN_IDENTITY ?= 599AA5902D1A8E329C1F6E7EF952A5B4C01452F6
NOTARY_PROFILE ?= notary-profile

DIST_DIR ?= dist
DMG_NAME ?= $(APP_NAME).dmg
DMG_PATH = $(DIST_DIR)/$(DMG_NAME)
APP_BUNDLE = $(APP_NAME).app

ENTITLEMENTS ?= Cairn.entitlements
ENTITLEMENTS_FLAG = $(if $(wildcard $(ENTITLEMENTS)),--entitlements $(ENTITLEMENTS),)

SOURCES = $(shell find Sources -name '*.swift')
RESOURCES = $(shell find Sources/$(APP_NAME)/Resources -type f 2>/dev/null)

.PHONY: all dev app-dev app-release dmg notarize release test run clean help

all: dev

define assemble_app
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp Info.plist $(APP_BUNDLE)/Contents/
	@cp .build/$(1)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@if [ -f Sources/$(APP_NAME)/Resources/AppIcon.icns ]; then \
		cp Sources/$(APP_NAME)/Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/; \
	fi
	@if DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun --find actool >/dev/null 2>&1; then \
		DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun actool Sources/$(APP_NAME)/Resources/Assets.xcassets \
			--compile $(APP_BUNDLE)/Contents/Resources \
			--platform macosx \
			--minimum-deployment-target 12.0 \
			--app-icon AppIcon \
			--output-partial-info-plist /tmp/cairn-actool-partial.plist >/dev/null 2>&1; \
		rm -f /tmp/cairn-actool-partial.plist; \
	fi
	@if [ -d .build/$(1)/$(APP_NAME)_$(APP_NAME).bundle ]; then \
		cp -R .build/$(1)/$(APP_NAME)_$(APP_NAME).bundle $(APP_BUNDLE)/Contents/Resources/; \
	fi
endef

dev: app-dev

app-dev: $(SOURCES) $(RESOURCES) Info.plist Package.swift
	DEVELOPER_DIR=$(DEVELOPER_DIR) swift build -c debug --product $(APP_NAME)
	@rm -rf $(APP_BUNDLE)
	$(call assemble_app,debug)
	codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "==> Development build complete: $(APP_BUNDLE)"
	@echo "Run with: make run"

app-release: $(SOURCES) $(RESOURCES) Info.plist Package.swift
	DEVELOPER_DIR=$(DEVELOPER_DIR) swift build -c release --product $(APP_NAME)
	@rm -rf $(APP_BUNDLE)
	$(call assemble_app,release)
	@if [ -d $(APP_BUNDLE)/Contents/Resources/$(APP_NAME)_$(APP_NAME).bundle ]; then \
		codesign --force --timestamp --options runtime --sign "$(CODESIGN_IDENTITY)" \
			$(APP_BUNDLE)/Contents/Resources/$(APP_NAME)_$(APP_NAME).bundle 2>/dev/null || true; \
	fi
	codesign --force --deep --options runtime --timestamp $(ENTITLEMENTS_FLAG) \
		--sign "$(CODESIGN_IDENTITY)" $(APP_BUNDLE)
	codesign --verify --deep --strict --verbose=2 $(APP_BUNDLE)
	@echo "==> Release app signed and verified: $(APP_BUNDLE)"

dmg: app-release
	@mkdir -p $(DIST_DIR)
	@rm -f $(DMG_PATH)
	@rm -rf $(DIST_DIR)/dmg_staging
	@mkdir -p $(DIST_DIR)/dmg_staging
	@cp -R $(APP_BUNDLE) $(DIST_DIR)/dmg_staging/
	@ln -s /Applications $(DIST_DIR)/dmg_staging/Applications
	@echo "==> Creating disk image: $(DMG_PATH)..."
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder $(DIST_DIR)/dmg_staging \
		-ov -format UDZO \
		$(DMG_PATH)
	@rm -rf $(DIST_DIR)/dmg_staging
	@echo "==> Signing DMG..."
	codesign --force --timestamp --sign "$(CODESIGN_IDENTITY)" $(DMG_PATH)
	codesign --verify --verbose=2 $(DMG_PATH)
	@echo "==> DMG successfully created and signed: $(DMG_PATH)"

notarize: dmg
	@echo "==> Submitting $(DMG_PATH) to Apple Notary Service (profile: $(NOTARY_PROFILE))..."
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun notarytool submit $(DMG_PATH) \
		--keychain-profile "$(NOTARY_PROFILE)" \
		--wait
	@echo "==> Stapling notarization ticket to DMG..."
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun stapler staple $(DMG_PATH)
	@echo "==> Validating stapled DMG..."
	spctl -a -t open --context context:primary-signature -v $(DMG_PATH)
	@echo "==> Release DMG notarized and stapled: $(DMG_PATH)"

release: notarize
	@echo "==> Release complete: $(DMG_PATH)"

test:
	DEVELOPER_DIR=$(DEVELOPER_DIR) swift test

run:
	open $(APP_BUNDLE)

clean:
	rm -rf $(APP_BUNDLE) $(DIST_DIR) .build build /tmp/cairn-actool-partial.plist
	@echo "Clean complete."

help:
	@echo "Available make targets:"
	@echo "  make dev          Build debug app with ad-hoc signing (default)"
	@echo "  make app-release  Build release app signed with Developer ID & hardened runtime"
	@echo "  make dmg          Build release app and package into signed DMG ($(DMG_PATH))"
	@echo "  make notarize     Build DMG, submit to Apple Notary Service, and staple ticket"
	@echo "  make release      Full release pipeline (app -> DMG -> notarize -> staple)"
	@echo "  make test         Run Swift test suite"
	@echo "  make run          Launch $(APP_BUNDLE)"
	@echo "  make clean        Remove build directories and artifacts"
