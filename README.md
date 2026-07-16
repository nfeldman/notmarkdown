# notmarkdown

**Markdown is for drafts. Markup is forever.**

`mdexport` publishes Markdown — Mermaid diagrams and LaTeX math included — as
self-contained HTML, PDF, PDF/A, or EPUB. One file, no JavaScript, no network, no
adjacent asset directory. The source stays ordinary Markdown; publishing is an
explicit step.

## Install

```bash
git clone https://github.com/nfeldman/notmarkdown
cd notmarkdown
./setup.sh
```

`setup.sh` installs Pandoc, Typst, and mermaidx, then symlinks `mdexport` into
`~/.local/bin`. It is idempotent, backs up anything it would overwrite, and warns
you if `~/.local/bin` is not on your `PATH`.

The manual equivalent:

```bash
brew install pandoc typst
uv tool install mermaidx        # or: pipx install mermaidx
mkdir -p ~/.local/bin
ln -s "$PWD/mdexport" ~/.local/bin/mdexport
```

`mdexport` resolves its own symlink back to the repository, so it finds the
filters and styles stored beside it.

## Usage

```bash
mdexport notes.md                  # notes.html (the default)
mdexport notes.md --pdf            # notes.pdf, via Typst
mdexport notes.md --pdfa           # archival PDF/A
mdexport notes.md --pdf-from-html  # PDF printed from the finished HTML
mdexport notes.md --epub           # notes.epub
mdexport notes.md --html           # HTML explicitly (combines with the above)
mdexport notes.md --all            # HTML + PDF
mdexport notes.md --open           # build HTML and open it
mdexport notes.md --strict         # fail if any diagram fails
mdexport notes.md --watch          # rebuild on save
mdexport notes.md --follow         # also export linked same-directory .md files
mdexport notes.md --bundle         # export the linked set, zipped
mdexport notes.md --out site/      # write outputs into site/

mdexport notes/                    # every notes/*.md  ->  sibling notes-html/
mdexport notes/ --epub             # every notes/*.md  ->  one combined notes.epub
```

## Output goes beside the input

| Input | Command | Output |
|---|---|---|
| `notes.md` | `mdexport notes.md` | `notes.html` |
| `notes/` | `mdexport notes/` | `notes-html/` |
| `notes/` | `mdexport notes/ --epub` | `notes.epub` |
| `notes/` | `mdexport notes/ --bundle` | `notes.zip` |

Formats that are one file per document (HTML, PDF) produce a sibling *directory*.
Single-artifact formats (EPUB, bundle ZIP) produce a sibling *file*, in the input
directory's parent. `--out DIR` redirects every output into `DIR` instead —
relocated, not duplicated. Directory input processes that directory's own
top-level `.md` files and does not recurse.

## Diagrams and math

Mermaid blocks render to SVG embedded directly in the HTML, with each diagram's
identifiers namespaced so multiple diagrams cannot collide. Math becomes MathML
in HTML and is typeset for PDF. Nothing is fetched when the document is read.

A diagram that fails to render becomes a visible, labelled placeholder holding its
original source, and the rest of the document still builds — a raw ```` ```mermaid ````
fence never reaches the finished document. `--strict` makes any diagram failure
abort the build instead.

### Renderer: mermaidx by default, mmdc when you need it

**mermaidx** is the default. It runs Mermaid without a browser and covers
flowcharts, sequence diagrams, ER diagrams, git graphs, and timelines. Other
types — state, class, pie, gantt, mindmap, journey — become placeholders.

For every Mermaid diagram type, install the official Mermaid CLI yourself and opt
in per run:

```bash
npm install -g @mermaid-js/mermaid-cli      # pulls ~170 MB of Chromium
MDEXPORT_MERMAID=mmdc mdexport notes.md --all
```

Nothing installs `mmdc` for you, and nothing fetches a browser behind your back.
When you do opt in, the filter feeds it per-format artifacts — inline SVG for
HTML, hi-DPI PNG for PDF — and batches the whole document in one pass.

| Renderer | Strength | Cost |
|---|---|---|
| `mermaidx` | Browser-free, few moving parts | Five diagram families |
| `mmdc` | Every Mermaid diagram type | ~170 MB Chromium |

## Two paths to PDF

```bash
mdexport notes.md --pdf            # Typst
mdexport notes.md --pdf-from-html  # browser print
```

| Path | Strength | Cost |
|---|---|---|
| Typst | Small toolchain, PDF/A support | Layout follows the HTML rather than matching it |
| Browser print | Closely matches the HTML | Needs a Chromium-family browser |

Typst is the default and the only path to PDF/A (`--pdfa`). The browser path
prints the finished HTML, so inline `code`, spacing, and typography carry over as
you see them. Set `MDEXPORT_CHROME=/path/to/chrome` when the browser is not found
automatically.

## Linked sets

`--follow` exports the input plus every same-directory Markdown file reachable
from it through links:

```bash
mdexport index.md --follow
mdexport index.md --bundle   # the same set, zipped as index.zip
```

`[x](other.md)` becomes `[x](other.html)`. Traversal is transitive, cycles are
handled, and links to URLs or to other directories are left alone. Only reachable
files are exported, so the ZIP holds exactly that set rather than every HTML file
in the directory. Unpack it anywhere and the links still work offline.

Use `--bundle` for a set of linked documents and `--epub` for one reflowable
document. EPUB does not use `typography.html`: the reader controls type size,
margins, and pagination.

## Drag-and-drop app (macOS)

```bash
./make-droplet          # -> ~/Desktop/notmarkdown.app
```

Drop Markdown files or folders onto the icon. It asks which format — HTML, PDF,
PDF matching the HTML, EPUB, or HTML + PDF — and applies it to everything
dropped. It is compiled from `droplet.applescript` with `osacompile`, so edit the
source and rebuild rather than hand-assembling an app; it calls the same
`mdexport` on your `PATH`. On first launch, right-click → *Open* to clear
Gatekeeper.

## From an AI assistant

The Claude Code skill at `.claude/skills/publish/SKILL.md` makes publishing an
explicit action, under one rule:

> Never publish a draft automatically. Publish when asked; otherwise, offer.

Install it globally:

```bash
mkdir -p ~/.claude/skills
ln -s "$PWD/.claude/skills/publish" ~/.claude/skills/publish
```

For shell-capable agents the skill and the CLI are enough; an MCP server would
only wrap the same command.

## Requirements

Pandoc, Typst, Python 3, and mermaidx. Optionally: Mermaid CLI for full diagram
coverage, and a Chromium-family browser for `--pdf-from-html`.

The scripts lean macOS: `--open` uses `open`, and the watch fallback uses BSD
`stat -f %m`. On Linux the equivalents are `xdg-open` and `stat -c %Y`. `--watch`
uses `watchexec` when it is installed and polls once a second otherwise.

## Files

| File | Role |
|---|---|
| `mdexport` | The CLI: conversion, output formats, linked export, watching. |
| `mermaid.lua` | Pandoc filter — finds, dedupes, batches, and renders Mermaid blocks; isolates failures as placeholders. |
| `mermaid-render` | Default Mermaid→SVG adapter using mermaidx. |
| `svg-scope` | Namespaces identifiers inside each embedded SVG so diagrams cannot collide. |
| `mdlinks.lua` | `--follow` link rewriting and discovery. |
| `typography.html` | Self-contained HTML styling: readable measure, print rules, dark mode, math-font fallbacks. |
| `make-droplet`, `droplet.applescript` | The macOS drag-and-drop app. |
| `.claude/skills/publish` | The Claude Code publishing skill. |

## Uninstall

```bash
rm ~/.local/bin/mdexport

uv tool uninstall mermaidx                  # or: pipx uninstall mermaidx
brew uninstall pandoc typst
npm uninstall -g @mermaid-js/mermaid-cli    # if installed only for this
```

## License

MIT
