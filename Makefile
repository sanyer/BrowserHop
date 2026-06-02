.PHONY: generate open clean build build-ci test install unregister dmg-test

generate:
	xcodegen generate

open: generate
	open BrowserHop.xcodeproj

build: generate
	xcodebuild -scheme BrowserHop -configuration Release -destination "generic/platform=macOS" build -quiet

build-ci: generate
	xcodebuild -scheme BrowserHop -configuration Release -destination "generic/platform=macOS" CODE_SIGNING_ALLOWED=NO build -quiet

test: generate
	xcodebuild -scheme BrowserHop -configuration Debug test -quiet

clean:
	rm -rf BrowserHop.xcodeproj .build

install: build
	rm -rf /Applications/BrowserHop.app
	ditto .build/DerivedData/Build/Products/Release/BrowserHop.app /Applications/BrowserHop.app
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister /Applications/BrowserHop.app

dmg-test:
	rm -f .build/release/test.dmg
	mkdir -p .build/release
	create-dmg \
		--volname "BrowserHop" \
		--background "scripts/dmg-assets/background.png" \
		--window-pos 200 120 \
		--window-size 600 400 \
		--icon-size 80 \
		--icon "BrowserHop.app" 150 165 \
		--app-drop-link 450 165 \
		--hide-extension "BrowserHop.app" \
		--no-internet-enable \
		.build/release/test.dmg \
		/Applications/BrowserHop.app
	open .build/release/test.dmg

unregister:
	@echo "Unregistering stale BrowserHop copies..."
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump \
		| grep "BrowserHop.app" | grep "path:" | sed 's/.*path: *//' | sed 's/ (0x.*//' \
		| grep -v "^/Applications/BrowserHop.app$$" \
		| while read -r p; do \
			echo "  Removing: $$p"; \
			/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$$p" 2>/dev/null; \
		done
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister /Applications/BrowserHop.app 2>/dev/null || true
	@echo "Done. Only /Applications/BrowserHop.app remains registered."
