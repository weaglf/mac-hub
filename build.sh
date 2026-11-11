#!/bin/zsh
# Hub.app'i derler ve build.noindex/Hub.app olarak paketler (.noindex: Spotlight bu kopyayı listelemez).
#   ./build.sh          → release derleme
#   ./build.sh debug    → debug derleme
#   ./build.sh run      → derle ve aç (build.noindex/ içinden)
#   ./build.sh install  → derle, /Applications/Hub.app olarak kur ve aç
set -euo pipefail
cd "$(dirname "$0")"

MODE=${1:-release}
CONFIG=release
[[ "$MODE" == "debug" ]] && CONFIG=debug

swift build -c "$CONFIG"
BIN_DIR=$(swift build -c "$CONFIG" --show-bin-path)

APP=build.noindex/Hub.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Hub" "$APP/Contents/MacOS/Hub"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" >/dev/null
echo "Hazır: $APP"

if [[ "$MODE" == "run" ]]; then
  pkill -x Hub 2>/dev/null || true
  open "$APP"
fi

if [[ "$MODE" == "install" ]]; then
  DEST=/Applications/Hub.app
  # Yalnızca kendi Hub'ımızın üzerine yaz; aynı adlı başka bir uygulamaya dokunma.
  if [[ -e "$DEST" ]] && [[ "$(defaults read "$DEST/Contents/Info" CFBundleIdentifier 2>/dev/null)" != "local.hub.home" ]]; then
    echo "Durdu: $DEST başka bir uygulamaya ait." >&2
    exit 1
  fi
  pkill -x Hub 2>/dev/null && sleep 1 || true
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  # Spotlight ve Launchpad yeni uygulamayı hemen görsün.
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
  # Geliştirme kopyası "Hub" aramasında ikinci sonuç olarak çıkmasın.
  "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
  echo "Kuruldu: $DEST"
  open "$DEST"
fi
