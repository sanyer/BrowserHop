.PHONY: generate open clean

generate:
	xcodegen generate

open: generate
	open BrowserHop.xcodeproj

clean:
	rm -rf BrowserHop.xcodeproj
