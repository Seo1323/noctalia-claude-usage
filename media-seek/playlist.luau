--!nonstrict
-- Bar button: circled plus, or a green check when the playing track is already on one of your playlists.
-- Click opens the playlist menu. No capsule (set per widget in settings: capsule_opacity / capsule_border_width = 0).
local SIZE = 22 -- typical bar glyph size
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
