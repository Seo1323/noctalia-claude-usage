--!nonstrict
-- Helpers shared by the bar and icon widgets.

local M = {}

function M.conf(key, default)
  local v = noctalia.getConfig(key)
  if v == nil then return default end
  return v
end

function M.bool(key, default)
  local v = noctalia.getConfig(key)
  if v == nil then return default end
  return v == true
end

function M.text(key, default)
  return noctalia.string.trim(tostring(M.conf(key, default)))
end

local ERRORS = {
  no_credentials = "Not logged in to Claude Code",
  token_expired = "Token expired - use Claude Code once to refresh",
  network = "No connection",
  bad_response = "Unexpected API response",
  http_429 = "Rate limited - will retry",
}

-- A window whose reset time already passed has been renewed: usage is 0.
local function effective(pct, resetAt)
  if pct == nil then return nil end
  if resetAt ~= nil and tonumber(resetAt) <= os.time() then return 0 end
  return math.floor(tonumber(pct) + 0.5)
end

-- Per-window values from a fetch.sh snapshot: { pct, reset, tokens, cache }.
function M.windows(data, withCacheReads)
  local function window(prefix, pctKey)
    local pct = data and effective(data[pctKey], data[prefix .. "_reset"])
    local tokens = data and data[prefix .. "_tokens"]
    local cache = data and data[prefix .. "_cache_read"]
    if pct == 0 then tokens, cache = 0, 0 end
    if withCacheReads and tokens ~= nil then tokens = tonumber(tokens) + tonumber(cache or 0) end
    return { pct = pct, reset = data and data[prefix .. "_reset"], tokens = tokens, cache = cache }
  end
  return { five = window("five", "five_hour"), week = window("weekly", "weekly") }
end

local function secondsLeft(resetAt)
  if resetAt == nil then return nil end
  local s = tonumber(resetAt) - os.time()
  return if s > 0 then s else nil
end

-- "3d 2h" / "1h 44m" / "5m", or nil when no reset is pending.
function M.verbose(resetAt)
  local s = secondsLeft(resetAt)
  if s == nil then return nil end
  local d, h, m = s // 86400, (s % 86400) // 3600, (s % 3600) // 60
  if d > 0 then return `{d}d {h}h` end
  if h > 0 then return `{h}h {m}m` end
  return `{m}m`
end

-- "1:44" (hours:minutes), or nil when no reset is pending.
function M.compact(resetAt)
  local s = secondsLeft(resetAt)
  if s == nil then return nil end
  return string.format("%d:%02d", s // 3600, (s % 3600) // 60)
end

function M.tokens(n, full)
  if n == nil then return "--" end
  n = tonumber(n)
  if full or n < 1000 then return tostring(math.floor(n)) end
  if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
  return string.format("%.0fk", n / 1000)
end

M.DEFAULT_COLORS = { byUsage = true, color = "on_surface", warn = "tertiary", crit = "error", warnAt = 70, critAt = 90 }

function M.colorFor(pct, c)
  if not c.byUsage or pct == nil then return c.color end
  if pct >= c.critAt then return c.crit end
  if pct >= c.warnAt then return c.warn end
  return c.color
end

-- Built-in glyph, bundled star or a custom image; nil for "none".
function M.logo(mode, size, color, glyph, path)
  if mode == "glyph" then
    return ui.glyph({ name = if glyph ~= "" then glyph else "brain", size = size, color = color })
  end
  local file = if mode == "star" then noctalia.pluginDir() .. "/assets/star.svg"
    elseif mode == "custom" then (if path ~= "" then path else noctalia.pluginDir() .. "/logo.svg")
    else nil
  if file == nil then return nil end
  return ui.image({ path = file, width = size, height = size, fit = "contain" })
end

-- Only plain #rrggbb ever reaches the SVG and its file name.
local function hex(color)
  local h = if type(color) == "string" and color:sub(1, 1) ~= "#" then noctalia.getColor(color) else color
  if type(h) == "string" and h:match("^#%x%x%x%x%x%x$") then return h:lower() end
  return "#e4e1e8"
end

local RING = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
  .. '<circle cx="32" cy="32" r="25" fill="none" stroke="%s" stroke-opacity="0.25" stroke-width="9"/>%s</svg>'
local ARC = '<circle cx="32" cy="32" r="25" fill="none" stroke="%s" stroke-width="9" stroke-linecap="round"'
  .. ' stroke-dasharray="%.2f 999" transform="rotate(-90 32 32)"/>'

-- Circular gauge filled clockwise from 12 o'clock. ui.ring needs plugin_api 55, so the
-- ring is an SVG cached in the plugin data dir, one file per (percent, colors).
function M.ring(fraction, color, size)
  local dir = noctalia.pluginDataDir()
  if dir == nil then return nil end
  local p = math.clamp(math.floor(fraction * 100 + 0.5), 0, 100)
  local fg, track = hex(color), hex("on_surface")
  local path = `{dir}/ring-{p}-{fg:sub(2)}-{track:sub(2)}.svg`
  if not noctalia.fileExists(path) then
    local arc = if p > 0 then string.format(ARC, fg, 2 * math.pi * 25 * p / 100) else ""
    noctalia.writeFile(path, string.format(RING, track, arc))
  end
  return ui.image({ path = path, width = size, height = size, fit = "contain" })
end

function M.tooltip(snapshot)
  local data = snapshot and snapshot.data
  local lines = { "Claude Code" }
  if data then
    local w = M.windows(data, false)
    for _, g in { { "5h", w.five }, { "7d", w.week } } do
      local win = g[2]
      local resets = M.verbose(win.reset) or (if win.reset then "now" else "-")
      lines[#lines + 1] = `{g[1]}: {win.pct or "--"}%  (resets in {resets})`
      lines[#lines + 1] = `    tokens: {M.tokens(win.tokens)}, cache read: {M.tokens(win.cache)}`
    end
  end
  local err = snapshot and snapshot.error
  if err then lines[#lines + 1] = (if data then "Stale: " else "") .. (ERRORS[err] or err) end
  if snapshot == nil then lines[#lines + 1] = "Loading..." end
  return table.concat(lines, "\n")
end

return M
