#!/usr/bin/env bash
#
# run.sh — regression suite for notmarkdown. Exercises the real pipeline end to
# end and asserts every guarantee and edge case, against BOTH renderer options.
#
# Runs locally and in CI. Requires pandoc + python3; PDF tests need typst; each
# renderer's tests are skipped (not failed) when that renderer is absent or its
# probe render fails (e.g. mmdc present but headless Chrome can't launch in CI).
#
# Exit status: non-zero if any test FAILED (skips do not fail the run).
# ---------------------------------------------------------------------------
set -uo pipefail   # deliberately NOT -e: each test handles its own failure.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MDEXPORT="$REPO/mdexport"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0; skip=0
_g='\033[32m'; _r='\033[31m'; _y='\033[33m'; _b='\033[1m'; _0='\033[0m'
ok()   { printf "  ${_g}PASS${_0} %s\n" "$1"; pass=$((pass+1)); }
bad()  { printf "  ${_r}FAIL${_0} %s\n" "$1"; [ -n "${2:-}" ] && printf "       %s\n" "$2"; fail=$((fail+1)); }
skp()  { printf "  ${_y}SKIP${_0} %s (%s)\n" "$1" "$2"; skip=$((skip+1)); }
have() { command -v "$1" >/dev/null 2>&1; }

# --- assertion helpers -----------------------------------------------------
# Each takes a human name last and reports pass/fail.
assert_rc()        { [ "$1" -eq "$2" ] && ok "$3" || bad "$3" "rc=$1 expected=$2; $(tail -1 "$WORK/.log" 2>/dev/null)"; }
assert_rc_nonzero(){ [ "$1" -ne 0 ]   && ok "$2" || bad "$2" "expected non-zero exit"; }
assert_file()      { [ -s "$1" ] && ok "$2" || bad "$2" "missing/empty: $1"; }
assert_grep()      { grep -qE "$2" "$1" && ok "$3" || bad "$3" "pattern not found: $2"; }
assert_no_grep()   { grep -qE "$2" "$1" && bad "$3" "unexpected pattern: $2" || ok "$3"; }
assert_count()     { local n; n=$(grep -oE "$2" "$1" | wc -l | tr -d ' '); [ "$n" -eq "$3" ] && ok "$4" || bad "$4" "count=$n expected=$3 for $2"; }

fixture() { printf '%s' "$2" > "$WORK/$1"; }
# build FILE ARGS... -> BUILD_RC set; output written next to FILE
build()   { "$MDEXPORT" "$WORK/$1" "${@:2}" >"$WORK/.log" 2>&1; BUILD_RC=$?; }

# --- preflight -------------------------------------------------------------
printf "${_b}notmarkdown regression suite${_0}\n"
have pandoc  || { echo "FATAL: pandoc not found (required)"; exit 2; }
have python3 || { echo "FATAL: python3 not found (required)"; exit 2; }
HAVE_TYPST=0; have typst && HAVE_TYPST=1
printf "tools: pandoc=yes python3=yes typst=%s\n\n" "$([ $HAVE_TYPST = 1 ] && echo yes || echo NO)"

# ===========================================================================
printf "${_b}[unit] svg-scope${_0}\n"
if python3 "$REPO/tests/test_svg_scope.py" >"$WORK/.log" 2>&1; then
  ok "svg-scope unit tests"
else
  bad "svg-scope unit tests" "$(tail -3 "$WORK/.log")"
fi

# ===========================================================================
printf "\n${_b}[math] renderer-agnostic${_0}\n"
fixture math.md '# m

Dollar $E=mc^2$ and paren \(a^2+b^2=c^2\) and display \[\sum_{i=1}^n i\].

Currency: it costs $5 today and $20 tomorrow, $100 total.

$$\begin{aligned} a &= b \\ &= c \end{aligned}$$
'
build math.md --html
assert_rc "$BUILD_RC" 0 "math doc builds"
# $x$, \(..\), \[..\], and the aligned env -> 4 <math> blocks; currency -> none of them.
assert_count "$WORK/math.html" '<math' 4 "all math delimiters -> MathML (\$, \\(\\), \\[\\], env)"
assert_no_grep "$WORK/math.html" 'costs <math|\$5 <math' "currency \$5/\$20 not parsed as math"

fixture gfm.md '- [x] done
- [ ] todo

~~struck~~ text.
'
build gfm.md --html
assert_grep "$WORK/gfm.html" 'type="checkbox"' "GFM task lists render"
assert_grep "$WORK/gfm.html" '<del>|<s>'       "GFM strikethrough renders"

fixture plain.md '# Just prose

No diagrams, no math. Self-contained check.
'
build plain.md --html
assert_rc "$BUILD_RC" 0 "prose-only (zero-diagram) doc builds"
assert_no_grep "$WORK/plain.html" 'src="https?://|href="https?://[^"]*\.(png|jpg|svg|css|js)"' "HTML is self-contained (no remote resources)"

# GitHub-style ToC anchors: LLMs write `[X](#1-x)` for `## 1. X`. Heading ids must
# use GitHub's scheme (keep the number) so the ToC resolves — and so the Typst PDF
# doesn't die on a #link to a nonexistent label.
fixture toc.md '# Doc

- [First Section](#1-first-section)

## 1. First Section

Body.
'
build toc.md --html
assert_rc "$BUILD_RC" 0 "ToC/anchor doc builds (HTML)"
assert_grep "$WORK/toc.html" 'id="1-first-section"' "GitHub-style heading id keeps the number (ToC resolves)"
if [ "$HAVE_TYPST" -eq 1 ]; then
  build toc.md --pdf
  assert_rc "$BUILD_RC" 0 "ToC/anchor doc builds (PDF — no dangling Typst label)"
else
  skp "ToC/anchor PDF" "typst not installed"
fi

# --follow: AST-based link discovery + rewriting. Covers bare and ./-prefixed
# links, reference-style links, %-encoded (spaced) filenames, cycles, code-block
# safety, subdir/URL exclusion, HTML-only, and directory-traversal protection.
FS="$WORK/fset"; mkdir -p "$FS/sub" "$WORK/victim"
printf '# SECRET — must never be exported\n' > "$WORK/victim/secret.md"
cat > "$FS/fa.md" <<'FEOF'
[bare](fb.md), [dot](./frel.md), [refstyle][r], [space](my%20note.md),
[url](https://x.example/z.md), [sub](sub/c.md),
[trav-plain](../victim/secret.md), [trav-enc](%2e%2e%2fvictim%2fsecret.md).

```
code [trap](trap.md) must not be followed
```

[r]: fref.md
FEOF
printf '# B\nback to [a](fa.md).\n' > "$FS/fb.md"   # cycle back to entry
printf '# rel\n'   > "$FS/frel.md"
printf '# ref\n'   > "$FS/fref.md"
printf '# space\n' > "$FS/my note.md"
printf '# trap\n'  > "$FS/trap.md"
printf '# c\n'     > "$FS/sub/c.md"
"$MDEXPORT" "$FS/fa.md" --follow >"$WORK/.log" 2>&1; BUILD_RC=$?
assert_rc "$BUILD_RC" 0 "--follow builds the linked set"
assert_file "$FS/fa.html"      "--follow builds the entry doc"
assert_file "$FS/fb.html"      "--follow follows a bare same-dir link (cycle handled)"
assert_file "$FS/frel.html"    "--follow follows a ./-prefixed link"
assert_file "$FS/fref.html"    "--follow follows a reference-style link"
assert_file "$FS/my note.html" "--follow follows a %-encoded (spaced) filename"
assert_grep "$FS/fa.html" 'href="fb.html"'        "--follow rewrites a bare .md link"
assert_grep "$FS/fa.html" 'href="./frel.html"'    "--follow rewrites a ./ link"
assert_grep "$FS/fa.html" 'href="my%20note.html"' "--follow rewrites an encoded link, keeps encoding"
assert_grep "$FS/fa.html" 'href="https://x.example/z.md"' "--follow leaves URLs untouched"
assert_grep "$FS/fa.html" 'href="sub/c.md"'       "--follow leaves subdir links untouched"
[ -f "$FS/trap.html" ]  && bad "--follow ignores code-block links" "built trap.html" \
                        || ok "--follow ignores code-block links"
[ -f "$FS/sub/c.html" ] && bad "--follow does not descend into subdirs" "built sub/c.html" \
                        || ok "--follow does not descend into subdirs"
[ -f "$WORK/victim/secret.html" ] && bad "--follow blocks directory traversal" "exported victim/secret.html" \
                                  || ok "--follow blocks directory traversal (plain + encoded)"
{ [ -f "$FS/fa.pdf" ] || [ -f "$FS/fb.pdf" ]; } && bad "--follow is HTML-only" "a PDF was produced for a followed doc" \
                                                || ok "--follow is HTML-only (no PDF for followed docs)"

# ===========================================================================
# Per-renderer tests. Each renderer is probed first; a failing probe -> SKIP.
# ===========================================================================
renderer_tests() {
  local label="$1" renderer="$2"
  export MDEXPORT_MERMAID="$renderer"

  # Probe: can this renderer actually render a trivial flowchart here?
  fixture _probe.md '```mermaid
flowchart LR
  A-->B
```
'
  build _probe.md --html
  if [ "$BUILD_RC" -ne 0 ] || ! grep -q '<svg' "$WORK/_probe.html" 2>/dev/null; then
    skp "[$label] all diagram tests" "renderer unavailable or probe failed"
    unset MDEXPORT_MERMAID
    return
  fi

  printf "\n${_b}[$label] diagrams${_0}\n"

  # flowchart + sequence render to inline SVG (both renderers support these)
  fixture fs.md '```mermaid
flowchart LR
  A-->B
```

```mermaid
sequenceDiagram
  Alice->>Bob: hi
```
'
  build fs.md --html
  assert_rc "$BUILD_RC" 0 "[$label] flowchart+sequence build"
  assert_count "$WORK/fs.html" '<svg' 2 "[$label] both diagrams -> inline SVG"
  assert_no_grep "$WORK/fs.html" 'class="mermaid"' "[$label] no raw mermaid fence leaks (HTML)"

  # multi-diagram id-collision: no cross-diagram duplicate ids
  fixture multi.md '```mermaid
flowchart LR
  A-->B
```

```mermaid
flowchart TD
  C-->D
```
'
  build multi.md --html
  local dups
  dups=$(grep -o 'id="[^"]*"' "$WORK/multi.html" | sort | uniq -d \
         | grep -vE 'id="m[0-9]+-(L_|edge[0-9]|flowchart-|Alice|Bob|id_)' | wc -l | tr -d ' ')
  [ "$dups" -eq 0 ] && ok "[$label] no cross-diagram duplicate ids (svg-scope)" \
                    || bad "[$label] no cross-diagram duplicate ids" "found $dups non-benign dup id(s)"

  # identical diagram twice -> two distinct per-occurrence prefixes
  fixture dup.md '```mermaid
flowchart LR
  A-->B
```

```mermaid
flowchart LR
  A-->B
```
'
  build dup.md --html
  local prefixes
  prefixes=$(grep -oE 'id="m[0-9]+-' "$WORK/dup.html" | grep -oE 'm[0-9]+-' | sort -u | wc -l | tr -d ' ')
  [ "$prefixes" -ge 2 ] && ok "[$label] identical diagrams get distinct per-occurrence prefixes" \
                        || bad "[$label] per-occurrence prefixes" "expected >=2 distinct, got $prefixes"

  # shell-quoting robustness: a '$' in the temp path must not break rendering
  local dollar="$WORK/wo\$rk"
  mkdir -p "$dollar"
  MDEXPORT_TMP="$dollar" "$MDEXPORT" "$WORK/_probe.md" --html >"$WORK/.log" 2>&1
  grep -q '<svg' "$WORK/_probe.html" \
    && ok "[$label] renders with \$ in temp path (shell-quoting)" \
    || bad "[$label] \$ in temp path" "$(tail -1 "$WORK/.log")"

  # failure isolation: a broken diagram -> placeholder, rest of doc still builds
  fixture bad.md '```mermaid
flowchart LR
  A-->B
```

```mermaid
flowchart LR
  A --> --> !!!broken
```

Tail prose.
'
  build bad.md --html
  assert_rc "$BUILD_RC" 0 "[$label] broken diagram does not abort the build (default)"
  assert_grep "$WORK/bad.html" '<div class="notmarkdown-render-error"' "[$label] broken diagram -> visible placeholder"
  assert_grep "$WORK/bad.html" 'Tail prose'               "[$label] rest of document survives"
  assert_count "$WORK/bad.html" '<svg' 1                  "[$label] the good diagram still rendered"

  # --strict turns any failure fatal
  build bad.md --html --strict
  assert_rc_nonzero "$BUILD_RC" "[$label] --strict aborts on a failed diagram"

  # clean doc -> no placeholder, no failure warning
  build fs.md --html
  assert_no_grep "$WORK/fs.html" '<div class="notmarkdown-render-error"' "[$label] clean doc has no placeholder"

  # no-leak: the belt-and-braces HTML sentinel never trips on good output
  assert_grep "$WORK/.log" 'self-contained, no raw mermaid' "[$label] no-leak sentinel passes on clean build"

  # PDF path (needs typst)
  if [ "$HAVE_TYPST" -eq 1 ]; then
    build fs.md --pdf
    assert_rc "$BUILD_RC" 0 "[$label] PDF builds"
    assert_file "$WORK/fs.pdf" "[$label] PDF file produced"
  else
    skp "[$label] PDF build" "typst not installed"
  fi

  unset MDEXPORT_MERMAID
}

# Default browser-free renderer (mermaidx wrapper) and the opt-in mmdc renderer.
renderer_tests "mermaidx" "$REPO/mermaid-render"
renderer_tests "mmdc"     "mmdc"

# mmdc-only guarantees: types mermaidx can't render, and the raster PDF path.
if MDEXPORT_MERMAID=mmdc "$MDEXPORT" "$WORK/_probe.md" --html >/dev/null 2>&1 \
   && grep -q '<svg' "$WORK/_probe.html"; then
  printf "\n${_b}[mmdc] full-fidelity guarantees${_0}\n"
  export MDEXPORT_MERMAID=mmdc
  fixture exotic.md '```mermaid
stateDiagram-v2
  [*] --> Idle
  Idle --> [*]
```

```mermaid
classDiagram
  Animal <|-- Dog
```

```mermaid
pie
  "a": 1
  "b": 2
```
'
  build exotic.md --html
  assert_rc "$BUILD_RC" 0 "[mmdc] state/class/pie build"
  assert_count "$WORK/exotic.html" '<svg' 3 "[mmdc] renders types mermaidx cannot (state/class/pie)"
  assert_no_grep "$WORK/exotic.html" '<div class="notmarkdown-render-error"' "[mmdc] no placeholders for exotic types"

  if [ "$HAVE_TYPST" -eq 1 ]; then
    build exotic.md --pdf
    assert_rc "$BUILD_RC" 0 "[mmdc] exotic-diagram PDF builds (raster path)"
    assert_file "$WORK/exotic.pdf" "[mmdc] PDF produced"
  fi
  unset MDEXPORT_MERMAID
else
  printf "\n"; skp "[mmdc] full-fidelity guarantees" "mmdc unavailable"
fi

# mermaidx-only: an unsupported type degrades to a placeholder (not an abort)
if "$REPO/mermaid-render" -i /dev/null -o "$WORK/.x.svg" >/dev/null 2>&1 || have mermaidx; then
  printf "\n${_b}[mermaidx] graceful degradation${_0}\n"
  export MDEXPORT_MERMAID="$REPO/mermaid-render"
  fixture pie.md '```mermaid
pie
  "a": 1
```
'
  build pie.md --html
  if [ "$BUILD_RC" -eq 0 ]; then
    assert_grep "$WORK/pie.html" '<div class="notmarkdown-render-error"' "[mermaidx] unsupported type -> placeholder, no abort"
  else
    skp "[mermaidx] unsupported-type placeholder" "mermaidx probe failed"
  fi
  unset MDEXPORT_MERMAID
fi

# ===========================================================================
printf "\n${_b}summary${_0}: ${_g}%d passed${_0}, ${_r}%d failed${_0}, ${_y}%d skipped${_0}\n" "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
