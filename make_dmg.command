#!/bin/bash
set -euo pipefail

# Pipa.dmg для релиза: окно с фоном (assets/draw_dmg_background.swift),
# Pipa и ярлык «Программы» по местам, без панелей Finder, иконка тома — Pipa.
# Раскладку окна пишет dmgbuild (ставится в свой venv в кэше), без
# AppleScript к Finder. Сначала собирает приложение (build.command).

ROOT="$(cd "$(dirname "$0")" && pwd)"
"$ROOT/build.command"

CACHE="$(getconf DARWIN_USER_CACHE_DIR)pipa"
VENV="$CACHE/dmgbuild-venv"
[[ -x "$VENV/bin/dmgbuild" ]] || { python3 -m venv "$VENV" && "$VENV/bin/pip" install -q dmgbuild; }

# Фон ×1 и ×2 в одном TIFF — Finder сам берёт Retina-вариант.
BG="$(mktemp -d)"
for s in 1 2; do swift "$ROOT/assets/draw_dmg_background.swift" "$BG/bg$s.png" $s; done
tiffutil -cathidpicheck "$BG/bg1.png" "$BG/bg2.png" -out "$BG/background.tiff" >/dev/null 2>&1

cat > "$BG/settings.py" <<EOF
import os.path
app = "$ROOT/Pipa.app"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = "$ROOT/assets/AppIcon.icns"
background = "$BG/background.tiff"
format = "UDZO"
compression_level = 9
filesystem = "HFS+"
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((200, 140), (640, 400))
icon_size = 112
text_size = 13
# Центры значков — те же, что под стрелкой на фоне.
icon_locations = {"Pipa.app": (170, 175), "Applications": (470, 175)}
EOF

DMG="$ROOT/Pipa.dmg"
rm -f "$DMG"
"$VENV/bin/dmgbuild" -s "$BG/settings.py" Pipa "$DMG" >/dev/null

echo "Готово: $DMG ($(du -h "$DMG" | cut -f1))"
