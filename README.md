# notmarkdown — Markdown → durable docs, with Mermaid + LaTeX baked in

LLMs emit Markdown full of Mermaid diagrams and `$…$` LaTeX. Zed's preview renders
Mermaid but **not** math; Claude Code's terminal renders neither. This toolkit
closes the gap two ways, favoring **few, open, durable tools** over a big stack.

## What you get

| Need | Answer |
|------|--------|
| **View** diagrams while editing | Zed's built-in Markdown preview already renders Mermaid natively (2026). Keep using it. |
| **View** math + diagrams together | `mdexport FILE.md --open` → a self-contained HTML page. |
| **Durable export** (everything baked in) | `mdexport` → self-contained HTML *and/or* PDF / PDF-A. |

The export guarantees **no raw diagram leaks** in either format: a diagram that
fails to render becomes a visible, labelled placeholder (the original source in an
error box), never a raw ` ```mermaid ` fence — so one bad block no longer destroys the
whole document. Pass `--strict` to restore all-or-nothing (any failure aborts the
build). Equations become MathML (HTML) or typeset math (PDF); LaTeX that pandoc itself
can't parse is passed through with a pandoc **warning on stderr** — that's a source
error to fix, so watch the build output.

## The pipeline (why these tools)

```
                            default: mermaidx (browser-free) ─▶ inline SVG (both formats)
Markdown ─▶ pandoc ─▶ mermaid.lua ─┤
                            opt-in:  mmdc (headless Chrome) ─┬─ HTML ─▶ inline SVG
                                                             └─ PDF  ─▶ hi-DPI PNG
   ├─ HTML5 + MathML + inline SVG        ── self-contained .html (no JS)
   └─ Typst ─▶ PDF / PDF-A               ── archival, fonts embedded
```

- **pandoc** — the durable universal converter; Markdown stays your source of truth.
  Its typed AST is the segment-and-reassemble engine: `mermaid.lua` collects and
  batches only the diagram blocks; everything else flows straight to the two writers.
- **Typst** — lean single-binary PDF engine (no multi-GB TeX). Renders LaTeX-style
  math, bundles good math fonts, and emits archival **PDF/A**. ~30× faster than XeLaTeX.
- **MathML** for HTML math — a W3C standard that renders natively in every 2026
  browser with **no JavaScript** and no network. 100× smaller than a KaTeX/MathJax
  bundle and won't rot when a pinned JS lib does. `typography.html` names STIX Two Math
  (present on macOS) so Chromium — which ships no math font — renders it too.
- **mermaidx** (browser-free) is the **default** diagram renderer — it runs the real
  Mermaid v11 JS in an embedded engine with **no headless Chrome**, the single biggest
  long-term-fragility source here. It is SVG-only and covers ~5 diagram types
  (flowchart, sequence, ER, gitGraph, timeline); any other type falls back to a visible
  placeholder instead of aborting the build. Inline SVGs are id-namespaced (`svg-scope`)
  so multiple diagrams never collide in one document.

### The one honest tradeoff

Full fidelity across *every* diagram type means **headless Chrome** (`mmdc`, the
official mermaid-cli) — a ~170 MB Chromium download that is the classic thing to break
on an OS/toolchain bump. So it is **opt-in**, not the default. When you do opt in, the
filter renders the whole document in one batched launch and feeds each output format
the artifact it displays correctly: inline SVG for HTML, and a **high-DPI PNG for the
PDF** (Typst's SVG engine silently drops mmdc's `<foreignObject>` labels, so we embed
browser pixels it can't mangle). One env var, no code change:

```bash
MDEXPORT_MERMAID=mmdc mdexport FILE.md --all
```

Because a failed diagram is now isolated (not fatal), mixing supported and
unsupported types under the mermaidx path degrades gracefully rather than aborting.

## Files

| File | Role |
|------|------|
| `mdexport` | The CLI. Orchestrates pandoc → HTML/PDF, runs the no-leak check. `--strict` for all-or-nothing. |
| `mermaid.lua` | Pandoc filter: collects, de-duplicates and batches every ` ```mermaid ` block, renders it per output format (inline SVG for HTML, hi-DPI PNG for the mmdc PDF path), and isolates a failed diagram to a visible placeholder. |
| `mermaid-render` | The default browser-free Mermaid→SVG renderer (mermaidx + z-order/viewBox fixups). |
| `svg-scope` | Namespaces every id in an inline SVG (per diagram occurrence) so multiple diagrams don't collide in one HTML document. |
| `mdlinks.lua` | `--follow` only: an AST filter that rewrites same-dir `X.md` links to `X.html` and records them to follow (a no-op on ordinary builds). |
| `typography.html` | Self-contained CSS: book-serif body, good measure/rhythm, math font, dark-mode aware. No web fonts. |

## Usage

```bash
mdexport notes.md              # -> notes.html (self-contained)
mdexport notes.md --pdf        # -> notes.pdf  (via Typst)
mdexport notes.md --all        # both
mdexport notes.md --pdfa       # -> notes.pdf as PDF/A-2b (archival, fonts embedded)
mdexport notes.md --pdf-from-html  # -> notes.pdf by printing the HTML (browser, high fidelity)
mdexport notes.md --open       # build HTML and open it
mdexport notes.md --strict     # abort the build if any diagram fails (default: placeholder)
mdexport notes.md --follow     # also export every same-dir .md it links to (HTML, links rewritten)
mdexport notes.md --watch      # rebuild on every save (uses watchexec if present)
```

`--follow` exports a whole set of interlinked notes at once: it builds the input and
every same-directory `.md` it links to (transitively, cycles handled), HTML only, and
rewrites each `[x](other.md)` cross-link to `other.html` so the exported set stays
navigable. Links to other directories and to URLs are left untouched.

**Two PDF paths.** `--pdf` (and `--pdfa`) go Markdown → Typst: fast, dependency-light,
archival, but the PDF uses Typst's own styling, so it doesn't match the HTML exactly.
`--pdf-from-html` instead prints the *built HTML* with a headless browser, so the PDF
inherits `typography.html` verbatim — code pills, measure, fonts, spacing all identical
to what you see in the browser. It needs a Chromium-family browser (Chrome/Chromium/
Edge/Brave, or the `chrome-headless-shell` that `mmdc` installs); point `MDEXPORT_CHROME`
at one if it isn't auto-found. Prefer `--pdf-from-html` when you want the PDF to look
like the HTML; keep `--pdf`/`--pdfa` for archival/offline builds.

## Requirements

- **pandoc** and **typst** — `brew install pandoc typst`
- **mermaidx** (default diagram renderer, browser-free) — `uv tool install mermaidx`
  (or `pipx install mermaidx`)
- **python3** — drives `mermaid-render`'s SVG fixups and `svg-scope`'s id-namespacing
- **mmdc** (optional — full-fidelity `MDEXPORT_MERMAID=mmdc` path) —
  `npm i -g @mermaid-js/mermaid-cli`; first run fetches `chrome-headless-shell` (~170 MB)
- macOS-oriented: `--open` uses `open`, and the `--watch` fallback uses BSD `stat -f %m`.
  On Linux, swap those two lines (`xdg-open`, `stat -c %Y`).

## Install

One step:

```bash
git clone <this-repo> notmarkdown && cd notmarkdown
./setup.sh
```

`setup.sh` is idempotent (safe to re-run). It installs `pandoc` + `typst` via
Homebrew and `mermaidx` via uv/pipx if missing, then symlinks `mdexport` into
`~/.local/bin` (backing up anything already there) and checks it's on your PATH.
Then: `mdexport notes.md`.

**Or do it by hand:**

```bash
brew install pandoc typst
uv tool install mermaidx            # default diagram renderer (or: pipx install mermaidx)
npm i -g @mermaid-js/mermaid-cli    # optional: MDEXPORT_MERMAID=mmdc full-fidelity path
mkdir -p ~/.local/bin
ln -s "$PWD/mdexport" ~/.local/bin/mdexport   # mdexport resolves this back to the repo for its assets
```

**Uninstall (the exit is one symlink):**

```bash
rm ~/.local/bin/mdexport
uv tool uninstall mermaidx          # or: pipx uninstall mermaidx
brew uninstall pandoc typst
```
