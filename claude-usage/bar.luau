--!nonstrict
-- Bar capsule: optional icon or usage ring + "22%  0:57  499k" (usage, time to reset, tokens).
-- Details can always show, show only when usage is high, or slide out on hover.
-- Left click: panel, click_command or refresh (click_action); right click: refresh.

local S = require("./shared.luau")
local conf, bool = S.conf, S.bool

local SEPARATORS = { dot = "·", bar = "|", slash = "/" }
local CHAR_PX = 7 -- rough width of one character, to pace the bar against the text

local cfg = {
  window = conf("window", "five_hour"), -- five_hour | weekly | both
  display = conf("display_mode", "always"), -- always | important | hover
  animationMs = math.max(0, tonumber(conf("animation_ms", 250)) or 250),
  logo = conf("logo", "ring"), -- none | glyph | star | custom | ring
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
  readyText = S.text("ready_text", ""), -- empty = translated "ready"
  showTokens = bool("show_tokens", true),
  cacheReads = bool("include_cache_read", false),
  fullTokens = conf("token_format", "short") == "full",
  showCost = bool("show_cost", false),
  separator = SEPARATORS[conf("separator", "dot")],
  dim = bool("dim_extras", true),
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
  clickAction = conf("click_action", "panel"), -- panel | command | refresh
  panelTranslucent = bool("panel_translucent", false),
  panelOpacity = math.clamp(tonumber(conf("panel_opacity", 0.85)) or 0.85, 0, 1),
  clickCommand = S.text("click_command", ""),
}
if cfg.readyText == "" then cfg.readyText = noctalia.tr("bar.ready") end
-- The panel cannot read this widget's settings, so its look is handed over through shared state.
noctalia.state.set("panel_style", { translucent = cfg.panelTranslucent, opacity = cfg.panelOpacity })
local hoverMode = cfg.display == "hover"

local snapshot = noctalia.state.get("usage")
local frame = nil -- icon, items and tooltip; rebuilt on new data or the minute tick, reused by animation frames

-- Hover animation: linear progress from `from` to `to` (0 = collapsed, 1 = open).
local anim = { from = 0, to = if hoverMode then 0 else 1, start = 0 }

local function animProgress()
  if cfg.animationMs == 0 then return anim.to end
  local k = math.clamp((noctalia.nowMs() - anim.start) / cfg.animationMs, 0, 1)
  return anim.from + (anim.to - anim.from) * k
end

local function ease(t) -- ease-in-out cubic
  return if t < 0.5 then 4 * t * t * t else 1 - (-2 * t + 2) ^ 3 / 2
end

local function percentText(prefix, pct)
  local text = if pct == nil then "--" elseif cfg.percentLeft then noctalia.tr("bar.left", { pct = S.num(100 - pct) }) else `{S.num(pct)}%`
  return if cfg.showPrefix then `{prefix} {text}` else text
end

-- Share of the bar / ring that is filled.
local function gauge(pct)
  local used = (pct or 0) / 100
  return if cfg.gaugeLeft then 1 - used else used
end

-- First n characters of a UTF-8 string.
local function head(s, n)
  if n <= 0 then return "" end
  local i = utf8.offset(s, n + 1)
  return if i then s:sub(1, i - 1) else s
end

-- Items are plain descriptors, so the animation can reveal them a character at a time.
local function buildItems(data, shown)
  local items = {}
  local function text(t, color) items[#items + 1] = { text = t, color = color, units = utf8.len(t) or #t } end
  for _, g in shown do
    local prefix, w = g[1], g[2]
    local color = S.colorFor(w.pct, cfg.colors)
    local extra = if cfg.dim then "on_surface_variant" else color
    local before = #items
    if cfg.showPercent then text(percentText(prefix, w.pct), color) end
    if cfg.display ~= "important" or (w.pct or 0) >= cfg.colors.warnAt then
      if cfg.showBar then
        items[#items + 1] = { bar = gauge(w.pct), color = color, units = math.ceil(cfg.barWidth / CHAR_PX) }
      end
      if cfg.showReset and data then text(cfg.resetText(w.reset) or cfg.readyText, extra) end
      if cfg.showTokens then text(S.tokens(w.tokens, cfg.fullTokens), extra) end
      if cfg.showCost and w.cost ~= nil then text(S.money(w.cost), extra) end
    end
    if #items == before then text(percentText(prefix, w.pct), color) end
  end
  if cfg.separator then -- interleave separators
    local out = {}
    for i, item in items do
      if i > 1 then out[#out + 1] = { text = cfg.separator, color = "on_surface_variant", units = 1 } end
      out[#out + 1] = item
    end
    items = out
  end
  return items
end

-- `units` = how much of the item is visible (nil = all), `alpha` = its opacity.
local function toNode(item, units, alpha)
  if item.bar then
    local width = if units then math.min(cfg.barWidth, units * CHAR_PX) else cfg.barWidth
    return ui.progress({
      progress = item.bar, fill = item.color, track = "on_surface/0.2",
      width = width, height = 6, radius = 3, opacity = alpha,
    })
  end
  return ui.label({
    text = if units then head(item.text, units) else item.text,
    color = item.color, fontWeight = cfg.weight, opacity = alpha,
  })
end

local render

local function onHover(state)
  anim.from = animProgress()
  anim.to = if state == "true" then 1 else 0
  anim.start = noctalia.nowMs()
  if cfg.animationMs > 0 then noctalia.setUpdateInterval(16) end
  render()
end

local function buildFrame()
  local data = snapshot and snapshot.data
  local win = S.windows(data, cfg.cacheReads)
  local shown = {}
  if cfg.window ~= "weekly" then shown[#shown + 1] = { "5h", win.five } end
  if cfg.window ~= "five_hour" then shown[#shown + 1] = { "7d", win.week } end
  local icon
  if cfg.logo == "ring" then
    local pct = shown[1][2].pct
    icon = S.ring(gauge(pct), S.colorFor(pct, cfg.colors), cfg.iconSize)
  else
    icon = S.logo(cfg.logo, cfg.iconSize, cfg.colors.color, cfg.glyph, cfg.logoPath)
  end
  local tooltip = S.tooltip(snapshot)
  if frame == nil or frame.tooltip ~= tooltip then barWidget.setTooltip(tooltip) end
  frame = { icon = icon, items = buildItems(data, shown), tooltip = tooltip }
end

function render(rebuild)
  if rebuild or frame == nil then buildFrame() end
  local icon, items = frame.icon, frame.items
  local parts = { icon }
  -- Without an icon the first item stays visible, so a collapsed capsule is never empty.
  local fixed = if icon then 0 else 1
  for i = 1, fixed do parts[#parts + 1] = toNode(items[i]) end

  local p = if hoverMode then ease(animProgress()) else 1
  if p >= 1 then
    for i = fixed + 1, #items do parts[#parts + 1] = toNode(items[i]) end
  elseif p > 0 then
    local total = 0
    for i = fixed + 1, #items do total += items[i].units end
    local budget = math.floor(p * total + 0.5)
    for i = fixed + 1, #items do
      if budget <= 0 then break end
      parts[#parts + 1] = toNode(items[i], math.min(budget, items[i].units), p)
      budget -= items[i].units
    end
  end

  local container = if barWidget.isVertical() then ui.column else ui.row
  barWidget.render(container({
    key = "capsule", gap = cfg.gap, align = "center",
    onHover = if hoverMode then onHover else nil,
  }, parts))
end

noctalia.state.watch("usage", function(value)
  snapshot = value
  render(true)
end)

-- Frames while animating, otherwise once a minute so countdowns stay current.
function update()
  local animating = animProgress() ~= anim.to
  render(not animating)
  noctalia.setUpdateInterval(if animating then 16 else 60000)
end

local function refresh()
  noctalia.state.set("refresh", noctalia.nowMs())
end

-- Left click: open the panel (launch Claude Code, graphs, per-model usage), run
-- click_command, or refresh - see click_action.
function onClick()
  if cfg.clickAction == "panel" then return noctalia.togglePanel("seo/claude-usage:panel") end
  if cfg.clickAction == "command" and cfg.clickCommand ~= "" then return S.spawn(cfg.clickCommand) end
  refresh()
end

-- Right click always refreshes.
function onRightClick()
  refresh()
end

render(true)
