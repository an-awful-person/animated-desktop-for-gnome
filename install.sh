#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Installs (copies) the extension into the user's GNOME Shell extensions dir.
# Re-run after editing any file, then log out/in (Wayland can't reload the shell).
set -euo pipefail

UUID="lowpoly-waves@local"
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.local/share/gnome-shell/extensions/$UUID"

mkdir -p "$DEST/schemas"
mkdir -p "$DEST/shaders"
rm -rf "$DEST/shader.glsl" "$DEST/shaders"
mkdir -p "$DEST/shaders"
cp "$SRC"/{metadata.json,extension.js,prefs.js} "$DEST/"
cp "$SRC"/shaders/*.glsl "$DEST/shaders/"
cp "$SRC"/schemas/*.gschema.xml "$DEST/schemas/"
glib-compile-schemas "$DEST/schemas"

# Mark as enabled (takes effect at next login if the shell doesn't know it yet).
if ! gnome-extensions enable "$UUID" 2>/dev/null; then
    current="$(gsettings get org.gnome.shell enabled-extensions)"
    if [[ "$current" != *"'$UUID'"* ]]; then
        if [[ "$current" == "@as []" || "$current" == "[]" ]]; then
            gsettings set org.gnome.shell enabled-extensions "['$UUID']"
        else
            gsettings set org.gnome.shell enabled-extensions "${current%]}, '$UUID']"
        fi
    fi
fi

echo "Installed to $DEST"
echo "Log out and back in to load it. Settings: gnome-extensions prefs $UUID"
echo "Turn off any time:  gnome-extensions disable $UUID"
