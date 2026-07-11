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

The export guarantees **no raw diagram leaks** in either format: `mermaid.lua` aborts
the whole conversion (non-zero exit) if any diagram fails to render, so a raw
` ```mermaid ` fence can never reach the HTML or the PDF. Equations become MathML
(HTML) or typeset math (PDF); LaTeX that pandoc itself can't parse is passed through
with a pandoc **warning on stderr** — that's a source error to fix, so watch the build
output.

## The pipeline (why these tools)

```
Markdown ─▶ pandoc ─┬─▶ (mermaid.lua ─▶ mermaid-render ─▶ inline SVG)
                    ├─▶ HTML5 + MathML + inline SVG   ── self-contained .html (no JS, ~15 KB)
                    └─▶ Typst ─▶ PDF / PDF-A           ── archival, fonts embedded
```

- **pandoc** — the durable universal converter; Markdown stays your source of truth.
- **Typst** — lean single-binary PDF engine (no multi-GB TeX). Renders LaTeX-style
  math, bundles good math fonts, and emits archival **PDF/A**. ~30× faster than XeLaTeX.
- **MathML** for HTML math — a W3C standard that renders natively in every 2026
  browser with **no JavaScript** and no network. 100× smaller than a KaTeX/MathJax
  bundle and won't rot when a pinned JS lib does. `typography.html` names STIX Two Math
  (present on macOS) so Chromium — which ships no math font — renders it too.
- **mermaidx** (browser-free) as the default Mermaid renderer, via `mermaid-render`,
  which runs the real Mermaid v11 JS in an embedded engine — **no headless Chrome**,
  the single biggest long-term-fragility source here. `mermaid-render` also patches two
  quirks in mermaidx's output (labels hidden behind node fills; wide diagrams clipped).

### The one honest tradeoff

Mermaid is fundamentally a browser renderer, so a truly faithful renderer means
**headless Chrome** (`mmdc`), which needs a ~170 MB Chromium download and is the
classic thing that breaks on an OS/toolchain bump — against the durability ethos.
`mermaidx` avoids Chrome entirely but is younger and needs the two output fixups in
`mermaid-render` (tested on flowcharts; exotic diagram types may render imperfectly).

**Default: mermaidx (browser-free).** If you hit a diagram it renders wrong, install
the official renderer and set the env var — no code change:

```bash
npx puppeteer browsers install chrome-headless-shell   # one-time ~170 MB
MDEXPORT_MERMAID=mmdc mdexport FILE.md --all
```

`mermaid-render`'s fixups are keyed to mermaidx's internal SVG class names, tested
against flowcharts. **When you upgrade mermaidx, re-run `mdexport` on a known
flowchart and eyeball it** — the script warns on stderr if it can no longer find the
structures it patches, but a visual check is the real guard.

## Files

| File | Role |
|------|------|
| `mdexport` | The CLI. Orchestrates pandoc → HTML/PDF, runs the no-leak check. |
| `mermaid.lua` | Pandoc filter: turns ` ```mermaid ` blocks into SVG (inline in HTML, embedded in PDF). |
| `mermaid-render` | Browser-free Mermaid→SVG (mermaidx + z-order/viewBox fixups). Swap for `mmdc` via env. |
| `typography.html` | Self-contained CSS: book-serif body, good measure/rhythm, math font, dark-mode aware. No web fonts. |

## Usage

```bash
mdexport notes.md              # -> notes.html (self-contained)
mdexport notes.md --pdf        # -> notes.pdf  (via Typst)
mdexport notes.md --all        # both
mdexport notes.md --pdfa       # -> notes.pdf as PDF/A-2b (archival, fonts embedded)
mdexport notes.md --open       # build HTML and open it
mdexport notes.md --watch      # rebuild on every save (uses watchexec if present)
```

## Requirements

- **pandoc** and **typst** — `brew install pandoc typst`
- **mermaidx** — browser-free Mermaid renderer — `uv tool install mermaidx` (or `pipx install mermaidx`)
- **bash** and **python3** — `python3` drives `mermaid-render`'s SVG fixups
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

<details><summary>Or do it by hand</summary>

```bash
brew install pandoc typst
uv tool install mermaidx            # or: pipx install mermaidx
mkdir -p ~/.local/bin
ln -s "$PWD/mdexport" ~/.local/bin/mdexport   # mdexport resolves this back to the repo for its assets
```
</details>

**Uninstall (the exit is one symlink):**

```bash
rm ~/.local/bin/mdexport
uv tool uninstall mermaidx          # or: pipx uninstall mermaidx
brew uninstall pandoc typst
```
