--!nonstrict
-- Hover card under the bar: current position, draggable seek bar, total length.
local m = noctalia.state.get("media")
local isOpen, dragging = false, nil

local function fmt(us)
  local s = math.floor((us or 0) / 1e6)
  return string.format("%d:%02d", s // 60, s % 60)
end

local function render()
  if not isOpen then return end
  local p = m and m.player
  if not p then return end
  local pos = dragging or p.position
  local frac = if p.length > 0 then math.clamp(pos / p.length, 0, 1) else 0
  local slider = if p.canSeek and p.length > 0 then
    ui.slider({ value = frac, min = 0, max = 1,
      onChange = function(v) dragging = v * p.length; render() end,
      onChangeEnd = function(v)
        dragging = nil
        noctalia.state.set("cmd", { kind = "seek", bus = p.bus, arg = p.trackid, arg2 = tostring(math.floor(v * p.length)), n = noctalia.nowMs() })
      end })
    else ui.progress({ progress = frac, height = 6, radius = 3 })
  panel.render(ui.column({ padding = 12, gap = 4,
    onPointerMove = function() noctalia.state.set("hover_keep", true) end,
    onPointerLeave = function() noctalia.state.set("hover_keep", false) end,
  }, {
    slider,
    ui.row({ justify = "space_between" }, {
      ui.label({ text = fmt(pos), fontSize = 11, color = "on_surface_variant" }),
      ui.label({ text = fmt(p.length), fontSize = 11, color = "on_surface_variant" }),
    }),
  }))
end

noctalia.state.watch("media", function(v) m = v; if not dragging then render() end end)
function onOpen() isOpen = true; noctalia.state.set("hover_open", true); render() end
function onClose() isOpen = false; dragging = nil; noctalia.state.set("hover_open", false); noctalia.state.set("hover_keep", false) end
