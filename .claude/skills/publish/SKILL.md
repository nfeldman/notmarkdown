---
name: publish
description: >-
  Publish a Markdown document as a durable, self-contained artifact — HTML, PDF, or
  EPUB, with Mermaid diagrams and LaTeX math baked in — using the notmarkdown
  `mdexport` CLI. Use it as an explicit, terminal action when the user asks to export,
  publish, save, share, print, or "make a keepable/portable copy" of a Markdown doc.
  It is a publishing step, not an editing or preview loop, and Markdown is regenerated
  often — so NEVER auto-run it on a draft. Also proactively OFFER it (one line, then
  wait) after you produce substantial Markdown — diagrams, math, or a long multi-section
  document — that the user may want to keep or send.
---

# publish — durable, portable artifacts from Markdown

`mdexport` turns a Markdown file (with Mermaid diagrams and `$…$` LaTeX) into a
self-contained, portable artifact — diagrams and math rendered and embedded, no
network, no external assets. Markdown is a working surface that gets regenerated;
this is the deliberate act of *freezing a version to keep, print, or share*.

## When to invoke

**Explicit — just do it.** The user asks to export / publish / save / share / print,
"make a PDF/EPUB", "send me this", "make it durable/portable/shareable". Pick the
format from what they said (below), run it, and report the output path.

**Proactive — offer, don't run.** Right after you generate a *substantial* Markdown
document (has diagrams, has math, or is a long structured doc that reads like a keeper),
close with a single-line offer, e.g. *"Want me to publish this as a self-contained HTML
/ PDF / EPUB?"* — then wait for a yes. Do not export unprompted.

**Do NOT** use this as a live preview/edit loop, and do not re-publish on every edit.
Publishing is terminal: the user is choosing *this* version to keep.

## How to run

Write the Markdown to a `.md` file, then run the `mdexport` CLI (it must be on PATH —
see the notmarkdown README to install it). Outputs are written next to the input.

```bash
mdexport FILE.md                 # self-contained HTML (default)
mdexport FILE.md --pdf           # PDF via Typst (fast, archival/offline)
mdexport FILE.md --pdf-from-html # PDF that matches the HTML exactly (needs a browser)
mdexport FILE.md --epub          # portable ebook; diagrams + math embedded
mdexport FILE.md --all           # HTML + PDF
mdexport FILE.md --follow        # + every same-dir .md it links to (a linked set)
mdexport FILE.md --bundle        # --follow, then zip the set into FILE.zip
```

Choosing by intent:

| The user wants… | Use |
|---|---|
| something that opens anywhere, forever (default) | *(nothing — plain HTML)* |
| a PDF, fast/archival, no browser needed | `--pdf` |
| a PDF that looks *exactly* like the HTML | `--pdf-from-html` |
| to read it on a phone / e-reader | `--epub` |
| a whole set of interlinked notes, one bundle | `--bundle` |

## Behavior to know (so you report accurately)

- **Diagrams:** the default renderer is browser-free and covers ~5 Mermaid types;
  set `MDEXPORT_MERMAID=mmdc` for full coverage (pulls in headless Chrome). A diagram
  that can't render becomes a **visible placeholder**, not a failure — the build still
  succeeds. Pass `--strict` to make any diagram failure abort instead.
- **Math** that pandoc can't parse is passed through with a **warning on stderr** —
  that's a source-LaTeX error to surface to the user, not a pipeline failure.
- `--pdf-from-html` needs a Chromium-family browser; if none is found it says so.
- Always tell the user the path(s) of what you produced.
