#!/bin/zsh
# Packages a signed QueepMac.app into a drag-to-Applications DMG.
# The disk image and the mounted volume both use Distribution/Queep.icns.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:?path to QueepMac.app}"
dmg="${2:-$root/build/Queep.dmg}"
icon="$root/Distribution/Queep.icns"
volname="Queep"

[[ -d "$app" ]] || { echo "App not found: $app" >&2; exit 1; }
[[ -f "$icon" ]] || { echo "Missing $icon — run Scripts/render-app-icons.swift first" >&2; exit 1; }

work="$(mktemp -d)"
stage="$work/src"
mkdir -p "$stage"
mount=""
cleanup() {
  if [[ -n "$mount" ]]; then
    hdiutil detach "$mount" >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT
cp -R "$app" "$stage/Queep.app"
ln -s /Applications "$stage/Applications"

mkdir -p "$(dirname "$dmg")"
rw="$work/Queep-rw.dmg"
hdiutil create -volname "$volname" -srcfolder "$stage" -ov -format UDRW "$rw" >/dev/null

mount="$(hdiutil attach "$rw" -readwrite -noverify -noautoopen | sed -n 's/.*\(\/Volumes\/.*\)/\1/p' | tail -1)"
cp "$icon" "$mount/.VolumeIcon.icns"
SetFile -a C "$mount"
hdiutil detach "$mount" >/dev/null
mount=""
hdiutil convert "$rw" -format UDZO -ov -o "$dmg" >/dev/null

swift -e 'import AppKit
let icon = CommandLine.arguments[1]
let file = CommandLine.arguments[2]
guard let image = NSImage(contentsOfFile: icon) else { fputs("Could not load icon\n", stderr); exit(1) }
NSWorkspace.shared.setIcon(image, forFile: file, options: [])
' "$icon" "$dmg"

echo "Wrote $dmg"
