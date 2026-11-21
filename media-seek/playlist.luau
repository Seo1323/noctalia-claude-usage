--!nonstrict
-- Round bar button: circled plus, or a green check when the playing track is already on one of your
-- playlists. Click opens the playlist menu. The capsule adds `capsule_padding` on both sides, so a content
-- width of (capsule height - 2 * padding) makes it a circle. shortcut: sizes come from config, not measured.
local function num(key, default) return tonumber(noctalia.getSetting(key)) or default end
local THICK = num("bar.default.thickness", 40) * num("bar.default.capsule_thickness", 0.8)
local SIZE = math.max(12, math.floor(THICK - 2 * num("bar.default.capsule_padding", 8)))
local GREEN = "#1ed760" -- Spotify green

local m, any = noctalia.state.get("media"), noctalia.state.get("in_any")

local function render()
  local p = m and m.player
  local id = p and tostring(p.trackid):match("^/com/spotify/track/(%w+)$")
  local added = id ~= nil and any ~= nil and any.track == id and any.value == true
  barWidget.render(ui.row({ width = SIZE, height = SIZE, align = "center", justify = "center" }, {
    ui.glyph({ name = if added then "circle-check-filled" else "circle-plus", size = SIZE, color = if added then GREEN else "on_surface" }),
  }))
  barWidget.setTooltip(if added then "Na playliście" else "Dodaj do playlisty")
end

noctalia.state.watch("media", function(v) m = v; render() end)
noctalia.state.watch("in_any", function(v) any = v; render() end)
function onClick() noctalia.togglePanel("seo/media-seek:playlists") end
function update() noctalia.setUpdateInterval(60000); render() end
render()
