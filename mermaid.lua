--[[
  mermaid.lua — Pandoc Lua filter: render every ```mermaid block into a baked-in
  diagram, BATCHED and PER-OUTPUT-FORMAT, with per-block failure isolation.

  Document-level (a Pandoc filter, not a per-block one): all diagrams are
  collected once, de-duplicated by content hash, and rendered together before the
  document is reassembled:
    • mmdc (headless Chrome) — one batched launch for the whole document; falls
      back to per-diagram only if the batch aborts, so a single bad block is
      isolated rather than taking the rest down. Per format: inline SVG for HTML,
      high-DPI PNG for PDF (Typst's usvg silently drops mmdc's <foreignObject>
      labels, so the PDF gets browser-rendered pixels it cannot mangle).
    • the browser-free mermaidx wrapper (the default) — SVG only, one diagram per
      call, but still de-duplicated and reassembled through the same path.

  Which behavior applies is set explicitly by MDEXPORT_MERMAID_KIND (mmdc|svg),
  not guessed from the renderer's name. Inline HTML SVGs are id-namespaced
  (svg-scope) with a UNIQUE per-occurrence prefix, so multiple diagrams — from
  either renderer, both of which emit fixed ids, and even byte-identical repeats —
  never collide in one document.

  A diagram that will not render becomes a visible placeholder (not a raw fence),
  so one bad block never destroys the document; --strict restores abort-on-fail.
--]]

local RENDERER = os.getenv('MDEXPORT_MERMAID') or 'mermaidx'
local IS_MMDC  = (os.getenv('MDEXPORT_MERMAID_KIND') or 'svg') == 'mmdc'
local STRICT   = os.getenv('MDEXPORT_STRICT')
local TMP      = os.getenv('MDEXPORT_TMP') or '.'
local SVGSCOPE = os.getenv('MDEXPORT_SVGSCOPE') or 'svg-scope'

-- POSIX single-quote a path for safe interpolation into a shell command run by
-- os.execute/io.popen. (Lua's %q quotes for LUA, not the shell: it leaves $ and
-- backticks live, so a temp/asset path containing them would break or inject.)
local function shq(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

local function exists(path)
  local f = io.open(path, 'r'); if f then f:close(); return true end; return false
end

-- mmdc flags for the wanted artifact — the single source of truth for both the
-- batched and the per-diagram invocation, so they can't drift apart.
local function mmdc_flags(want_png) return want_png and ' -s 3' or ' -b transparent' end

-- Visible cross-format placeholder for a diagram that failed to render. Returned
-- as a Pandoc Div so both writers emit visible content and a raw ```mermaid fence
-- never reaches either output. Neutral class so it neither re-triggers rendering
-- nor trips mdexport's HTML no-leak sentinel (which greps for class="mermaid").
local function placeholder(src, why)
  io.stderr:write(('mermaid.lua: diagram failed to render (%s); emitting a '
    .. 'placeholder (use --strict to abort instead)\n'):format(why))
  return pandoc.Div({
    pandoc.Para({ pandoc.Strong({ pandoc.Str('\u{26A0} diagram failed to render') }),
                  pandoc.Space(), pandoc.Str('(' .. why .. ')') }),
    pandoc.CodeBlock(src, { class = 'notmarkdown-render-error' }),
  }, { class = 'notmarkdown-render-error' })
end

-- Render one diagram (mermaidx always; mmdc only as batch-failure fallback).
-- RENDERER is left unquoted so it may carry flags; only paths are shell-quoted.
local function render_one(job, want_png)
  local flags = IS_MMDC and mmdc_flags(want_png) or ''
  local cmd = ('%s -i %s -o %s%s >/dev/null 2>&1'):format(
    RENDERER, shq(job.mmd), shq(job.out), flags)
  return os.execute(cmd) and exists(job.out)
end

-- Render every job, returning a hash->ok map. mmdc renders the whole document in
-- ONE process (single Chrome launch); if that batch aborts (mmdc fails the entire
-- run on one bad diagram) it falls back to per-diagram so the failure is isolated.
local function render_all(jobs, want_png)
  local ok = {}
  if #jobs == 0 then return ok end

  if IS_MMDC then
    local list = TMP .. '/mermaid-batch.md'
    local fh = io.open(list, 'w')
    if fh then
      for _, job in ipairs(jobs) do fh:write('```mermaid\n', job.src, '\n```\n\n') end
      fh:close()
      local ext = want_png and 'png' or 'svg'
      local obase = ('%s/mermaid-batch.%s'):format(TMP, ext)
      local cmd = ('%s -i %s -o %s%s >/dev/null 2>&1'):format(
        RENDERER, shq(list), shq(obase), mmdc_flags(want_png))
      -- mmdc numbers outputs by fence order: <base>-<n>.<ext>, 1-based. Trust the
      -- batch only if exactly #jobs files exist (no missing, no surprise extras) —
      -- otherwise the positional hash->artifact mapping could be wrong, so fall back.
      if os.execute(cmd)
         and not exists(('%s/mermaid-batch-%d.%s'):format(TMP, #jobs + 1, ext)) then
        local all = true
        for i, job in ipairs(jobs) do
          local produced = ('%s/mermaid-batch-%d.%s'):format(TMP, i, ext)
          if exists(produced) then os.rename(produced, job.out); ok[job.hash] = true
          else all = false end
        end
        if all then return ok end
      end
      ok = {}   -- batch aborted or count mismatch — isolate via per-diagram below
    end
  end

  for _, job in ipairs(jobs) do ok[job.hash] = render_one(job, want_png) end
  return ok
end

-- Read the rendered SVG for an occurrence, id-namespaced with a unique prefix
-- (so repeated identical diagrams stay distinct). Falls back to the raw SVG if
-- svg-scope is unavailable, and to nil if the artifact itself is missing.
local function scoped_svg(out, occ)
  local p = io.popen(('%s %s %s 2>/dev/null'):format(
    shq(SVGSCOPE), shq('m' .. occ .. '-'), shq(out)))
  if p then
    local data = p:read('*a'); p:close()
    if data and data ~= '' then return data end
  end
  local sh = io.open(out, 'r')
  if not sh then return nil end
  local data = sh:read('*a'); sh:close()
  return data
end

function Pandoc(doc)
  local html = FORMAT:match('html') ~= nil
  local want_png = IS_MMDC and not html
  local ext = want_png and 'png' or 'svg'

  -- 1. Collect + de-duplicate every mermaid block by content hash.
  local jobs, index = {}, {}
  doc:walk({ CodeBlock = function(cb)
    if not cb.classes:includes('mermaid') then return nil end
    local hash = pandoc.utils.sha1(cb.text)
    if not index[hash] then
      local job = {
        hash = hash, src = cb.text,
        mmd = ('%s/mermaid-%s.mmd'):format(TMP, hash),
        out = ('%s/mermaid-%s.%s'):format(TMP, hash, ext),
      }
      local f = io.open(job.mmd, 'w')
      if f then f:write(cb.text); f:close() end
      jobs[#jobs + 1] = job
      index[hash] = job
    end
  end })

  -- 2. Batch-render everything up front.
  local ok = render_all(jobs, want_png)

  -- 3. Reassemble: replace each mermaid block with its artifact or a placeholder.
  --    Inline HTML SVGs are scoped per occurrence (unique prefix each).
  local occ = 0
  return doc:walk({ CodeBlock = function(cb)
    if not cb.classes:includes('mermaid') then return nil end
    local job = index[pandoc.utils.sha1(cb.text)]
    if not (job and ok[job.hash]) then
      if STRICT then
        error(('mermaid render failed (%s) and --strict is set. Fix the diagram '
          .. 'or set MDEXPORT_MERMAID=mmdc. Offending source:\n%s'):format(RENDERER, cb.text))
      end
      return placeholder(cb.text, RENDERER .. ' render failed')
    end
    if html then
      occ = occ + 1
      local data = scoped_svg(job.out, occ)
      if not data then
        if STRICT then error('mermaid.lua: rendered SVG went missing: ' .. job.out) end
        return placeholder(cb.text, 'rendered SVG went missing')
      end
      data = data:gsub('^%s*<%?xml.-%?>%s*', '')   -- drop XML prolog for clean HTML5
      return pandoc.RawBlock('html', data)
    end
    return pandoc.Para(pandoc.Image({}, job.out, '', { ['alt'] = 'mermaid diagram' }))
  end })
end
