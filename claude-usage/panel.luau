--!nonstrict
-- Click panel: both limits, token graphs (last 24 h / 7 days) and tokens per model.

local S = require("./shared.luau")

local snapshot = noctalia.state.get("usage")
local style = noctalia.state.get("panel_style") or {} -- set by the bar widget: { translucent, opacity, match }
local isOpen = false
local tableWindow = "five" -- five | weekly
local hover = {} -- graph id -> hovered bucket index

local function muted(text)
  return ui.label({ text = text, color = "on_surface_variant", fontSize = 12 })
end

local function heading(glyph, text)
  return ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = glyph, size = 18, color = "primary" }),
    ui.label({ text = text, fontWeight = "bold" }),
  })
end

local render

-- One half of the top card: usage ring, big percentage, window name and reset time.
local function limitBlock(label, win)
  local time = S.verbose(win.reset)
  local color = S.colorFor(win.pct, S.DEFAULT_COLORS)
  return ui.row({ gap = 12, align = "center" }, {
    S.ring(math.clamp((win.pct or 0) / 100, 0, 1), color, 52) or ui.glyph({ name = "gauge", size = 40, color = color }),
    ui.column({ gap = 2 }, {
      muted(label),
      ui.label({ text = `{S.num(win.pct)}%`, fontSize = 24, fontWeight = "bold", color = color }),
      muted(time or noctalia.tr("panel.no_reset")),
    }),
  })
end

-- Line graph of token counts with a hover readout; `unit` is the bucket length label key.
local function graph(id, glyph, title, values, ago)
  local max = 0
  for _, v in values do max = math.max(max, v) end
  local norm = {}
  for i, v in values do norm[i] = if max > 0 then v / max else 0 end
  local i = hover[id]
  local readout = if i
    then `{S.tokens(values[i])} · {ago(#values - i)}`
    else noctalia.tr("panel.peak", { tokens = S.tokens(max) })
  return ui.column({ gap = 4 }, {
    ui.row({ justify = "space_between", align = "center" }, { heading(glyph, title), muted(readout) }),
    ui.graph({
      values = norm, color = "primary", fillOpacity = 0.25, lineWidth = 2, height = 44,
      onPointerMove = function(x)
        local n = math.clamp(math.floor(tonumber(x) * #values) + 1, 1, #values)
        if hover[id] ~= n then hover[id] = n; render() end
      end,
      onPointerLeave = function() hover[id] = nil; render() end,
    }),
  })
end

local function modelTable(data)
  local list = data[tableWindow .. "_models"] or {}
  local rows = {}
  for _, m in list do
    -- thin line between rows, like the forecast list in the weather tab
    if #rows > 0 then rows[#rows + 1] = ui.separator({}) end
    local detail = noctalia.tr("panel.model_tokens", { tokens = "", messages = m.messages, cache = S.tokens(m.cache_read) })
      :gsub("^%s*·%s*", "") .. (if S.SHOW_PRICES and S.cost({ m }) then " · " .. S.money(S.cost({ m })) else "")
    rows[#rows + 1] = ui.column({ gap = 4 }, {
      ui.row({ gap = 8, align = "center" }, {
        ui.glyph({ name = "sparkles", size = 16, color = "secondary" }),
        ui.label({ text = S.modelName(m.model), fontWeight = "medium" }),
        ui.spacer({ grow = 1 }),
        ui.label({ text = S.tokens(S.modelTokens(m)), fontWeight = "bold" }),
      }),
      muted(detail),
    })
  end
  if #rows == 0 then rows[1] = muted(noctalia.tr("panel.no_models")) end
  local function tab(key, text)
    return ui.button({
      text = text, controlSize = "sm", variant = if tableWindow == key then "primary" else "ghost",
      onClick = function() tableWindow = key; render() end,
    })
  end
  return ui.column({ gap = 10 }, {
    ui.row({ justify = "space_between", align = "center" }, {
      heading("cpu", noctalia.tr("panel.by_model")),
      -- one pill holding both buttons, like the Daily / Hourly switch in the weather tab
      ui.row({ gap = 0, padding = 3, fill = "surface", radius = 10 }, { tab("five", "5h"), tab("weekly", "7d") }),
    }),
    ui.column({ gap = 10 }, rows),
    if S.SHOW_PRICES and S.cost(list) then muted(noctalia.tr("panel.cost_total", { cost = S.money(S.cost(list)) })) else nil,
  })
end

function render()
  if not isOpen then return end
  local data = snapshot and snapshot.data
  -- Like Noctalia's own panels: a title row, then each section on its own card, with the panel's
  -- glass showing between the cards. Translucency darkens or lightens the cards.
  -- "Match Noctalia's look" takes the card strength from Settings -> Panels -> Transparency.
  local MATCH = { glass = 0.45, soft = 0.7, solid = 1 }
  local alpha = if style.match then MATCH[tostring(noctalia.getSetting("shell.panel.transparency_mode") or "solid")] or 1
    elseif style.translucent then style.opacity or 0.85 else 1
  local cardFill = if alpha < 1 then string.format("surface_container/%.2f", alpha) else "surface_container"
  local function card(nodes)
    return ui.column({ padding = 14, gap = 12, fill = cardFill, radius = 16, border = "outline_variant", borderWidth = 1 }, nodes)
  end

  local children = {
    ui.row({ justify = "space_between", align = "center" }, {
      ui.label({ text = "Claude Code", fontWeight = "bold", fontSize = 16, color = "primary" }),
      ui.row({ gap = 4 }, {
        ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = noctalia.tr("panel.refresh"),
          onClick = function() noctalia.state.set("refresh", noctalia.nowMs()) end }),
        ui.button({ glyph = "settings", variant = "ghost", controlSize = "sm", tooltip = noctalia.tr("panel.settings"),
          onClick = function() noctalia.openSettings() end }),
        ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", onClick = function() panel.close() end }),
      }),
    }),
  }
  local function add(node) children[#children + 1] = node end

  if data then
    local w = S.windows(data, false)
    local gap = function() return ui.spacer({ grow = 1 }) end
    add(card({ ui.row({ align = "center" }, { gap(), limitBlock("5h", w.five), gap(), limitBlock("7d", w.week), gap() }) }))
  else
    add(card({ muted(S.tooltip(snapshot)) }))
  end

  local hourly = if S.COUNT_WRITES then data and data.hourly else data and (data.hourly_io or data.hourly)
  local daily = if S.COUNT_WRITES then data and data.daily else data and (data.daily_io or data.daily)
  if hourly then
    add(card({
      graph("hourly", "clock", noctalia.tr("panel.last_24h"), hourly, function(n) return noctalia.tr("panel.hours_ago", { n = n }) end),
      graph("daily", "calendar", noctalia.tr("panel.last_7d"), daily, function(n) return noctalia.tr("panel.days_ago", { n = n }) end),
    }))
  end

  if data and data.hourly then add(card({ modelTable(data) })) end

  -- Noctalia draws the panel background itself (attached or floating), like its own panels.
  panel.render(ui.column({ gap = 8 }, children))
end

noctalia.state.watch("usage", function(value)
  snapshot = value
  render()
end)

noctalia.state.watch("panel_style", function(value)
  style = value or {}
  render()
end)

function onOpen()
  isOpen = true
  render()
end

function onClose()
  isOpen = false
  hover = {}
end
