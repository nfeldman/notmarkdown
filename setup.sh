#!/usr/bin/env bash
#
# setup.sh — one-step install for notmarkdown.
# Installs pandoc + typst + mermaidx and puts `mdexport` on your PATH.
#
# Usage:
#   ./setup.sh
#
# Idempotent: safe to re-run. Checks before installing, backs up anything it
# would overwrite. Uninstall notes are in the README.
# ---------------------------------------------------------------------------
set -euo pipefail

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
info() { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
ok()   { printf "\033[1;32m ok\033[0m %s\n" "$1"; }
warn() { printf "\033[1;33m !!\033[0m %s\n" "$1"; }
die()  { printf "\033[1;31m xx\033[0m %s\n" "$1" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bold "notmarkdown setup"

# 1. Conversion engines (Homebrew) -----------------------------------------
command -v brew >/dev/null 2>&1 || die "Homebrew not found — install it from https://brew.sh, then re-run."
for f in pandoc typst; do
  if command -v "$f" >/dev/null 2>&1; then
    ok "$f present"
  else
    info "brew install $f"
    brew install "$f"
  fi
done

# 2. mermaidx — browser-free Mermaid renderer (no headless Chrome) ----------
export PATH="$HOME/.local/bin:$PATH"   # where uv/pipx put console scripts
if command -v mermaidx >/dev/null 2>&1; then
  ok "mermaidx present"
elif command -v uv >/dev/null 2>&1; then
  info "uv tool install mermaidx"
  uv tool install mermaidx || warn "mermaidx install failed"
elif command -v pipx >/dev/null 2>&1; then
  info "pipx install mermaidx"
  pipx install mermaidx || warn "mermaidx install failed"
else
  warn "no uv or pipx found — install one, then: 'uv tool install mermaidx' (diagrams need it)"
fi

# 3. Put mdexport on PATH (symlink back to this repo; assets resolve beside it)
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
chmod +x "$HERE/mdexport" "$HERE/mermaid-render"
DEST="$BIN/mdexport"
if [[ -e "$DEST" && ! -L "$DEST" ]]; then
  cp "$DEST" "$DEST.backup.$(date +%s)" && warn "backed up existing $DEST"
elif [[ -L "$DEST" && "$(readlink "$DEST")" != "$HERE/mdexport" ]]; then
  warn "repointing symlink $DEST (was → $(readlink "$DEST"))"
fi
ln -sf "$HERE/mdexport" "$DEST"
ok "linked mdexport → $DEST"

# 4. PATH check -------------------------------------------------------------
case ":$PATH:" in
  *":$BIN:"*) ok "$BIN is on PATH" ;;
  *) warn "$BIN is not on your PATH — add this to your shell rc:
       export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

echo
bold "Done. ✅"
echo "Try:  mdexport README.md --open"
