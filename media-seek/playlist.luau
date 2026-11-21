--!nonstrict
-- Bar button: opens the "add to playlist" panel for the track that is playing.
-- The bar capsule adds `capsule_padding` on both sides, so a content width of (capsule height - 2 * padding)
-- makes the whole capsule a circle. shortcut: sizes are read from the shell config, not measured.
local function num(key, default) return tonumber(noctalia.getSetting(key)) or default end
local THICK = num("bar.default.thickness", 40) * num("bar.default.capsule_thickness", 0.8)
local SIZE = math.max(12, math.floor(THICK - 2 * num("bar.default.capsule_padding", 8)))

function onClick() noctalia.togglePanel("seo/media-seek:playlists") end
function update()
  barWidget.render(ui.row({ width = SIZE, height = SIZE, align = "center", justify = "center" }, {
    ui.glyph({ name = "circle-plus", size = SIZE }),
  }))
  barWidget.setTooltip("Dodaj do playlisty")
end
update()
