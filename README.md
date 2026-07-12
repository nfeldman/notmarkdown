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
Markdown ─▶ pandoc ─▶ mermaid.lua ─┬─ HTML ─▶ mmdc ─▶ inline SVG   ── self-contained .html (no JS)
                                   └─ PDF  ─▶ mmdc ─▶ hi-DPI PNG ─▶ Typst ─▶ PDF / PDF-A
                    (prose · tables · math: MathML in HTML, native Typst in PDF)
```

- **pandoc** — the durable universal converter; Markdown stays your source of truth.
  Its typed AST is the segment-and-reassemble engine: `mermaid.lua` rewrites only the
  diagram blocks; everything else flows straight to the two writers.
- **Typst** — lean single-binary PDF engine (no multi-GB TeX). Renders LaTeX-style
  math, bundles good math fonts, and emits archival **PDF/A**. ~30× faster than XeLaTeX.
- **MathML** for HTML math — a W3C standard that renders natively in every 2026
  browser with **no JavaScript** and no network. 100× smaller than a KaTeX/MathJax
  bundle and won't rot when a pinned JS lib does. `typography.html` names STIX Two Math
  (present on macOS) so Chromium — which ships no math font — renders it too.
- **mmdc** (official mermaid-cli) as the default diagram renderer — the only renderer
  that covers *every* Mermaid diagram type at full fidelity. Each block is rendered in
  its authoritative engine and each output format gets the artifact it renders
  correctly: **inline SVG for HTML** (a unique `--svgId` per diagram keeps multiple
  diagrams from colliding) and a **high-DPI PNG for the PDF** (Typst's SVG engine
  silently drops `<foreignObject>` labels, so we embed browser pixels it can't mangle).

### The one honest tradeoff

Full fidelity means **headless Chrome** (`mmdc`) by default: a ~170 MB Chromium
download that is the classic thing to break on an OS/toolchain bump — the one place
this tool trades durability for correctness, because it is the only renderer that
handles every diagram type. It is quarantined to the diagram-render step.

**Prefer no Chrome?** Opt into the browser-free **mermaidx** wrapper — it runs the
real Mermaid v11 JS in an embedded engine (no Puppeteer) but is SVG-only and covers
~5 diagram types (flowchart, sequence, ER, gitGraph, timeline); other types fall back
to a placeholder. No code change:

```bash
MDEXPORT_MERMAID="$PWD/mermaid-render" mdexport FILE.md --all
```

Because a failed diagram is now isolated (not fatal), mixing supported and
unsupported types under the mermaidx path degrades gracefully rather than aborting.

## Files

| File | Role |
|------|------|
| `mdexport` | The CLI. Orchestrates pandoc → HTML/PDF, runs the no-leak check. `--strict` for all-or-nothing. |
| `mermaid.lua` | Pandoc filter: renders each ` ```mermaid ` block per output format (inline SVG for HTML, hi-DPI PNG for PDF); isolates a failed diagram to a visible placeholder. |
| `mermaid-render` | Opt-in browser-free Mermaid→SVG (mermaidx + z-order/viewBox fixups). Select via `MDEXPORT_MERMAID`. |
| `typography.html` | Self-contained CSS: book-serif body, good measure/rhythm, math font, dark-mode aware. No web fonts. |

## Usage

```bash
mdexport notes.md              # -> notes.html (self-contained)
mdexport notes.md --pdf        # -> notes.pdf  (via Typst)
mdexport notes.md --all        # both
mdexport notes.md --pdfa       # -> notes.pdf as PDF/A-2b (archival, fonts embedded)
mdexport notes.md --open       # build HTML and open it
mdexport notes.md --strict     # abort the build if any diagram fails (default: placeholder)
mdexport notes.md --watch      # rebuild on every save (uses watchexec if present)
```

## Requirements

- **pandoc** and **typst** — `brew install pandoc typst`
- **mmdc** (default diagram renderer) — `npm i -g @mermaid-js/mermaid-cli`; first run
  fetches `chrome-headless-shell` (~170 MB, one-time)
- **mermaidx** (optional — only for the browser-free `MDEXPORT_MERMAID` path) —
  `uv tool install mermaidx` (or `pipx install mermaidx`); `python3` drives its SVG fixups
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
npm i -g @mermaid-js/mermaid-cli    # default diagram renderer (mmdc)
uv tool install mermaidx            # optional: browser-free path (or: pipx install mermaidx)
mkdir -p ~/.local/bin
ln -s "$PWD/mdexport" ~/.local/bin/mdexport   # mdexport resolves this back to the repo for its assets
```

**Uninstall (the exit is one symlink):**

```bash
rm ~/.local/bin/mdexport
uv tool uninstall mermaidx          # or: pipx uninstall mermaidx
brew uninstall pandoc typst
```
