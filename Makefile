.PHONY: package release-dmg

DMG_NAME := window-switcher.dmg
APP_PATH := build/window-switcher-mac.app
DMG_IDENTIFIER := jp.blk.windowswitcher.dmg

package:
	test -d "$(APP_PATH)"
	rm -f "$(DMG_NAME)"
	create-dmg \
		--volname "Window Switcher" \
		--app-drop-link 600 185 \
		--icon-size 100 \
		--icon "window-switcher-mac.app" 200 190 \
		--window-pos 200 120 \
		--window-size 800 400 \
		"$(DMG_NAME)" ./build

release-dmg:
	@test -n "$(SIGNING_IDENTITY)" || { echo 'Set SIGNING_IDENTITY to your Developer ID Application identity'; exit 1; }
	@test -n "$(NOTARY_PROFILE)" || { echo 'Set NOTARY_PROFILE to a notarytool keychain profile'; exit 1; }
	$(MAKE) package
	codesign --sign "$(SIGNING_IDENTITY)" --timestamp --identifier "$(DMG_IDENTIFIER)" "$(DMG_NAME)"
	codesign --verify --strict --verbose=2 "$(DMG_NAME)"
	xcrun notarytool submit "$(DMG_NAME)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(DMG_NAME)"
	xcrun stapler validate "$(DMG_NAME)"
