--[[
  mdlinks.lua — link handling for `mdexport --follow`. A NO-OP unless the CLI sets
  MDEXPORT_FOLLOW_OUT, so it never affects an ordinary build.

  For each link to a same-directory Markdown file it (a) rewrites the target
  X.md -> X.html so an exported set of interlinked docs stays navigable, and (b)
  appends the referenced filename to MDEXPORT_FOLLOW_OUT so the CLI can follow it.

  Because it runs on Pandoc's parsed AST — not raw text — it correctly handles a
  leading "./", link titles, #fragments, reference-style links, and percent-encoded
  names, and it NEVER matches a code block, a URL, or a link into another directory.

  Security: the target is percent-decoded BEFORE the same-directory test, so an
  encoded separator (e.g. %2f) or "../" can't smuggle a path outside the directory
  past the check — anything containing a slash after decoding is left untouched.
--]]

local OUT = os.getenv('MDEXPORT_FOLLOW_OUT')

local function urldecode(s)
  return (s:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end

function Link(el)
  if not OUT then return nil end                       -- not a --follow build
  local path, frag = el.target:match('^([^#]*)(#?.*)$')  -- split off any #fragment
  if not path or path:match('^%a[%w+.-]*:') then return nil end   -- URL scheme -> leave
  -- Tolerate one leading "./", then decode; the decoded name is what we test and
  -- what we build, so encoded separators can't slip a path past the same-dir gate.
  local bare = urldecode((path:gsub('^%./', '')))
  if bare == '' or bare:find('/') then return nil end   -- other dir / traversal / absolute
  if not bare:lower():match('%.md$') then return nil end -- not Markdown -> leave
  local fh = io.open(OUT, 'a')
  if fh then fh:write(bare, '\n'); fh:close() end
  el.target = path:gsub('%.[Mm][Dd]$', '.html') .. frag
  return el
end
