.PHONY: generate open clean build test

generate:
	xcodegen generate

open: generate
	open BrowserHop.xcodeproj

build: generate
	xcodebuild -scheme BrowserHop -configuration Release -destination "generic/platform=macOS" CODE_SIGNING_ALLOWED=NO build -quiet

test: generate
	xcodebuild -scheme BrowserHop -configuration Debug test -quiet

clean:
	rm -rf BrowserHop.xcodeproj .build
