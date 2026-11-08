#!/bin/zsh
set -eu
cd "${0:A:h}"
app_bundle=build/screeny.app
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
target_archs="${SCREENY_ARCHS:-$(uname -m)}"
binaries=()
for target_arch in ${=target_archs}; do
    case "$target_arch" in arm64|x86_64) ;; *) print -u2 "Unsupported architecture: $target_arch"; exit 1 ;; esac
    binary="build/screeny-$target_arch"
    xcrun swiftc -O -whole-module-optimization -module-cache-path build/ModuleCache -target "$target_arch-apple-macosx14.0" Sources/*.swift -o "$binary"
    binaries+=("$binary")
done
xcrun lipo -create "${binaries[@]}" -output "$app_bundle/Contents/MacOS/screeny"
strip -x "$app_bundle/Contents/MacOS/screeny"
cp Info.plist "$app_bundle/Contents/Info.plist"
cp Assets/AppIcon.icns "$app_bundle/Contents/Resources/AppIcon.icns"
if [[ -n "${SCREENY_VERSION:-}" ]]; then
    if [[ ! "$SCREENY_VERSION" =~ '^[0-9]+(\.[0-9]+){0,2}$' ]]; then
        print -u2 'SCREENY_VERSION must be a numeric version, such as 1.0.0'; exit 1
    fi
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SCREENY_VERSION" "$app_bundle/Contents/Info.plist"
fi
if [[ -n "${SCREENY_BUILD_VERSION:-}" ]]; then
    if [[ ! "$SCREENY_BUILD_VERSION" =~ '^[0-9]+$' ]]; then
        print -u2 'SCREENY_BUILD_VERSION must be numeric'; exit 1
    fi
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $SCREENY_BUILD_VERSION" "$app_bundle/Contents/Info.plist"
fi
plutil -lint "$app_bundle/Contents/Info.plist"
codesign --force --sign - "$app_bundle"
codesign --verify --strict "$app_bundle"
