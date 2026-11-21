--!nonstrict
-- Bar button: opens the "add to playlist" panel for the track that is playing.
function onClick() noctalia.togglePanel("seo/media-seek:playlists") end
function update() barWidget.render(ui.glyph({ name = "circle-plus" })); barWidget.setTooltip("Dodaj do playlisty") end
update()
