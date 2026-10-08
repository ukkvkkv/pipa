#!/bin/bash
set -euo pipefail

# Pipa.dmg для релиза: приложение + ярлык «Программы», иконка тома — иконка Pipa.
# Сначала собирает приложение (build.command).

ROOT="$(cd "$(dirname "$0")" && pwd)"
"$ROOT/build.command"

STAGE="$(mktemp -d)/Pipa"
mkdir -p "$STAGE"
cp -R "$ROOT/Pipa.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/assets/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
SetFile -c icnC "$STAGE/.VolumeIcon.icns" 2>/dev/null || true

DMG="$ROOT/Pipa.dmg"
rm -f "$DMG"
RW="$(mktemp -d)/rw.dmg"
hdiutil create -volname Pipa -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
MNT="$(hdiutil attach -nobrowse -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}')"
SetFile -a C "$MNT" 2>/dev/null || true      # том показывает свою иконку
hdiutil detach "$MNT" -quiet
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null

echo "Готово: $DMG ($(du -h "$DMG" | cut -f1))"
