# Phoenix Slides

Official web site: <https://blyt.net/phxslides/>

Phoenix Slides aims to be the fastest way to browse and view the image files
on your disk. Features include the following:

- Fast thumbnailing. Uses embedded EXIF (for jpeg and heic) or JPEG (for raw) previews when appropriate. Otherwise uses macOS's Image I/O framework to scale down images quickly.
- Slideshows (full screen or in a window) with random, loop, and/or auto-advance options
- Special support for sorting files by EXIF (creation) date
- Support for animated GIF and WebP files
- Support for viewing EXIF metadata

And of course, it is open source! After a major code overhaul the source should be
fairly readable now. It's not Swift (this app was started in 2005 when macOS was
called OS X 10.3 and the system frameworks still had very basic bugs in them),
but it's modern!

Enjoy!

## Localization

If anyone wants to help translate to any currently supported or new languages,
let me know. Lately I've been just plugging new strings into google translate
and massaging those results. (I don't actually speak Italian!)

## Compiling

The master branch will generally require the latest version of Xcode.

The easiest way to build is to open `creevey.xcodeproj` in Xcode and press ⌘R.
The commands below cover building, running, and packaging from the command line;
run them from the repository root. The single scheme/target is named
`Phoenix Slides` and the product is `Phoenix Slides.app`.

### Build

`CODE_SIGNING_ALLOWED=NO` produces an unsigned build for local use, so you don't
need a signing certificate; drop it (and see the packaging section) when building
to distribute.

```sh
# Release build into a predictable ./build folder
xcodebuild -project creevey.xcodeproj -scheme "Phoenix Slides" \
  -configuration Release -derivedDataPath build build CODE_SIGNING_ALLOWED=NO

# Debug build
xcodebuild -project creevey.xcodeproj -scheme "Phoenix Slides" \
  -configuration Debug -derivedDataPath build build CODE_SIGNING_ALLOWED=NO

# Clean
xcodebuild -project creevey.xcodeproj -scheme "Phoenix Slides" clean
rm -rf build
```

The built app lands at `build/Build/Products/Release/Phoenix Slides.app`.

### Run

```sh
open "build/Build/Products/Release/Phoenix Slides.app"
```

### Test

There is no XCTest target, so a successful Release build (which also compiles
the nibs) is the effective smoke test. To quickly syntax-check a single source
file without a full build:

```sh
xcrun --sdk macosx clang -fsyntax-only -fobjc-arc -fmodules \
  -I. -IDYjpegtran -Iexiftags -Ilibjpeg CreeveyController.m
```

### Packaging a DMG for distribution

```sh
APP="build/Build/Products/Release/Phoenix Slides.app"
VERSION=$(xcodebuild -project creevey.xcodeproj -scheme "Phoenix Slides" \
  -showBuildSettings 2>/dev/null | awk '/ MARKETING_VERSION /{print $3}')

rm -rf dist && mkdir -p dist/dmg
cp -R "$APP" dist/dmg/
ln -s /Applications dist/dmg/Applications
hdiutil create -volname "Phoenix Slides" -srcfolder dist/dmg \
  -ov -format UDZO "Phoenix-Slides-$VERSION.dmg"
```

For public distribution the app must be signed with a Developer ID (build with
`CODE_SIGN_IDENTITY`, `DEVELOPMENT_TEAM`, and `OTHER_CODE_SIGN_FLAGS="--options runtime"`),
and the resulting DMG notarized and stapled so Gatekeeper accepts it:

```sh
xcrun notarytool submit "Phoenix-Slides-$VERSION.dmg" \
  --apple-id "you@example.com" --team-id TEAMID \
  --password "app-specific-password" --wait
xcrun stapler staple "Phoenix-Slides-$VERSION.dmg"
```

### Legacy toolchains

Commit 7d0cc7e should compile for 10.6+. https://github.com/gobbledegook/creevey/releases/tag/v1.3.1i

Branch xcode326 will compile a universal binary with PPC support but requires Xcode 3.2.6. https://github.com/gobbledegook/creevey/tree/xcode326

## Etymology

`creevey` was the code name for Phoenix Slides when I first started developing it
and code names were cool.
Colin Creevey is the kid in Harry Potter who keeps taking pictures.
