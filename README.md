# notmarkdown — Markdown → durable documents, with Mermaid and math included

`notmarkdown` publishes Markdown containing Mermaid diagrams and LaTeX-style math
as self-contained HTML, PDF, PDF/A, or EPUB.

It uses a small set of open tools, with defaults chosen for durability and explicit
opt-ins for cases where fidelity or coverage matters more.

## What you get

| Need | Use |
|---|---|
| Preview Mermaid while editing | Zed’s built-in Markdown preview |
| View math and diagrams together | `mdexport FILE.md --open` |
| Create self-contained HTML | `mdexport FILE.md` |
| Create PDF or PDF/A | `mdexport FILE.md --pdf` or `--pdfa` |
| Match the HTML closely in PDF | `mdexport FILE.md --pdf-from-html` |
| Publish linked Markdown files together | `mdexport FILE.md --follow` or `--bundle` |
| Create a portable ebook | `mdexport FILE.md --epub` |

The source remains ordinary Markdown. Publishing is a separate, explicit step.

## Predictable failure behavior

A failed diagram should not corrupt an otherwise useful document.

By default, each Mermaid block is rendered independently. If one cannot be rendered,
the output contains a visible, labelled placeholder with the original Mermaid source.
It never exposes a raw ```` ```mermaid ```` fence in the finished document.

Use `--strict` when partial output is not acceptable:

```bash
mdexport FILE.md --strict
```

In strict mode, any diagram failure aborts the build.

Equations are written as MathML in HTML and typeset for PDF. If Pandoc cannot parse a
piece of LaTeX, it reports a warning on standard error. That is treated as a source
problem to review rather than silently hidden.

## How it works

```text
Markdown
    │
    ▼
  pandoc ── mermaid.lua
    │
    ├── Mermaid ── mermaidx ── inline SVG
    │             or
    │             mmdc ─────── inline SVG / high-resolution PNG
    │
    ├── HTML5 + MathML + inline SVG
    │       └── self-contained HTML, with no JavaScript or network dependency
    │
    └── Typst
            └── PDF or PDF/A, with fonts embedded

Alternative PDF path:

self-contained HTML ── Chromium-family browser ── PDF
```

The main components are deliberately conventional:

- **Pandoc** parses the document into a typed syntax tree and writes the output
  formats. The Mermaid filter handles diagram blocks; the rest of the document
  continues through Pandoc normally.
- **Typst** provides the default PDF path without requiring a full TeX installation.
  It is used for both ordinary PDF and archival PDF/A output.
- **MathML** keeps HTML equations self-contained and avoids shipping a JavaScript
  math renderer with every document.
- **Mermaid SVG** is embedded directly into HTML. Each diagram’s identifiers are
  namespaced so multiple SVGs cannot interfere with one another.
- **Mermaidx** provides the default browser-free diagram path.
- **Mermaid CLI (`mmdc`)** provides the broader-coverage path when carrying a browser
  dependency is justified.

## Two deliberate approaches

Some engineering choices do not have one correct answer. They have different correct
answers for different constraints.

`notmarkdown` therefore provides a conservative default and an explicit alternative
where the tradeoff is meaningful.

### Diagram rendering: small dependency or broad coverage

The default renderer is `mermaidx`. It runs Mermaid without launching a headless
browser and produces SVG directly.

Its current coverage includes the common diagram families used by this project, such
as flowcharts, sequence diagrams, entity-relationship diagrams, git graphs, and
timelines. Unsupported diagrams become labelled placeholders unless `--strict` is
enabled.

For Mermaid’s full renderer and wider diagram coverage, use `mmdc`:

```bash
MDEXPORT_MERMAID=mmdc mdexport FILE.md --all
```

That path uses the official Mermaid CLI and its Chromium runtime.

The tradeoff is direct:

| Renderer | Strength | Cost |
|---|---|---|
| `mermaidx` | Small, browser-free, fewer moving parts | More limited diagram coverage |
| `mmdc` | Broad coverage and web-renderer fidelity | Chromium dependency and a larger installation |

Neither is a degraded version of the other. They serve different priorities.

### PDF rendering: archival independence or visual equivalence

The default PDF path sends the document through Typst:

```bash
mdexport FILE.md --pdf
```

This produces a self-contained PDF using a dedicated document engine. It can also
produce PDF/A:

```bash
mdexport FILE.md --pdfa
```

The resulting PDF follows the same overall design as the HTML, but it is not intended
to be a pixel-identical copy. HTML and paged documents have different layout models.

For a PDF that closely follows the HTML presentation, print the completed HTML through
a browser:

```bash
mdexport FILE.md --pdf-from-html
```

That preserves the HTML typography and layout more directly, at the cost of making a
Chromium-family browser part of the publishing path.

| PDF path | Strength | Cost |
|---|---|---|
| Typst | Dedicated PDF engine, small toolchain, PDF/A support | Layout is related to the HTML rather than identical |
| Browser print | Closely matches the HTML presentation | Browser dependency |

### Why provide both?

AI-assisted development lowered the cost of implementing and refining alternatives.
That saved effort can be used in three ways:

- build a prototype and discard it—the Fred Brooks “plan to throw one away” case;
- spend the same time making one implementation substantially stronger;
- when the needs are distinct and the maintenance cost remains reasonable, build both.

This project takes the third approach. The model accelerated implementation and routine
checking; the constraints, defaults, tradeoffs, and acceptance criteria remained human
decisions.

The same principle applies beyond a small publishing tool: faster implementation can
mean more output, but it can also mean better judgment applied to more of the design
space.

## Output formats

### Self-contained HTML

The default output is one `.html` file containing its styles, MathML, and diagrams.

```bash
mdexport notes.md
```

It requires no JavaScript, network connection, or adjacent asset directory.

```bash
mdexport notes.md --open
```

builds the HTML and opens it in the default browser.

### PDF and PDF/A

```bash
mdexport notes.md --pdf
mdexport notes.md --pdfa
mdexport notes.md --pdf-from-html
```

Use the Typst path for a dedicated, self-contained PDF pipeline. Use the browser path
when matching the HTML presentation is more important.

Keeping both HTML and PDF is inexpensive: HTML is convenient for reading and linking;
PDF remains useful for exchange, printing, and archival workflows.

### EPUB

```bash
mdexport notes.md --epub
```

EPUB packages one document as reflowable XHTML with its diagrams and math embedded.

Because an ebook reader controls page size, type size, margins, and pagination, EPUB
does not use `typography.html`. That is intentional rather than a loss of fidelity.

## Files

| File | Role |
|---|---|
| `mdexport` | Main CLI. Coordinates conversion, output formats, validation, linked-document export, and watching. |
| `mermaid.lua` | Pandoc filter that finds, deduplicates, batches, and renders Mermaid blocks. It also isolates failures as placeholders. |
| `mermaid-render` | Default Mermaid-to-SVG adapter using `mermaidx`, with SVG view-box and ordering corrections. |
| `svg-scope` | Namespaces identifiers inside each embedded SVG so diagrams cannot collide in one HTML document. |
| `mdlinks.lua` | Used by `--follow` to rewrite same-directory Markdown links and record linked files for export. |
| `typography.html` | Self-contained HTML styling, including readable measure, print rules, dark-mode handling, and math-font fallbacks. |
| `droplet.applescript`, `make-droplet` | Source and builder for an optional macOS drag-and-drop app (see below). |
| `.claude/skills/publish` | Optional Claude Code skill that exposes publishing as an explicit action. |

## Usage

```bash
mdexport notes.md                  # notes.html
mdexport notes.md --pdf            # notes.pdf through Typst
mdexport notes.md --all            # HTML and PDF
mdexport notes.md --pdfa           # archival PDF/A
mdexport notes.md --pdf-from-html  # PDF printed from the completed HTML
mdexport notes.md --epub           # notes.epub
mdexport notes.md --out site/      # write outputs into site/ instead of alongside
mdexport notes.md --open           # build HTML and open it
mdexport notes.md --strict         # fail if any diagram cannot be rendered
mdexport notes.md --follow         # export linked same-directory Markdown files
mdexport notes.md --bundle         # export the linked set and create a ZIP
mdexport notes.md --watch          # rebuild after each save

mdexport notes/                    # every notes/*.md  ->  sibling notes-html/
mdexport notes/ --epub             # every notes/*.md  ->  one combined notes.epub
```

## Publishing a linked set

`--follow` exports the input document and every same-directory Markdown file reachable
from it through Markdown links.

```bash
mdexport index.md --follow
```

For the exported HTML set:

- `[x](other.md)` becomes `[x](other.html)`;
- traversal is transitive;
- cycles are handled;
- links to URLs and files in other directories are left unchanged;
- only reachable files are exported.

This allows a directory of interlinked Markdown notes to remain navigable after export.

### Bundling the set

```bash
mdexport index.md --bundle
```

`--bundle` performs the linked export and then creates `index.zip`.

The archive contains exactly the reachable exported set, rather than every existing
HTML file in the directory. It can be unpacked anywhere and opened locally; rewritten
links continue to work without a network connection.

Use `--bundle` for a collection of linked documents. Use `--epub` for one reflowable
document.

## Processing a directory

An input may be a directory instead of a single file. Every top-level `.md` in it is
processed (not only the files reachable through links), and the output is written as a
**sibling of the input directory**:

```bash
mdexport notes/          # -> notes-html/  (a sibling directory of HTML)
mdexport notes/ --pdf    # -> notes-pdf/   (a sibling directory of PDFs)
mdexport notes/ --epub   # -> notes.epub   (one combined ebook, beside the directory)
mdexport notes/ --bundle # -> notes.zip    (the HTML set as one archive, beside it)
```

The shape follows the format. Formats that are inherently one-file-per-document (HTML,
PDF) produce a sibling *directory*; formats that are a single artifact (EPUB, a bundle
ZIP) produce a sibling *file*, sharing the input directory's parent. For the HTML
directory, same-directory `[x](other.md)` links are rewritten to `other.html`, so the
exported folder is navigable, and the source directory is left untouched. Recursion is
intentionally not performed — only the directory's own top-level files.

## Output location

By default each output is written next to its source. `--out DIR` redirects every
output into `DIR` (created if missing) instead; the output is relocated, not duplicated.
It composes with the above, so a directory of linked notes can be published elsewhere in
one step:

```bash
mdexport notes/ --out /tmp/site      # every notes/*.md -> /tmp/site/*.html
mdexport index.md --follow --out site/   # a linked set, published into site/
```

## Drag-and-drop app (macOS)

Because every input produces a sibling output, no configuration is needed to publish by
dropping. `make-droplet` compiles a small AppleScript into an app you can drop Markdown
files or folders onto:

```bash
./make-droplet                 # -> ~/Applications/notmarkdown.app
```

On a drop it asks which format to produce — HTML, PDF, EPUB, or both — and applies it to
everything dropped: a file becomes a sibling file, a folder a sibling folder (or one
combined ebook). The app is built from `droplet.applescript` with `osacompile`, so it is
version-controlled and rebuildable rather than assembled by hand — edit the source and run
`make-droplet` again. It calls the same `mdexport` on your `PATH`, so it stays in step with
the CLI. (On first launch, right-click the app and choose *Open* to clear Gatekeeper.)

## Requirements

### Required

- **Pandoc**
- **Typst**
- **Python 3**
- **Mermaidx**

On macOS:

```bash
brew install pandoc typst
uv tool install mermaidx
```

`pipx` may be used instead of `uv`:

```bash
pipx install mermaidx
```

### Optional

For the full-coverage Mermaid path:

```bash
npm install -g @mermaid-js/mermaid-cli
```

For `--pdf-from-html`, install a Chromium-family browser such as Chrome, Chromium,
Edge, Brave, or the headless Chromium runtime provided with Mermaid CLI.

Set an explicit browser path when automatic discovery is not sufficient:

```bash
MDEXPORT_CHROME=/path/to/chrome mdexport notes.md --pdf-from-html
```

### Platform notes

The supplied scripts are currently oriented toward macOS:

- `--open` uses `open`;
- the built-in watch fallback uses BSD `stat -f %m`.

On Linux, the equivalent commands are generally:

- `xdg-open`;
- `stat -c %Y`.

`--watch` uses `watchexec` when it is available.

## Install

Clone the repository and run the setup script:

```bash
git clone <this-repo> notmarkdown
cd notmarkdown
./setup.sh
```

`setup.sh` is idempotent and safe to run again.

It:

1. installs Pandoc and Typst through Homebrew when missing;
2. installs `mermaidx` through `uv` or `pipx`;
3. creates a symlink to `mdexport` in `~/.local/bin`;
4. backs up an existing file at that path rather than overwriting it;
5. checks whether `~/.local/bin` is on `PATH`.

After installation:

```bash
mdexport notes.md
```

### Manual installation

```bash
brew install pandoc typst
uv tool install mermaidx

# Optional full-coverage Mermaid renderer
npm install -g @mermaid-js/mermaid-cli

mkdir -p ~/.local/bin
ln -s "$PWD/mdexport" ~/.local/bin/mdexport
```

`mdexport` resolves its symlink back to the repository so it can locate the filters,
styles, and helper scripts stored with it.

## Uninstall

Remove the CLI symlink:

```bash
rm ~/.local/bin/mdexport
```

Remove installed dependencies when they are no longer used elsewhere:

```bash
uv tool uninstall mermaidx
# or:
pipx uninstall mermaidx

brew uninstall pandoc typst
```

If Mermaid CLI was installed only for this project:

```bash
npm uninstall -g @mermaid-js/mermaid-cli
```

## Using it from an AI assistant

Markdown is the working format. `mdexport` is the publishing step.

The included Claude Code skill is located at:

```text
.claude/skills/publish/SKILL.md
```

It follows one primary rule:

> Never publish a draft automatically. Publish when asked; otherwise, offer.

Install the skill globally by symlinking it:

```bash
mkdir -p ~/.claude/skills
ln -s "$PWD/.claude/skills/publish" ~/.claude/skills/publish
```

For shell-capable agents such as Claude Code, the skill and CLI are sufficient. An MCP
server would add little beyond wrapping the same command.

An MCP wrapper may still be useful for clients that cannot execute shell commands. Its
interface can remain small:

```text
publish_markdown
    input: Markdown text or a file path
    format: html, pdf, pdfa, epub, or all
    output: the completed artifact
```

Its tool description should preserve the same publication rule: publishing is an
explicit action, not an automatic consequence of generating Markdown.
