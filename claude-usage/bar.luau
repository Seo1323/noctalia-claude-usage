--!nonstrict
-- Bar capsule: optional icon or usage ring + "22%  0:57  499k" (usage, time to reset, tokens).
-- Details can always show, show only when usage is high, or show only on hover. Click refreshes.

local S = require("./shared.luau")
local conf, bool = S.conf, S.bool

local SEPARATORS = { dot = "·", bar = "|", slash = "/" }

local cfg = {
  window = conf("window", "five_hour"), -- five_hour | weekly | both
  display = conf("display_mode", "always"), -- always | important | hover
  logo = conf("logo", "none"), -- none | glyph | star | custom | ring
  glyph = S.text("glyph", "brain"),
  logoPath = S.text("logo_path", ""),
  iconSize = tonumber(conf("icon_size", 18)) or 18,
  showPercent = bool("show_percent", true),
  percentLeft = conf("percent_mode", "used") == "left",
  showPrefix = bool("show_prefix", false),
  showBar = bool("show_bar", false),
  barWidth = tonumber(conf("bar_width", 32)) or 32,
  gaugeLeft = conf("gauge_mode", "left") == "left",
  showReset = bool("show_reset", true),
  resetText = if conf("reset_format", "compact") == "verbose" then S.verbose else S.compact,
  readyText = tostring(conf("ready_text", "ready")),
  showTokens = bool("show_tokens", true),
  cacheReads = bool("include_cache_read", false),
  fullTokens = conf("token_format", "short") == "full",
  separator = SEPARATORS[conf("separator", "none")],
  dim = bool("dim_extras", false),
  gap = tonumber(conf("gap", 4)) or 4,
  weight = conf("font_weight", "medium"),
  colors = {
    byUsage = bool("color_by_usage", true),
    color = conf("color", "on_surface"),
    warn = conf("warn_color", "tertiary"),
    crit = conf("critical_color", "error"),
    warnAt = tonumber(conf("warn_at", 70)) or 70,
    critAt = tonumber(conf("critical_at", 90)) or 90,
  },
  clickCommand = S.text("click_command", ""),
}

local snapshot = noctalia.state.get("usage")
local hovered = false

local function percentText(prefix, pct)
  local text = if pct == nil then "--" elseif cfg.percentLeft then `{100 - pct}% left` else `{pct}%`
  return if cfg.showPrefix then `{prefix} {text}` else text
end

-- Share of the bar / ring that is filled.
local function gauge(pct)
  local used = (pct or 0) / 100
  return if cfg.gaugeLeft then 1 - used else used
end

local render

local function onHover(state)
  hovered = state == "true"
  render()
end

function render()
  local data = snapshot and snapshot.data
  local win = S.windows(data, cfg.cacheReads)
  local shown = {}
  if cfg.window ~= "weekly" then shown[#shown + 1] = { "5h", win.five } end
  if cfg.window ~= "five_hour" then shown[#shown + 1] = { "7d", win.week } end
  local compact = cfg.display == "hover" and not hovered

  local icon
  if cfg.logo == "ring" then
    local pct = shown[1][2].pct
    icon = S.ring(gauge(pct), S.colorFor(pct, cfg.colors), cfg.iconSize)
  else
    icon = S.logo(cfg.logo, cfg.iconSize, cfg.colors.color, cfg.glyph, cfg.logoPath)
  end

  local items = {}
  local function label(text, color)
    items[#items + 1] = ui.label({ text = text, color = color, fontWeight = cfg.weight })
  end

  for _, g in shown do
    local prefix, w = g[1], g[2]
    local color = S.colorFor(w.pct, cfg.colors)
    if compact then
      if icon == nil then label(percentText(prefix, w.pct), color) end
    else
      local before = #items
      local extra = if cfg.dim then "on_surface_variant" else color
      local details = cfg.display ~= "important" or (w.pct or 0) >= cfg.colors.warnAt
      if cfg.showPercent then label(percentText(prefix, w.pct), color) end
      if details then
        if cfg.showBar then
          items[#items + 1] = ui.progress({
            progress = gauge(w.pct), fill = color, track = "on_surface/0.2",
            width = cfg.barWidth, height = 6, radius = 3,
          })
        end
        if cfg.showReset and data then label(cfg.resetText(w.reset) or cfg.readyText, extra) end
        if cfg.showTokens then label(S.tokens(w.tokens, cfg.fullTokens), extra) end
      end
      if #items == before then label(percentText(prefix, w.pct), color) end
    end
  end

  local parts = { icon }
  for i, node in items do
    if i > 1 and cfg.separator then
      parts[#parts + 1] = ui.label({ text = cfg.separator, color = "on_surface_variant", fontWeight = cfg.weight })
    end
    parts[#parts + 1] = node
  end

  local container = if barWidget.isVertical() then ui.column else ui.row
  barWidget.render(container({
    key = "capsule", gap = cfg.gap, align = "center",
    onHover = if cfg.display == "hover" then onHover else nil,
  }, parts))
  barWidget.setTooltip(S.tooltip(snapshot))
end

noctalia.state.watch("usage", function(value)
  snapshot = value
  render()
end)

-- Re-render each minute so countdowns and renewed windows stay current.
function update()
  noctalia.setUpdateInterval(60000)
  render()
end

function onClick()
  if cfg.clickCommand ~= "" then
    noctalia.runAsync(`PATH="$HOME/.local/bin:$PATH" setsid -f {cfg.clickCommand} >/dev/null 2>&1`, function() end)
  else
    noctalia.state.set("refresh", noctalia.nowMs())
  end
end

render()
