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

## Two of everything

Every choice here is a tradeoff, and the interesting ones have no right answer — only a
defensible one for a given set of constraints. So where a choice was genuinely contested,
there are two paths: a **default that leans boring and durable**, and an **opt-in that
spends durability on fidelity or coverage**. Choose per document; nothing is load-bearing
across the whole system, so you're free to disagree with a default one file at a time.

**Diagram renderer — small and browser-free, or complete and heavy.** The default,
`mermaidx`, runs Mermaid in an embedded JS engine: no headless Chrome (the single biggest
long-term-fragility source in this space), at the price of ~5 diagram types and the
occasional rough render. `MDEXPORT_MERMAID=mmdc` opts into the official mermaid-cli — every
diagram type, exactly as the web draws them — and with it a ~170 MB Chromium that is the
classic thing to break on an OS bump. Newer/smaller/80%-there versus
battle-tested/monolithic/complete. Neither is wrong.

```bash
MDEXPORT_MERMAID=mmdc mdexport FILE.md --all   # opt into full-fidelity diagrams
```

**PDF — a lean single binary, or a mirror of the HTML.** `--pdf` goes Markdown → Typst:
one small binary (no multi-GB TeX), fast, and able to emit archival **PDF/A** — but it
styles the page its own way, so the PDF is a close cousin of the HTML, not a twin.
`--pdf-from-html` prints the built HTML with a browser instead, so the PDF inherits the
HTML's typography exactly — at the cost of depending on that browser. Archival and
self-contained versus identical to what you see.

**And which format outlives which?** The HTML is the copy I'd bet on: self-contained, no
JavaScript, no network, system fonts — the plain text of twenty years ago, still rendering
the same everywhere. PDF has the longer lineage and the better odds of being readable and
printable in fifty years, precisely because the world is drowning in it. Keep the HTML to
read; keep the PDF to archive; keep both — they're cheap.

The defaults encode one bias — *take something modern and produce something boring and
durable, without much fuss* — and the opt-ins are there for the times that bias costs you
something you actually need.

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
mdexport notes.md --epub       # -> notes.epub (portable ebook, diagrams + math embedded)
mdexport notes.md --open       # build HTML and open it
mdexport notes.md --strict     # abort the build if any diagram fails (default: placeholder)
mdexport notes.md --follow     # also export every same-dir .md it links to (HTML, links rewritten)
mdexport notes.md --bundle     # --follow, then zip the set into notes.zip
mdexport notes.md --watch      # rebuild on every save (uses watchexec if present)
```

`--follow` exports a whole set of interlinked notes at once: it builds the input and
every same-directory `.md` it links to (transitively, cycles handled), HTML only, and
rewrites each `[x](other.md)` cross-link to `other.html` so the exported set stays
navigable. Links to other directories and to URLs are left untouched.

**Bundling a set into one file.** `--bundle` runs `--follow`, then zips exactly that
set (the reachable docs — not stray `.html` already in the directory) into `notes.zip`:
the most portable multi-document container there is — unzip anywhere, open the entry
page in any browser, and the rewritten links resolve offline. `--epub` instead packs a
single document into an EPUB — a valid, battle-tested ZIP of XHTML with diagrams and
math (MathML) embedded — for e-readers; it's reflowable, so it deliberately drops
`typography.html` and lets the reader own the layout.

`--pdf-from-html` needs a Chromium-family browser (Chrome/Chromium/Edge/Brave, or the
`chrome-headless-shell` that `mmdc` installs); set `MDEXPORT_CHROME` if it isn't
auto-found. See [Two of everything](#two-of-everything) for when to prefer it over `--pdf`.

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
