#!/usr/bin/env bash
set -euo pipefail

# Stock Tracker — local installer for Omarchy Quattro
# Copies this repo (which IS the plugin folder) to ~/.config/omarchy/plugins/
# Validates, rescans, and optionally adds to bar.

PLUGIN_ID="io.github.ardfard.stock-tracker"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

echo "→ Stock Tracker installer"
echo "  Source: $SRC_DIR"
echo "  Dest:   $DEST_DIR"
echo ""

# 1. Check dependencies
if ! command -v omarchy >/dev/null 2>&1; then
  echo "✗ 'omarchy' not found. Are you on Omarchy Quattro?" >&2
  exit 1
fi

# 2. Create dest & copy files (manifest + QML + JS are required)
mkdir -p "$DEST_DIR"
echo "→ Copying plugin files..."
cp -v "$SRC_DIR/manifest.json" "$SRC_DIR/BarWidget.qml" "$SRC_DIR/Panel.qml" "$SRC_DIR/Model.js" "$DEST_DIR/"
# optional docs
cp -v "$SRC_DIR/README.md" "$SRC_DIR/LICENSE" "$DEST_DIR/" 2>/dev/null || true

# sanity: no symlinks, no omarchy.* id
if [[ -L "$DEST_DIR/manifest.json" ]]; then echo "✗ symlink detected" >&2; exit 1; fi

# 3. Validate
echo ""
echo "→ Validating manifest..."
if ! omarchy plugin validate "$DEST_DIR"; then
  echo "✗ omarchy plugin validate failed" >&2
  exit 1
fi
echo "✓ manifest OK"

# 4. QML lint (best-effort — skipped if qmllint/OMARCHY_PATH missing)
if command -v qmllint >/dev/null 2>&1 && [[ -n "${OMARCHY_PATH:-}" && -d "$OMARCHY_PATH/shell" ]]; then
  echo "→ Linting QML..."
  qmllint -I "$OMARCHY_PATH/shell" "$DEST_DIR/BarWidget.qml" "$DEST_DIR/Panel.qml"
  echo "✓ qmllint OK"
else
  echo "→ Skipping qmllint (qmllint or \$OMARCHY_PATH/shell not found)"
  echo "  Run manually: qmllint -I \"\$OMARCHY_PATH/shell\" \"$DEST_DIR/BarWidget.qml\" \"$DEST_DIR/Panel.qml\""
fi

# 5. Rescan plugins
echo ""
echo "→ Rescanning plugins..."
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins || echo "  (rescanPlugins failed — shell may not be running, continuing)"
else
  echo "  (omarchy-shell not found — skipping rescan)"
fi

# 6. Show status
echo ""
if omarchy plugin list --json 2>/dev/null | grep -q "\"id\": \"$PLUGIN_ID\""; then
  echo "✓ Plugin discovered:"
  omarchy plugin list --json | jq --arg id "$PLUGIN_ID" '.[] | select(.id==$id) | {id, kinds, enabled}' 2>/dev/null || \
    omarchy plugin list 2>/dev/null | grep -A2 "$PLUGIN_ID" || true
else
  echo "⚠ Plugin not yet listed — try: omarchy-shell shell rescanPlugins"
  echo "  Check: omarchy plugin list --json | jq"
fi

# 7. Offer to add to bar layout
SHELL_JSON="$HOME/.config/omarchy/shell.json"
if [[ -f "$SHELL_JSON" ]]; then
  if grep -q "\"id\": \"$PLUGIN_ID\"" "$SHELL_JSON" 2>/dev/null; then
    echo ""
    echo "✓ Already in shell.json"
  else
    echo ""
    read -rp "Add '$PLUGIN_ID' to bar center? [Y/n] " ans
    ans=${ans:-Y}
    if [[ "$ans" =~ ^[Yy] ]]; then
      # Backup then insert via python (jq would be fragile for nested layout)
      cp "$SHELL_JSON" "$SHELL_JSON.bak.$(date +%Y%m%d%H%M%S)"
      python3 - <<PY
import json, pathlib
p = pathlib.Path("$SHELL_JSON")
data = json.loads(p.read_text())
bar = data.setdefault("bar", {})
layout = bar.setdefault("layout", {})
center = layout.setdefault("center", [])
if not any(e.get("id")=="$PLUGIN_ID" for e in center):
    # insert after clock if present, otherwise append
    idx = next((i for i,e in enumerate(center) if e.get("id")=="omarchy.clock"), -1)
    center.insert(idx+1 if idx>=0 else len(center), {"id":"$PLUGIN_ID"})
    p.write_text(json.dumps(data, indent=2) + "\n")
    print("✓ Added to bar.layout.center (backup created)")
else:
    print("already present")
PY
      echo "  Restart shell or run: omarchy restart shell  (or logout/login)"
    else
      echo "  Skipped — enable manually in Omarchy bar settings or shell.json"
    fi
  fi
fi

echo ""
echo "Done. Test:"
echo "  omarchy-shell shell summon $PLUGIN_ID '{}'"
echo "  omarchy-shell shell hide $PLUGIN_ID"
echo ""
echo "Customize watchlist: click bar ticker → Panel → Add (e.g. AAPL, BBCA.JK, ^JKSE)"
echo "Presets: US Tech / IDX Blue Chip / ^JKSE are built-in. See README.md"
