--[[
  mermaid.lua — a tiny, self-contained Pandoc Lua filter that turns embedded
  ```mermaid fenced code blocks into baked-in SVG, browser-free.

  Why a Lua filter (and not sed/awk): Pandoc has already parsed the document, so
  a ```mermaid block arrives as a CodeBlock with class "mermaid" — no fragile
  fence-matching, no confusion over indentation or nested backticks.

  Why mermaidx (not mmdc): mermaidx renders the real Mermaid v11 library inside
  an embedded JS engine (QuickJS-ng) with NO headless Chrome / Puppeteer — the
  single biggest long-term-fragility source in this space. Its SVG also contains
  no <foreignObject>, so it converts cleanly to PDF later.

  The rendered SVG is written to $MDEXPORT_TMP and referenced as an Image; Pandoc
  then inlines it (self-contained HTML) or embeds it (Typst PDF). If a diagram
  fails to render we ABORT the whole conversion with a Lua error, so a broken
  diagram can never leak into EITHER output as raw text — the no-leak guarantee
  holds for both HTML and PDF, not just the format mdexport greps afterward.
--]]

local RENDERER = os.getenv('MDEXPORT_MERMAID') or 'mermaidx'

function CodeBlock(cb)
  if not cb.classes:includes('mermaid') then return nil end

  local tmp = os.getenv('MDEXPORT_TMP') or '.'
  local base = tmp .. '/mermaid-' .. pandoc.utils.sha1(cb.text)
  local mmd, svg = base .. '.mmd', base .. '.svg'

  local fh = io.open(mmd, 'w')
  if not fh then io.stderr:write('mermaid.lua: cannot write temp file\n'); return nil end
  fh:write(cb.text); fh:close()

  -- Quote paths so spaces in a temp dir can't break the shell-out.
  local cmd = string.format('%s -i %q -o %q >/dev/null 2>&1', RENDERER, mmd, svg)
  if not os.execute(cmd) then
    -- Abort the conversion rather than pass the raw fence through: a broken
    -- diagram must never reach the HTML or the PDF as text.
    error(string.format('mermaid render failed (%s). Fix the diagram or set '
      .. 'MDEXPORT_MERMAID=mmdc. Offending source:\n%s', RENDERER, cb.text))
  end

  -- HTML: inline the SVG markup directly (greppable, no base64 bloat).
  -- Other targets (Typst/PDF, LaTeX): reference the file so the writer embeds it.
  if FORMAT:match('html') then
    local sh = io.open(svg, 'r')
    if not sh then error('mermaid.lua: rendered SVG went missing: ' .. svg) end
    local data = sh:read('*a'); sh:close()
    data = data:gsub('^%s*<%?xml.-%?>%s*', '')      -- drop XML prolog for clean HTML5
    return pandoc.RawBlock('html', data)
  end
  return pandoc.Para(pandoc.Image({}, svg, '', {['alt'] = 'mermaid diagram'}))
end
