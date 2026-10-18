#!/usr/bin/env bash
# Builds the standalone Linux Bytefray Spectator executable with Godot 4.7.2
# (and its export templates), then runs the build's --check against the
# bundled presentations. Usage: GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 packaging/build.sh
#
# The project-root export_presets.cfg is git-ignored; packaging/export_presets.cfg
# is copied into place for the export and an existing one is restored afterwards.
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
godot="${GODOT:-godot}"
command -v "$godot" >/dev/null 2>&1 || [ -x "$godot" ] || { echo "Godot 4.7.2 not found; set GODOT" >&2; exit 2; }
presets="$project/export_presets.cfg"
backup=""
if [ -e "$presets" ]; then backup="$presets.user-backup"; mv -f "$presets" "$backup"; fi
restore() { rm -f "$presets"; if [ -n "$backup" ]; then mv -f "$backup" "$presets"; fi; }
trap restore EXIT
cp "$project/packaging/export_presets.cfg" "$presets"
out="$project/build/linux/bytefray-spectator.x86_64"
mkdir -p "$(dirname "$out")"
rm -f "$out"
"$godot" --headless --path "$project" --import >/dev/null 2>&1 || true
"$godot" --headless --path "$project" --export-release "Linux" "$out"
[ -f "$out" ] || { echo "Linux export failed" >&2; exit 1; }
chmod +x "$out"
echo "Linux: $out ($(stat -c %s "$out") bytes, sha256 $(sha256sum "$out" | cut -d' ' -f1))"
for fixture in showcase dev sample; do
    "$out" --headless -- "--fixture=$fixture" --check
done
