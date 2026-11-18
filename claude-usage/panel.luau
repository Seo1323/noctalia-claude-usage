--!nonstrict
-- Click panel: both limits, launching Claude Code with a chosen model and mode,
-- token graphs (last 24 h / 7 days) and tokens per model.

local S = require("./shared.luau")

local MODELS = { "", "opus", "sonnet", "haiku" } -- "" = Claude Code's default model
local MODES = { "", "--continue", "--resume" } -- new session, continue last, pick a session

local snapshot = noctalia.state.get("usage")
local style = noctalia.state.get("panel_style") or {} -- set by the bar widget: { translucent, opacity, resume }
local isOpen = false
local model, mode = 1, 1
local tableWindow = "five" -- five | weekly
local hover = {} -- graph id -> hovered bucket index

local function muted(text)
  return ui.label({ text = text, color = "on_surface_variant", fontSize = 12 })
end

local function heading(text)
  return ui.label({ text = text, fontWeight = "bold" })
end

local function launch()
  local parts = { S.text("launch_command", "alacritty -e claude") }
  if MODELS[model] ~= "" then parts[#parts + 1] = "--model " .. MODELS[model] end
  if MODES[mode] ~= "" then parts[#parts + 1] = MODES[mode] end
  S.spawn(table.concat(parts, " "))
  panel.close()
end

-- Resumes a session in the folder it was started in (Claude Code keeps sessions per folder).
local function resume(session)
  local id = tostring(session.id or "")
  if not id:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then return end
  local parts = { S.text("launch_command", "alacritty -e claude") }
  if MODELS[model] ~= "" then parts[#parts + 1] = "--model " .. MODELS[model] end
  parts[#parts + 1] = "--resume " .. id
  S.spawnIn(session.cwd, table.concat(parts, " "))
  panel.close()
end

local function folderName(path)
  if path:match("^/home/[^/]+/?$") or path == "/root" then return "~" end
  return path:match("([^/]+)/*$") or path
end

local render

local function limitRow(label, win)
  local time = S.verbose(win.reset) or noctalia.tr("panel.no_reset")
  return ui.column({ gap = 4 }, {
    ui.row({ justify = "space_between" }, {
      ui.label({ text = `{label}  {S.num(win.pct)}%`, fontWeight = "medium", color = S.colorFor(win.pct, S.DEFAULT_COLORS) }),
      muted(noctalia.tr("panel.resets_in", { time = time })),
    }),
    ui.progress({ progress = math.clamp((win.pct or 0) / 100, 0, 1), fill = S.colorFor(win.pct, S.DEFAULT_COLORS), height = 6, radius = 3 }),
  })
end

-- Line graph of token counts with a hover readout; `unit` is the bucket length label key.
local function graph(id, title, values, ago)
  local max = 0
  for _, v in values do max = math.max(max, v) end
  local norm = {}
  for i, v in values do norm[i] = if max > 0 then v / max else 0 end
  local i = hover[id]
  local readout = if i
    then `{S.tokens(values[i])} · {ago(#values - i)}`
    else noctalia.tr("panel.peak", { tokens = S.tokens(max) })
  return ui.column({ gap = 4 }, {
    ui.row({ justify = "space_between" }, { ui.label({ text = title, fontWeight = "medium" }), muted(readout) }),
    ui.graph({
      values = norm, color = "primary", fillOpacity = 0.25, lineWidth = 2, height = 56,
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
  local total = 0
  for _, m in list do total += m.tokens end
  local rows = {}
  for _, m in list do
    rows[#rows + 1] = ui.column({ gap = 3 }, {
      ui.row({ justify = "space_between" }, {
        ui.label({ text = S.modelName(m.model) }),
        muted(noctalia.tr("panel.model_tokens", { tokens = S.tokens(m.tokens), messages = m.messages, cache = S.tokens(m.cache_read) })
          .. (if S.cost({ m }) then " · " .. S.money(S.cost({ m })) else "")),
      }),
      ui.progress({ progress = if total > 0 then m.tokens / total else 0, fill = "secondary", height = 4, radius = 2 }),
    })
  end
  if #rows == 0 then rows[1] = muted(noctalia.tr("panel.no_models")) end
  local function tab(key, text)
    return ui.button({
      text = text, controlSize = "sm", variant = if tableWindow == key then "primary" else "ghost",
      onClick = function() tableWindow = key; render() end,
    })
  end
  return ui.column({ gap = 8 }, {
    ui.row({ justify = "space_between", align = "center" }, {
      heading(noctalia.tr("panel.by_model")),
      ui.row({ gap = 4 }, { tab("five", "5h"), tab("weekly", "7d") }),
    }),
    ui.column({ gap = 8 }, rows),
    if S.cost(list) then muted(noctalia.tr("panel.cost_total", { cost = S.money(S.cost(list)) })) else nil,
  })
end

function render()
  if not isOpen then return end
  local data = snapshot and snapshot.data
  local children = {
    ui.row({ justify = "space_between", align = "center" }, {
      ui.label({ text = "Claude Code", fontWeight = "bold", fontSize = 16 }),
      ui.row({ gap = 4 }, {
        ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = noctalia.tr("panel.refresh"),
          onClick = function() noctalia.state.set("refresh", noctalia.nowMs()) end }),
        ui.button({ glyph = "settings", variant = "ghost", controlSize = "sm", tooltip = noctalia.tr("panel.settings"),
          onClick = function() noctalia.openSettings() end }),
      }),
    }),
  }
  local function add(node) children[#children + 1] = node end

  if data then
    local w = S.windows(data, false)
    add(limitRow("5h", w.five))
    add(limitRow("7d", w.week))
  else
    add(muted(S.tooltip(snapshot)))
  end

  add(ui.separator({}))
  add(heading(noctalia.tr("panel.launch")))
  add(ui.select({
    options = { noctalia.tr("panel.model_default"), "Opus", "Sonnet", "Haiku" }, selectedIndex = model - 1,
    onChange = function(i) model = tonumber(i) + 1 end,
  }))
  add(ui.select({
    options = { noctalia.tr("panel.mode_new"), noctalia.tr("panel.mode_continue"), noctalia.tr("panel.mode_resume") },
    selectedIndex = mode - 1,
    onChange = function(i) mode = tonumber(i) + 1 end,
  }))
  add(ui.button({ text = noctalia.tr("panel.start"), glyph = "terminal-2", variant = "primary", onClick = launch }))

  local sessions = if style.resume == false then {} else (data and data.recent_sessions or {})
  if #sessions > 0 then
    add(ui.separator({}))
    add(heading(noctalia.tr("panel.resume")))
    for _, s in sessions do
      local prompt = tostring(s.prompt or "")
      if utf8.len(prompt) and utf8.len(prompt) > 38 then prompt = prompt:sub(1, utf8.offset(prompt, 38) - 1) .. "…" end
      add(ui.button({
        text = `{folderName(s.cwd)} · {S.ago(s.t)}` .. (if prompt ~= "" then ` — {prompt}` else ""),
        glyph = "history", variant = "outline", contentAlign = "start",
        onClick = function() resume(s) end,
      }))
    end
  end

  if data and data.hourly then
    add(ui.separator({}))
    add(graph("hourly", noctalia.tr("panel.last_24h"), data.hourly, function(n) return noctalia.tr("panel.hours_ago", { n = n }) end))
    add(graph("daily", noctalia.tr("panel.last_7d"), data.daily, function(n) return noctalia.tr("panel.days_ago", { n = n }) end))
    add(ui.separator({}))
    add(modelTable(data))
  end

  -- Translucency goes into the background fill only, so the content stays fully opaque.
  local fill = if style.translucent then string.format("surface/%.2f", style.opacity or 0.85) else "surface"
  panel.render(ui.column({ padding = 16, gap = 12, fill = fill, radius = 12 }, children))
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
