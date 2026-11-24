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

-- Error codes from fetch.sh that have a translated message (others are shown as-is).
local ERRORS = { no_credentials = true, token_expired = true, network = true, bad_response = true, http_429 = true }

-- Tokens count the new text (sent + written) by default; the plugin setting count_cache_writes
-- also counts text saved for re-reading, which jumps after a pause when a long conversation is
-- saved again.
local COUNT_WRITES = noctalia.getConfig("count_cache_writes") == true
M.COUNT_WRITES = COUNT_WRITES

-- Tokens of one per-model entry from fetch.sh, following count_cache_writes.
function M.modelTokens(m)
  if COUNT_WRITES then return tonumber(m.tokens) or 0 end
  return (tonumber(m.input) or 0) + (tonumber(m.output) or 0)
end

-- Per-window values from a fetch.sh snapshot: { pct, reset, tokens, cache }.
-- A window whose reset time already passed has been renewed, so it counts as unused.
function M.windows(data, withCacheReads)
  local function window(prefix, pctKey)
    local reset = data and data[prefix .. "_reset"]
    local pct = data and data[pctKey]
    -- older cached readings have no *_io field yet: fall back to the full count
    local tokens = data and (if COUNT_WRITES then data[prefix .. "_tokens"] else (data[prefix .. "_io"] or data[prefix .. "_tokens"]))
    local cache = data and data[prefix .. "_cache_read"]
    if pct ~= nil then pct = tonumber(pct) end
    if reset ~= nil and tonumber(reset) <= os.time() then pct, tokens, cache = 0, 0, 0 end
    if withCacheReads and tokens ~= nil then tokens = tonumber(tokens) + tonumber(cache or 0) end
    local cost = if pct == 0 and reset ~= nil and tonumber(reset) <= os.time() then 0 else M.cost(data and data[prefix .. "_models"])
    return { pct = pct, reset = data and data[prefix .. "_reset"], tokens = tokens, cache = cache, cost = cost }
  end
  return { five = window("five", "five_hour"), week = window("weekly", "weekly") }
end

-- Percent with the configured number of decimals (plugin setting percent_decimals).
local DECIMALS = math.clamp(tonumber(noctalia.getConfig("percent_decimals")) or 0, 0, 2)
function M.num(pct)
  if pct == nil then return "--" end
  return string.format(`%.{DECIMALS}f`, pct)
end

-- API list prices in USD per million tokens: { input, output, cache read }. Cache writes are
-- 1.25x input (5-minute TTL) or 2x input (1-hour TTL). Source: Anthropic pricing, 2026-11.
-- Subscription users do not pay per token; this is an "at API prices" estimate.
local PRICES = {
  ["claude-fable-5-2"] = { 8, 40, 0.20 }, ["claude-mythos-5-2"] = { 8, 40, 0.20 },
  ["claude-fable-5-1"] = { 10, 50, 0.25 }, ["claude-mythos-5-1"] = { 10, 50, 0.25 },
  ["claude-fable-5"] = { 10, 50, 1.00 }, ["claude-mythos-5"] = { 10, 50, 1.00 },
  ["claude-opus-5-5"] = { 4, 20, 0.20 },
  ["claude-opus-5"] = { 5, 25, 0.50 },
  ["claude-sonnet-5-5"] = { 2, 10, 0.10 },
  ["claude-sonnet-5"] = { 2, 10, 0.20 },
  ["claude-sonnet-4-6"] = { 3, 15, 0.30 },
  ["claude-haiku-5-5"] = { 0.10, 0.50, 0.01 },
  ["claude-haiku-4-5"] = { 1, 5, 0.10 },
}
-- Unknown or older ids fall back to their family's classic price.
local FAMILY = { fable = { 10, 50, 1.00 }, mythos = { 10, 50, 1.00 }, opus = { 5, 25, 0.50 }, sonnet = { 3, 15, 0.30 }, haiku = { 1, 5, 0.10 } }

-- Optional own prices (plugin settings, USD per million tokens) replace the table for every model.
local CUSTOM = if noctalia.getConfig("custom_prices") == true then {
  tonumber(noctalia.getConfig("price_input")) or 4,
  tonumber(noctalia.getConfig("price_output")) or 20,
  tonumber(noctalia.getConfig("price_cache_read")) or 0.2,
} else nil

local function priceFor(id)
  if CUSTOM then return CUSTOM end
  local p = PRICES[id]
  if p then return p end
  for family, fp in FAMILY do
    if id:find(family, 1, true) then return fp end
  end
  return nil
end

-- Estimated cost in USD of a list of per-model entries from fetch.sh (nil when none is priced).
function M.cost(models)
  if models == nil then return nil end
  local total, priced = 0, false
  for _, m in models do
    local p = priceFor(m.model or "")
    if p then
      priced = true
      local input = tonumber(m.input or 0) + 1.25 * tonumber(m.cache_write_5m or 0) + 2 * tonumber(m.cache_write_1h or 0)
      total += (input * p[1] + tonumber(m.output or 0) * p[2] + tonumber(m.cache_read or 0) * p[3]) / 1000000
    end
  end
  return if priced then total else nil
end

-- Plugin setting show_prices: off hides every cost (bar, tooltip and panel).
M.SHOW_PRICES = noctalia.getConfig("show_prices") ~= false

-- Display currency (plugin setting). The rate is manual (exchange_rate = units per 1 USD) or,
-- when that is 0, the ECB reference rates the poller publishes as "rates" (EUR based).
local CURRENCY = tostring(noctalia.getConfig("currency") or "USD")
local MANUAL_RATE = tonumber(noctalia.getConfig("exchange_rate")) or 0
-- symbol, placed before (true) or after (false) the amount; decimals for small amounts
local SYMBOLS = {
  USD = { "$", true, 2 }, EUR = { " €", false, 2 }, GBP = { "£", true, 2 }, PLN = { " zł", false, 2 },
  CHF = { "CHF ", true, 2 }, JPY = { "¥", true, 0 }, CNY = { "¥", true, 2 }, CAD = { "C$", true, 2 },
  AUD = { "A$", true, 2 }, SEK = { " kr", false, 2 }, NOK = { " kr", false, 2 }, DKK = { " kr", false, 2 },
  CZK = { " Kč", false, 0 }, HUF = { " Ft", false, 0 }, RON = { " lei", false, 2 }, TRY = { "₺", true, 2 },
  BRL = { "R$", true, 2 }, INR = { "₹", true, 0 }, KRW = { "₩", true, 0 }, MXN = { "MX$", true, 2 },
}

local function rate()
  if CURRENCY == "USD" then return 1 end
  if MANUAL_RATE > 0 then return MANUAL_RATE end
  local rates = noctalia.state.get("rates")
  if rates and rates.USD and rates[CURRENCY] then return rates[CURRENCY] / rates.USD end
  return nil
end

-- Formats a USD amount in the display currency; falls back to USD until rates arrive.
function M.money(usd)
  if usd == nil then return "--" end
  local r, code = rate(), CURRENCY
  if r == nil then r, code = 1, "USD" end
  local amount = usd * r
  local sym = SYMBOLS[code] or { " " .. code, false, 2 }
  local decimals = if amount >= 100 then 0 elseif amount >= 10 then math.min(1, sym[3]) else sym[3]
  local text = string.format(`%.{decimals}f`, amount)
  return if sym[2] then sym[1] .. text else text .. sym[1]
end

-- "claude-opus-5-5" -> "Opus 5.5"; ids in another shape are returned unchanged.
function M.modelName(id)
  local family, rest = id:match("^claude%-(%a+)%-?(.*)$")
  if family == nil then return id end
  local version = (rest:gsub("%-%d%d%d%d%d%d%d%d$", ""):gsub("%-", "."))
  return family:sub(1, 1):upper() .. family:sub(2) .. (if version ~= "" then " " .. version else "")
end

local function secondsLeft(resetAt)
  if resetAt == nil then return nil end
  local s = tonumber(resetAt) - os.time()
  -- round up to whole minutes: 2m 1s left shows 3m, never 2m
  return if s > 0 then (s + 59) // 60 * 60 else nil
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

-- "1:44" (hours:minutes) or "2d 13:56" from a day on; nil when no reset is pending.
function M.compact(resetAt)
  local s = secondsLeft(resetAt)
  if s == nil then return nil end
  if s >= 86400 then return string.format("%dd %d:%02d", s // 86400, (s % 86400) // 3600, (s % 3600) // 60) end
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

local function mix(a, b, t)
  local function ch(h, i) return tonumber(h:sub(i, i + 1), 16) end
  local function lerp(i) return math.floor(ch(a, i) + (ch(b, i) - ch(a, i)) * t + 0.5) end
  return string.format("#%02x%02x%02x", lerp(2), lerp(4), lerp(6))
end

function M.colorFor(pct, c)
  if not c.byUsage or pct == nil then return c.color end
  if c.gradient then -- smooth blend: color at 0 -> warn at warnAt -> crit at critAt
    local base, warn, crit = M.hex(c.color), M.hex(c.warn), M.hex(c.crit)
    if pct >= c.critAt then return crit end
    if pct >= c.warnAt then return mix(warn, crit, (pct - c.warnAt) / math.max(1, c.critAt - c.warnAt)) end
    return mix(base, warn, math.max(0, pct) / math.max(1, c.warnAt))
  end
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

-- Resolves a color role or hex to plain #rrggbb; only that ever reaches the SVG and its file name.
function M.hex(color)
  local h = if type(color) == "string" and color:sub(1, 1) ~= "#" then noctalia.getColor(color) else color
  if type(h) == "string" and h:match("^#%x%x%x%x%x%x$") then return h:lower() end
  return "#e4e1e8"
end

local RING_WIDTH = { thin = 5, normal = 9, thick = 13 }
local TRACK = '<circle cx="32" cy="32" r="%.1f" fill="none" stroke="%s" stroke-opacity="0.25" stroke-width="%d"/>'
local ARC = '<circle cx="32" cy="32" r="%.1f" fill="none" stroke="%s" stroke-width="%d" stroke-linecap="round"'
  .. ' stroke-dasharray="%.2f 999" transform="rotate(-90 32 32)"/>'

local written = {} -- ring files known to exist, to skip the disk check

-- Circular gauge filled clockwise from 12 o'clock. ui.ring needs plugin_api 55, so the ring is
-- an SVG cached in the plugin data dir, one file per (percent, colors, thickness, track).
-- opts: { thickness = "thin" | "normal" | "thick", track = bool }
function M.ring(fraction, color, size, opts)
  local dir = noctalia.pluginDataDir()
  if dir == nil then return nil end
  opts = opts or {}
  local width = RING_WIDTH[opts.thickness or "normal"] or 9
  local showTrack = opts.track ~= false
  local p = math.clamp(math.floor(fraction * 100 + 0.5), 0, 100)
  local fg, track = M.hex(color), M.hex("on_surface")
  local path = `{dir}/ring-{p}-{fg:sub(2)}-{track:sub(2)}-{width}{if showTrack then "t" else "n"}.svg`
  if not written[path] and not noctalia.fileExists(path) then
    local r = 32 - width / 2 - 2
    local body = if showTrack then string.format(TRACK, r, track, width) else ""
    if p > 0 then body ..= string.format(ARC, r, fg, width, 2 * math.pi * r * p / 100) end
    noctalia.writeFile(path, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">' .. body .. "</svg>")
  end
  written[path] = true
  return ui.image({ path = path, width = size, height = size, fit = "contain" })
end

-- Runs a user-configured command detached from the shell, with ~/.local/bin on PATH (claude lives there).
function M.spawn(command)
  noctalia.runAsync(`PATH="$HOME/.local/bin:$PATH" setsid -f {command} >/dev/null 2>&1`, function() end)
end

function M.tooltip(snapshot)
  local data = snapshot and snapshot.data
  local lines = { "Claude Code" }
  if data then
    local w = M.windows(data, false)
    for _, g in { { "5h", w.five }, { "7d", w.week } } do
      local win = g[2]
      local time = M.verbose(win.reset)
      lines[#lines + 1] = if time
        then noctalia.tr("tooltip.window", { window = g[1], pct = M.num(win.pct), time = time })
        else `{g[1]}: {M.num(win.pct)}%  ({noctalia.tr("bar.ready")})`
      lines[#lines + 1] = "    " .. noctalia.tr("tooltip.tokens", { tokens = M.tokens(win.tokens), cache = M.tokens(win.cache) })
      if M.SHOW_PRICES and win.cost ~= nil then lines[#lines + 1] = "    " .. noctalia.tr("tooltip.cost", { cost = M.money(win.cost) }) end
    end
  end
  local err = snapshot and snapshot.error
  if err then
    local msg = if ERRORS[err] then noctalia.tr("error." .. err) else err
    lines[#lines + 1] = if data then noctalia.tr("tooltip.stale", { error = msg }) else msg
  end
  if snapshot == nil then lines[#lines + 1] = noctalia.tr("tooltip.loading") end
  return table.concat(lines, "\n")
end

return M
