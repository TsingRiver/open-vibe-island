#!/bin/zsh

set -euo pipefail


skip_setup=false
no_restart=false
skip_build=false
for arg in "$@"; do
  case "$arg" in
    --skip-setup) skip_setup=true ;;
    --no-restart) no_restart=true ;;
    --skip-build) skip_build=true ;;
  esac
done

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
brand_script="$repo_root/scripts/generate_brand_icons.py"
brand_icon="$repo_root/Assets/Brand/OpenIsland.icns"
bundle_dir="$HOME/Applications/Open Island Dev.app"
plist_path="$bundle_dir/Contents/Info.plist"
bundle_binary="$bundle_dir/Contents/MacOS/OpenIslandApp"

cd "$repo_root"

# Keep the generated dev bundle aligned with the latest public appcast entry.
# OPEN_ISLAND_VERSION / OPEN_ISLAND_BUILD_NUMBER remain available for explicit
# local release testing, while the default follows the online stable version.
appcast_metadata="$(python3 - "$repo_root/appcast.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

# Use the XML parser so Sparkle namespace handling stays stable as the feed
# gains metadata. The first item is the newest public release by convention.
sparkle_namespace = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
appcast_path = sys.argv[1]
appcast = ET.parse(appcast_path)
latest_item = appcast.find("./channel/item")
latest_version = None
latest_build = None

if latest_item is not None:
    # Read both bundle-facing version fields from the same appcast item so the
    # generated Info.plist cannot mix metadata from different releases.
    latest_version = latest_item.findtext(
        "sparkle:shortVersionString",
        namespaces=sparkle_namespace,
    )
    latest_build = latest_item.findtext(
        "sparkle:version",
        namespaces=sparkle_namespace,
    )

if not latest_version or not latest_build:
    raise SystemExit("missing latest appcast version metadata")

print(f"{latest_version} {latest_build}")
PY
)"
appcast_short_version="${appcast_metadata%% *}"
appcast_build_number="${appcast_metadata##* }"
dev_short_version="${OPEN_ISLAND_VERSION:-$appcast_short_version}"
dev_build_number="${OPEN_ISLAND_BUILD_NUMBER:-$appcast_build_number}"

if [ "$skip_build" = false ]; then
  swift build -c debug --product OpenIslandApp
  swift build -c debug --product OpenIslandHooks
  swift build -c debug --product OpenIslandSetup
fi

build_root="$(swift build -c debug --show-bin-path)"
app_binary="$build_root/OpenIslandApp"
hooks_binary="$build_root/OpenIslandHooks"
setup_binary="$build_root/OpenIslandSetup"

python3 "$brand_script"
if [ "$skip_setup" = false ]; then
  "$setup_binary" install --hooks-binary "$hooks_binary"
fi

mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Helpers" "$bundle_dir/Contents/Resources" "$bundle_dir/Contents/Frameworks"

if [ "$no_restart" = false ]; then
  # Kill any running instance before copying so the binary isn't locked.
  osascript -e 'tell application "Open Island Dev" to quit' 2>/dev/null || true
  pkill -9 -f "Open Island Dev" 2>/dev/null || true
  sleep 2
fi

# Use rm -f before copying to prevent Text file busy errors if the app is currently running.
rm -f "$bundle_binary"
command cp "$app_binary" "$bundle_binary"
rm -f "$bundle_dir/Contents/Helpers/OpenIslandHooks"
command cp "$hooks_binary" "$bundle_dir/Contents/Helpers/OpenIslandHooks"
rm -f "$bundle_dir/Contents/Helpers/OpenIslandSetup"
command cp "$setup_binary" "$bundle_dir/Contents/Helpers/OpenIslandSetup"
command cp "$brand_icon" "$bundle_dir/Contents/Resources/OpenIsland.icns"
chmod +x "$bundle_binary" "$bundle_dir/Contents/Helpers/OpenIslandHooks" "$bundle_dir/Contents/Helpers/OpenIslandSetup"

# Add rpath so the binary can find Sparkle.framework in Contents/Frameworks/.
install_name_tool -add_rpath @loader_path/../Frameworks "$bundle_binary" 2>/dev/null || true

# Copy SPM resource bundle to .app root — SPM's generated Bundle.module accessor
# searches Bundle.main.bundleURL (the .app root), NOT Contents/Resources/.
resource_bundle="$build_root/OpenIsland_OpenIslandApp.bundle"
if [ -d "$resource_bundle" ]; then
    rm -rf "$bundle_dir/OpenIsland_OpenIslandApp.bundle"
    command cp -R "$resource_bundle" "$bundle_dir/"
fi

# Copy Sparkle.framework for auto-update support.
sparkle_framework="$repo_root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$sparkle_framework" ]; then
    rm -rf "$bundle_dir/Contents/Frameworks/Sparkle.framework"
    command cp -R "$sparkle_framework" "$bundle_dir/Contents/Frameworks/"
fi

# Embed the checkout root so the running dev bundle can safely fast-forward
# origin/main and relaunch itself from the same workspace when a newer appcast
# version is detected.
cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>OpenIslandApp</string>
    <key>CFBundleIdentifier</key>
    <string>app.openisland.dev</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIconFile</key>
    <string>OpenIsland</string>
    <key>CFBundleName</key>
    <string>Open Island Dev</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$dev_short_version</string>
    <key>CFBundleVersion</key>
    <string>$dev_build_number</string>
    <key>OpenIslandDevelopmentRepoRoot</key>
    <string>$repo_root</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Open Island needs automation access to focus Terminal and iTerm sessions for jump-back.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/Octane0411/open-vibe-island/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>3IF8txq9RRNanzE2FNhyGRcwhslTucCcJHpTkpxcgBQ=</string>
</dict>
</plist>
EOF

# Dev builds on macOS 26+: the SPM resource bundle at the .app root
# causes "unsealed contents" codesign failure. Move it into
# Contents/Resources/ so signing succeeds. On the developer machine
# Bundle.module falls back to the hardcoded .build/ path, so
# localization still works. (Release builds use package-app.sh which
# has its own resource bundle handling.)
resource_bundle_name="OpenIsland_OpenIslandApp.bundle"
root_bundle="$bundle_dir/$resource_bundle_name"
resources_bundle="$bundle_dir/Contents/Resources/$resource_bundle_name"
if [ -d "$root_bundle" ] && [ ! -L "$root_bundle" ]; then
    rm -rf "$resources_bundle"
    mv "$root_bundle" "$resources_bundle"
fi
# Remove stale symlinks from previous runs.
[ -L "$root_bundle" ] && rm -f "$root_bundle"

# Detect a local stable signing identity so the dev bundle's cdhash
# stays stable across rebuilds and macOS TCC grants (Accessibility,
# Automation) persist. Without it we fall back to ad-hoc signing, which
# changes the cdhash every build and silently invalidates any TCC
# grants the developer had approved — extremely disruptive when
# iterating on features that need AX permission. See
# scripts/setup-dev-signing.sh for a one-time setup that creates this
# identity locally with zero Apple Developer Program involvement.
sign_identity="-"
if security find-identity -p codesigning -v "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null \
       | grep -q '"Open Island Dev Local"'; then
    sign_identity="Open Island Dev Local"
else
    echo
    echo "⚠ Using ad-hoc signing. macOS TCC grants (Accessibility, Automation)"
    echo "  will be invalidated on every rebuild. Run once to fix:"
    echo "    zsh scripts/setup-dev-signing.sh"
    echo
fi

codesign --force --deep --sign "$sign_identity" "$bundle_dir" 2>/dev/null || true

if [ "$no_restart" = false ]; then
  open -na "$bundle_dir"
fi
