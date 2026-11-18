# Claude Usage

<p align="center"><img src="docs/example-2.png" alt="Claude Usage in the Noctalia bar" height="44"></p>

Shows your Claude Code usage in the bar: how much of the 5-hour (and optionally weekly) limit is used, how long
until it resets, and how many tokens you used in that window — as text, a small progress bar or a usage ring.
Details can stay visible, appear only when usage is high, or appear only on hover. Click to refresh.

## Plugin

| Field | Value |
| --- | --- |
| ID | `seo/claude-usage` |
| Entries | Bar widget: `bar`; bar widget: `icon`; service: `poller` |

## Requirements

Install `curl` and `jq` on `PATH`. Claude Code must be logged in on this machine
(`~/.claude/.credentials.json`, or `$CLAUDE_CONFIG_DIR/.credentials.json`).

## Usage

Add **Claude Usage** to a bar in **Settings → Bar** and pick the entry:

- **`bar`** — capsule with an optional icon or usage ring, usage %, progress bar, time to reset and tokens.
  With **Show details** set to *Only on hover* it shrinks to the icon or ring until you point at it. Click
  refreshes now (or runs your `click_command`).
- **`icon`** — compact variant: only an icon or a usage ring, everything else in the tooltip. Click runs
  `command` (default `alacritty -e claude`).

The `poller` service starts with the plugin and refreshes every `refresh_minutes`; all widgets share its result.

### Examples

| Look | Settings |
| --- | --- |
| <img src="docs/example-1.png" alt="Defaults" height="34"> | Defaults |
| <img src="docs/example-2.png" alt="Star icon" height="34"> | `logo = star`, `show_prefix = true` |
| <img src="docs/example-3.png" alt="Both windows" height="34"> | `logo = glyph`, `show_prefix = true`, `window = both`, `show_reset = false`, `show_tokens = false` |
| <img src="docs/example-4.png" alt="Verbose and bold" height="34"> | `logo = star`, `reset_format = verbose`, `token_format = full`, `font_weight = bold` |
| <img src="docs/example-5.png" alt="Critical color" height="34"> | `show_prefix = true`, `show_tokens = false`, `critical_at = 5` |
| <img src="docs/example-6.png" alt="Usage ring" height="34"> | `logo = ring`, `separator = dot`, `dim_extras = true` |
| <img src="docs/example-7.png" alt="Progress bar" height="34"> | `show_bar = true`, `percent_mode = left`, `show_tokens = false` |
| <img src="docs/example-8.png" alt="Ring until hovered" height="34"> | `display_mode = hover`, `logo = ring` (at rest) |
| <img src="docs/example-9.png" alt="Quiet until high" height="34"> | `display_mode = important`, `logo = star` |
| <img src="docs/example-10.png" alt="Any glyph" height="34"> | `logo = glyph`, `glyph = bolt`, `separator = bar` |

## Settings

Plugin:

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `refresh_minutes` | `int` | `5` | How often the usage API is queried (1–120 minutes). |

`bar` widget:

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `window` | `select` | `five_hour` | Which limit to show: `five_hour`, `weekly` or `both`. |
| `display_mode` | `select` | `always` | When details (time, tokens, bar) show: `always`, `important` (at or above `warn_at`) or `hover` (otherwise only the icon or ring, or the percentage when there is no icon). |
| `logo` | `select` | `none` | `none`, `glyph`, `star` (bundled `assets/star.svg`), `custom` or `ring` (usage ring). |
| `glyph` | `glyph` | `brain` | Icon used when `logo = glyph`. |
| `logo_path` | `file` | `""` | SVG / PNG used when `logo = custom`; empty means `logo.svg` in the plugin folder. |
| `icon_size` | `int` | `18` | Icon and ring size, in pixels (10–40). |
| `show_percent` | `bool` | `true` | Show the usage percentage. |
| `percent_mode` | `select` | `used` | `used` (`22%`) or `left` (`78% left`). |
| `show_prefix` | `bool` | `false` | Prefix the percentage with `5h` / `7d`. |
| `show_bar` | `bool` | `false` | Small progress bar after the percentage. |
| `bar_width` | `int` | `32` | Progress bar width, in pixels (12–120). |
| `gauge_mode` | `select` | `left` | What the progress bar and the ring fill with: `left` or `used`. |
| `show_reset` | `bool` | `true` | Show the time left until the window resets. |
| `reset_format` | `select` | `compact` | `compact` (`1:05`, hours:minutes) or `verbose` (`1h 5m`). |
| `ready_text` | `string` | `ready` | Shown instead of the countdown when no window is running. |
| `show_tokens` | `bool` | `true` | Show tokens used in the window. |
| `include_cache_read` | `bool` | `false` | Add prompt-cache reads to the token count. They are cheap but numerous, so the number gets much larger. The tooltip always shows them separately. |
| `token_format` | `select` | `short` | `short` (`290k`) or `full` (`289731`). |
| `separator` | `select` | `none` | Between items: `none`, `dot` (`·`), `bar` (`\|`) or `slash` (`/`). |
| `dim_extras` | `bool` | `false` | Time and tokens in a muted color; only the percentage keeps the usage color. |
| `gap` | `int` | `4` | Spacing between items, in pixels (0–24). |
| `font_weight` | `select` | `medium` | `medium` or `bold`. |
| `color_by_usage` | `bool` | `true` | Use the warning / critical colors above the thresholds. |
| `warn_at` | `int` | `70` | Warning threshold, in percent. |
| `critical_at` | `int` | `90` | Critical threshold, in percent. |
| `color` | `color` | `on_surface` | Normal text color (color role or hex). |
| `warn_color` | `color` | `tertiary` | Text color above `warn_at`. |
| `critical_color` | `color` | `error` | Text color above `critical_at`. |
| `click_command` | `string` | `""` | Shell command run on click; empty refreshes now. |

Dependent settings (glyph, image, formats, thresholds…) only appear in the settings window when they apply.

`icon` widget:

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `logo` | `select` | `glyph` | `glyph`, `star`, `custom` or `ring` (5-hour usage ring). |
| `glyph` | `glyph` | `brain` | Icon used when `logo = glyph`. |
| `logo_path` | `file` | `""` | SVG / PNG used when `logo = custom`; empty means `logo.svg` in the plugin folder. |
| `size` | `int` | `20` | Icon size, in pixels (10–40). |
| `command` | `string` | `alacritty -e claude` | Command run on click. |

## IPC

Refresh immediately:

```sh
noctalia msg plugin seo/claude-usage:poller all refresh
```

## Notes

- **Network:** one HTTPS request per refresh to `https://api.anthropic.com/api/oauth/usage`, authenticated with
  the OAuth token Claude Code stores in `~/.claude/.credentials.json`. The token is only read, never written or
  refreshed. If it has expired, the tooltip says so; using Claude Code once refreshes it.
- **Files read:** `~/.claude/.credentials.json` and transcripts in `~/.claude/projects/**/*.jsonl` modified in the
  last 8 days (to count tokens: input + output + cache-creation, deduplicated per message; cache reads are
  counted separately and added only with `include_cache_read`).
- **Processes:** the poller runs `fetch.sh` directly (no shell), which runs `curl`, `jq`, `find`, `xargs` and
  `grep`. Clicking the `bar` widget refreshes through the plugin's shared state without spawning anything, unless
  you set `click_command`; the `icon` widget runs `command`.
- **Files written:** the usage ring is drawn as small SVG files cached in the plugin's data directory
  (`noctalia.pluginDataDir()`), one per percentage and color. `ui.ring` would avoid this but needs plugin API 55.
- Uses an undocumented endpoint that may change without notice. Not affiliated with or endorsed by Anthropic.
