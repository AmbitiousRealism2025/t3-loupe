#!/usr/bin/env bash
# Install T3 Loupe into the Omarchy shell.
#
#   tools/install.sh                        copy + enable, widget on the bar's right
#   tools/install.sh --section left|center  choose the bar section instead
#   tools/install.sh --notch-strip          place it in the custom Notch Strip's right flank
#   tools/install.sh --copy-only            update files only (hot reload picks them up)
set -euo pipefail

ID="ambitiousrealism.t3-loupe"
SRC="$(cd "$(dirname "$0")/.." && pwd)/plugin"
DEST="$HOME/.config/omarchy/plugins/$ID"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
STRIP_LAYOUT="$HOME/.config/omarchy/plugins/ambitiousrealism.notch-strip/layout.json"

section="right"
mode="bar"
while (( $# )); do
  case "$1" in
    --section) section="${2:?--section needs left, center or right}"; shift 2 ;;
    --notch-strip) mode="strip"; shift ;;
    --copy-only) mode="copy"; shift ;;
    -h|--help) sed -n 2,8p "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

# The collector runs as plain TypeScript: Node 22.18+ strips types natively.
if ! node_version=$(node --version 2>/dev/null); then
  echo "Node.js 22.18 or newer must be on PATH (the shell's PATH, not just your terminal's)." >&2
  exit 1
fi
IFS=. read -r major minor _ <<<"${node_version#v}"
if (( major < 22 || (major == 22 && minor < 18) )); then
  echo "Node $node_version found; T3 Loupe needs 22.18 or newer." >&2
  exit 1
fi

mkdir -p "$DEST"
rsync -a --delete --exclude '__pycache__' "$SRC/" "$DEST/"
chmod 0755 "$DEST/daemon/main.ts" "$DEST/bin/focus-t3"
echo "Copied plugin to $DEST"

case "$mode" in
  copy) ;;
  bar)
    omarchy plugin enable "$ID" --section "$section"
    ;;
  strip)
    [[ -f $STRIP_LAYOUT ]] || { echo "Notch Strip layout not found at $STRIP_LAYOUT" >&2; exit 1; }
    stamp=$(date +%Y%m%d-%H%M%S)
    cp -p "$SHELL_JSON" "$SHELL_JSON.before-t3-loupe-$stamp"
    cp -p "$STRIP_LAYOUT" "$STRIP_LAYOUT.before-t3-loupe-$stamp"
    # Service entry (shared collector), then the visual widget in the strip.
    tmp=$(mktemp)
    jq --arg id "$ID" 'if any(.plugins[]?; .id == $id) then . else .plugins = ([{id: $id}] + (.plugins // [])) end' "$SHELL_JSON" >"$tmp" && mv "$tmp" "$SHELL_JSON"
    tmp=$(mktemp)
    jq --arg id "$ID" 'if any(.right[]?; .id == $id) then . else .right = ((.right // []) + [{id: $id}]) end' "$STRIP_LAYOUT" >"$tmp" && mv "$tmp" "$STRIP_LAYOUT"
    echo "Enabled $ID and placed it on the Notch Strip's right (backups: *.before-t3-loupe-$stamp)"
    ;;
esac

echo
echo "Pair a T3 environment if you have not yet:"
echo "  node $DEST/daemon/main.ts pair-local                 # this machine"
echo "  node $DEST/daemon/main.ts pair-ssh --ssh-host HOST   # a remote machine with an ssh -L forward"
echo "  node $DEST/daemon/main.ts doctor"
