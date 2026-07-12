--[[
  mermaid.lua — a Pandoc Lua filter that turns embedded ```mermaid fenced code
  blocks into baked-in diagrams, one PER-OUTPUT-FORMAT artifact per block.

  Why a Lua filter (and not sed/awk): Pandoc has already parsed the document, so
  a ```mermaid block arrives as a CodeBlock with class "mermaid" — no fragile
  fence-matching, no confusion over indentation or nested backticks.

  PER-FORMAT ARTIFACTS (the full-fidelity rule). A single rich SVG cannot be
  faithfully re-interpreted by two different engines, so we render each block in
  its authoritative engine and hand each output format the artifact IT renders
  correctly:
    • HTML  -> inline SVG. Browsers render Mermaid's <foreignObject>/CSS natively.
              Each SVG is given a unique --svgId so multiple diagrams inlined in
              one document don't collide on Mermaid's fixed id="my-svg" (and its
              derived markers / filters / #my-svg-scoped CSS).
    • PDF   -> high-DPI PNG. Typst's SVG engine (usvg) silently DROPS every
              <foreignObject> label (diagrams come out as empty boxes), so we
              embed browser-rendered pixels it cannot mangle.

  Why mmdc by default: the official mermaid-cli (headless Chrome) is the only
  renderer that covers every Mermaid diagram type at full fidelity. The
  browser-free mermaidx wrapper (mermaid-render) stays available as an opt-in,
  no-Chrome escape hatch via MDEXPORT_MERMAID — it is SVG-only and covers ~5
  diagram types, so it feeds SVG to both formats (accepting the usvg limitation).

  Failure handling: a diagram that will not render becomes a visible placeholder
  (see below) so one bad block never destroys the document; --strict restores the
  old all-or-nothing abort. A raw ```mermaid fence never reaches either output.
--]]

local RENDERER = os.getenv('MDEXPORT_MERMAID') or 'mmdc'
-- Is the active renderer the browser-based mmdc? Only mmdc gets per-format
-- artifacts (PNG for PDF) and --svgId; the browser-free mermaidx wrapper is
-- SVG-only. Anything that isn't our mermaidx wrapper is treated as mmdc-like.
local IS_MMDC = not (RENDERER:match('mermaid%-render') or RENDERER:match('mermaidx'))
-- Strict mode (mdexport --strict): a single failed diagram aborts the whole
-- build, as before. Default (unset): failures are ISOLATED to their block — the
-- rest of the document still renders. This is the fix for the old flaw where one
-- unsupported diagram destroyed the entire output.
local STRICT = os.getenv('MDEXPORT_STRICT')

-- Build a visible, cross-format placeholder for a diagram that failed to render.
-- Returned as a Pandoc Div (not format-specific raw text), so BOTH the HTML and
-- Typst writers emit visible content and a raw ```mermaid fence can never reach
-- either output. The source is preserved in a CodeBlock with a neutral class so
-- it (a) does not re-trigger this filter and (b) does not trip mdexport's HTML
-- no-leak sentinel, which greps for class="mermaid".
local function placeholder(src, why)
  io.stderr:write(string.format('mermaid.lua: diagram failed to render (%s); '
    .. 'emitting a placeholder (use --strict to abort instead)\n', why))
  local head = pandoc.Para({
    pandoc.Strong({pandoc.Str('\u{26A0} diagram failed to render')}),
    pandoc.Space(), pandoc.Str('(' .. why .. ')'),
  })
  local body = pandoc.CodeBlock(src, {class = 'notmarkdown-render-error'})
  return pandoc.Div({head, body}, {class = 'notmarkdown-render-error'})
end

function CodeBlock(cb)
  if not cb.classes:includes('mermaid') then return nil end

  local tmp = os.getenv('MDEXPORT_TMP') or '.'
  local hash = pandoc.utils.sha1(cb.text)
  local base = tmp .. '/mermaid-' .. hash
  local mmd = base .. '.mmd'

  local fh = io.open(mmd, 'w')
  if not fh then io.stderr:write('mermaid.lua: cannot write temp file\n'); return nil end
  fh:write(cb.text); fh:close()

  local html = FORMAT:match('html') ~= nil
  -- Per-format artifact: PNG for the PDF path (only when the renderer can
  -- produce it), SVG otherwise (all HTML, and the SVG-only mermaidx path).
  local use_png = IS_MMDC and not html
  local out = base .. (use_png and '.png' or '.svg')

  -- Build the renderer invocation. mmdc gets a unique --svgId per diagram for
  -- collision-free inline HTML, transparent bg so inline SVG suits dark mode,
  -- and -s 3 for a high-DPI raster on the PDF path.
  local cmd
  if IS_MMDC then
    local extra = use_png and ' -s 3'
                           or string.format(' --svgId mmd_%s -b transparent', hash)
    cmd = string.format('%s -i %q -o %q%s >/dev/null 2>&1', RENDERER, mmd, out, extra)
  else
    cmd = string.format('%s -i %q -o %q >/dev/null 2>&1', RENDERER, mmd, out)
  end
  -- Quote paths so spaces in a temp dir can't break the shell-out.
  if not os.execute(cmd) then
    -- A broken diagram must never reach the HTML or PDF as raw ```mermaid text.
    -- Strict: abort the whole build. Default: isolate the failure to this block
    -- and keep going, so one bad diagram no longer destroys the document.
    if STRICT then
      error(string.format('mermaid render failed (%s) and --strict is set. Fix '
        .. 'the diagram or set MDEXPORT_MERMAID=mmdc. Offending source:\n%s',
        RENDERER, cb.text))
    end
    return placeholder(cb.text, RENDERER .. ' render failed')
  end

  -- HTML: inline the SVG markup directly (greppable, no base64 bloat).
  -- Other targets (Typst/PDF, LaTeX): reference the artifact so the writer embeds it.
  if html then
    local sh = io.open(out, 'r')
    if not sh then
      if STRICT then error('mermaid.lua: rendered SVG went missing: ' .. out) end
      return placeholder(cb.text, 'rendered SVG went missing')
    end
    local data = sh:read('*a'); sh:close()
    data = data:gsub('^%s*<%?xml.-%?>%s*', '')      -- drop XML prolog for clean HTML5
    return pandoc.RawBlock('html', data)
  end
  return pandoc.Para(pandoc.Image({}, out, '', {['alt'] = 'mermaid diagram'}))
end
