--!nonstrict
-- Bar capsule: optional icon + "5h 12%  1:44  92k" (usage %, time to reset, tokens used).
-- Everything is configurable in the widget settings. Click refreshes (or runs a custom command).

local function conf(key, default)
  local v = noctalia.getConfig(key)
  if v == nil then return default end
  return v
end

local cfg = {
  window = conf("window", "five_hour"), -- five_hour | weekly | both
  logo = conf("logo", "none"), -- none | glyph | star | custom
  showPrefix = conf("show_prefix", false) ~= false,
  showPercent = conf("show_percent", true) ~= false,
  showReset = conf("show_reset", true) ~= false,
  showTokens = conf("show_tokens", true) ~= false,
  resetFormat = conf("reset_format", "compact"), -- compact (1:44) | verbose (1h 44m)
  tokenFormat = conf("token_format", "short"), -- short (92k) | full (92424)
  readyText = tostring(conf("ready_text", "ready")),
  gap = tonumber(conf("gap", 4)) or 4,
  weight = conf("font_weight", "medium"),
  colorByUsage = conf("color_by_usage", true) ~= false,
  color = conf("color", "on_surface"),
  warnColor = conf("warn_color", "tertiary"),
  critColor = conf("critical_color", "error"),
  warnAt = tonumber(conf("warn_at", 70)) or 70,
  critAt = tonumber(conf("critical_at", 90)) or 90,
  logoPath = noctalia.string.trim(tostring(conf("logo_path", ""))),
  clickCommand = noctalia.string.trim(tostring(conf("click_command", ""))),
}

local snapshot = noctalia.state.get("usage")

-- Custom logo: the `logo_path` setting, or logo.svg inside the plugin folder.
local function logoFile()
  if cfg.logo == "star" then return noctalia.pluginDir() .. "/assets/star.svg" end
  if cfg.logoPath ~= "" then return (cfg.logoPath:gsub("^~", os.getenv("HOME") or "~")) end
  return noctalia.pluginDir() .. "/logo.svg"
end

local ERRORS = {
  no_credentials = "Not logged in to Claude Code",
  token_expired = "Token expired - use Claude Code once to refresh",
  network = "No connection",
  bad_response = "Unexpected API response",
}

local function colorFor(pct)
  if not cfg.colorByUsage or pct == nil then return cfg.color end
  if pct >= cfg.critAt then return cfg.critColor end
  if pct >= cfg.warnAt then return cfg.warnColor end
  return cfg.color
end

-- A window whose reset time already passed has been renewed: usage is 0.
local function effective(pct, resetAt)
  if pct == nil then return nil end
  if resetAt ~= nil and tonumber(resetAt) <= os.time() then return 0 end
  return math.floor(tonumber(pct) + 0.5)
end

-- Time to reset for the tooltip ("1h 44m", "3d 2h").
local function left(resetAt)
  if resetAt == nil then return "-" end
  local s = tonumber(resetAt) - os.time()
  if s <= 0 then return "now" end
  local d, h, m = s // 86400, (s % 86400) // 3600, (s % 3600) // 60
  if d > 0 then return `{d}d {h}h` end
  if h > 0 then return `{h}h {m}m` end
  return `{m}m`
end

-- Time to reset for the bar, in the configured format.
local function resetText(resetAt)
  if resetAt == nil then return cfg.readyText end
  local s = tonumber(resetAt) - os.time()
  if s <= 0 then return cfg.readyText end
  if cfg.resetFormat == "verbose" then return left(resetAt) end
  return string.format("%d:%02d", s // 3600, (s % 3600) // 60)
end

local function fmtTokens(n, full)
  if n == nil then return "--" end
  n = tonumber(n)
  if full then return tostring(math.floor(n)) end
  if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
  if n >= 1000 then return string.format("%.0fk", n / 1000) end
  return tostring(n)
end

local function render()
  local data = snapshot and snapshot.data
  local err = snapshot and snapshot.error

  local parts = {}
  if cfg.logo == "custom" or cfg.logo == "star" then
    parts[#parts + 1] = ui.image({ path = logoFile(), width = 18, height = 18, fit = "contain" })
  elseif cfg.logo == "glyph" then
    parts[#parts + 1] = ui.glyph({ name = "brain", color = cfg.color })
  end

  local function label(text, pct)
    parts[#parts + 1] = ui.label({ text = text, color = colorFor(pct), fontWeight = cfg.weight })
  end

  -- One group of labels for a usage window.
  local function group(prefix, pct, resetAt, tokens)
    local any = false
    if cfg.showPercent then
      local text = pct == nil and "--" or `{pct}%`
      if cfg.showPrefix then text = `{prefix} {text}` end
      label(text, pct)
      any = true
    end
    if cfg.showReset and data then label(resetText(resetAt), pct); any = true end
    if cfg.showTokens then label(fmtTokens(pct == 0 and 0 or tokens, cfg.tokenFormat == "full"), pct); any = true end
    if not any then label(pct == nil and "--" or `{pct}%`, pct) end
  end

  local five = data and effective(data.five_hour, data.five_reset)
  local week = data and effective(data.weekly, data.weekly_reset)
  if cfg.window ~= "weekly" then
    group("5h", five, data and data.five_reset, data and data.five_tokens)
  end
  if cfg.window ~= "five_hour" then
    group("7d", week, data and data.weekly_reset, data and data.weekly_tokens)
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = cfg.gap, align = "center" }, parts))

  local lines = { "Claude Code" }
  if data then
    lines[#lines + 1] = `5h: {five or "--"}%  (resets in {left(data.five_reset)})\n    tokens: {fmtTokens(five == 0 and 0 or data.five_tokens)}`
    lines[#lines + 1] = `7d: {week or "--"}%  (resets in {left(data.weekly_reset)})\n    tokens: {fmtTokens(week == 0 and 0 or data.weekly_tokens)}`
  end
  if err then lines[#lines + 1] = (data and "Stale: " or "") .. (ERRORS[err] or err) end
  if snapshot == nil then lines[#lines + 1] = "Loading..." end
  barWidget.setTooltip(table.concat(lines, "\n"))
end

noctalia.state.watch("usage", function(value)
  snapshot = value
  render()
end)

-- Re-render each minute so reset countdowns / renewed windows stay current.
function update()
  noctalia.setUpdateInterval(60000)
  render()
end

function onClick()
  if cfg.clickCommand ~= "" then
    noctalia.runAsync("PATH=\"$HOME/.local/bin:$PATH\" setsid -f " .. cfg.clickCommand .. " >/dev/null 2>&1", function() end)
  else
    noctalia.runAsync("noctalia msg plugin seo/claude-usage:poller all refresh", function() end)
  end
end

render()
