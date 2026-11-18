<div align="center">

<img src="claude-usage/docs/banner.png" alt="Claude Limits — Claude Code limits in your Noctalia bar" width="720">

<br>

[![Noctalia plugin](https://img.shields.io/badge/Noctalia-plugin-8b7cf6?style=flat-square)](https://github.com/noctalia-dev/noctalia)
[![Plugin API](https://img.shields.io/badge/plugin__api-43-5b8def?style=flat-square)](https://docs.noctalia.dev/noctalia/plugins/development/)
[![Tested on Niri](https://img.shields.io/badge/tested%20on-Niri-46a58f?style=flat-square)](https://github.com/YaLTeR/niri)
[![License: MIT](https://img.shields.io/badge/license-MIT-e0a458?style=flat-square)](LICENSE)

**See how much of your Claude Code limit is left — without leaving your desktop.**

[Install](#-install) · [Examples](#-examples) · [Settings](#%EF%B8%8F-settings) · [How it works](#-how-it-works)

</div>

---

## ✨ Features

- **5-hour and weekly limits** — usage percentage straight from your Claude account.
- **Time to reset** — a live countdown (`1:05` or `1h 5m`), or `ready` when no window is running.
- **Tokens used** — counted locally from your Claude Code transcripts (`290k` or `289731`), optionally including prompt-cache reads.
- **Text, bar or ring** — show numbers, a small progress bar, or a usage ring that empties as you go.
- **Details on hover** — keep just an icon or the ring in the bar and reveal the numbers when you point at it,
  or show them only when usage gets high.
- **What it would cost** — optional estimate of your tokens at API prices, in the bar, tooltip and panel.
- **Colors that warn you** — switches to warning / critical colors above the thresholds you pick.
- **Make it yours** — any glyph from the icon set or your own image, separators, dimmed extras, percent used or left,
  icon size, spacing, font weight and colors.
- **Click for more** — a panel with both limits, one-click Claude Code launch with a model of your choice
  (default, Opus, Sonnet, Haiku; new session, continue or resume), token graphs for the last 24 hours and
  7 days, and tokens per model.
- **Speaks your language** — settings, tooltip and bar text in all 29 languages Noctalia supports.
- **Light on resources** — one background poller, no matter how many monitors or bars.

## 📸 Examples

Same widget, different settings:

<table>
  <tr>
    <td align="center"><img src="claude-usage/docs/example-6.png" alt="Default look" height="40"></td>
    <td><b>Defaults</b><br>usage ring · usage · time to reset · tokens</td>
  </tr>
  <tr>
    <td align="center"><img src="claude-usage/docs/example-1.png" alt="Plain text" height="40"></td>
    <td><b>Plain text</b><br><code>logo = none</code>, <code>separator = none</code>, <code>dim_extras = false</code></td>
  </tr>
  <tr>
    <td align="center"><img src="claude-usage/docs/example-2.png" alt="Star icon and 5h label" height="40"></td>
    <td><b>Star icon + label</b><br><code>logo = star</code>, <code>show_prefix = true</code></td>
  </tr>
  <tr>
    <td align="center"><img src="claude-usage/docs/example-3.png" alt="Both windows" height="40"></td>
    <td><b>Both windows, compact</b><br><code>logo = glyph</code>, <code>window = both</code>, <code>show_reset = false</code>, <code>show_tokens = false</code></td>
  </tr>
  <tr>
    <td align="center"><img src="claude-usage/docs/example-4.png" alt="Verbose and bold" height="40"></td>
    <td><b>Verbose & bold</b><br><code>reset_format = verbose</code>, <code>token_format = full</code>, <code>font_weight = bold</code></td>
  </tr>
  <tr>
    <td align="center"><img src="claude-usage/docs/example-5.png" alt="Critical color" height="40"></td>
    <td><b>Critical color</b><br>shown above <code>critical_at</code> (here forced with <code>critical_at = 5</code>)</td>
  </tr>
  <tr>
    <td align="center"><img src="claude-usage/docs/example-7.png" alt="Progress bar and percent left" height="40"></td>
    <td><b>Progress bar, percent left</b><br><code>show_bar = true</code>, <code>percent_mode = left</code>, <code>show_tokens = false</code></td>
  </tr>
  <tr>
    <td align="center"><img src="claude-usage/docs/example-8.png" alt="Ring only until hovered" height="40"></td>
    <td><b>Ring only — details on hover</b><br><code>display_mode = hover</code>, <code>logo = ring</code></td>
  </tr>
  <tr>
    <td align="center"><img src="claude-usage/docs/example-9.png" alt="Details only when usage is high" height="40"></td>
    <td><b>Quiet until it matters</b><br><code>display_mode = important</code> — time and tokens appear above <code>warn_at</code></td>
  </tr>
  <tr>
    <td align="center"><img src="claude-usage/docs/example-10.png" alt="Any glyph and bar separators" height="40"></td>
    <td><b>Any glyph</b><br><code>logo = glyph</code>, <code>glyph = bolt</code>, <code>separator = bar</code></td>
  </tr>
</table>

## 🚀 Install

**From Noctalia's settings**

1. Open **Settings → Plugins → Add source**.
2. Choose **git** and paste `https://github.com/Seo1323/noctalia-claude-usage`.
3. Switch on **Claude Limits** in the plugin list.
4. Add the **Claude Limits** widget to your bar.

<details>
<summary><b>Or from a terminal</b></summary>

```sh
noctalia msg plugins source add seo git https://github.com/Seo1323/noctalia-claude-usage
noctalia msg plugins enable seo/claude-usage
```

Then add the **Claude Limits** widget to your bar in Noctalia's settings.

</details>

**Requirements:** Noctalia (plugin API 43+), `curl`, `jq`, and Claude Code logged in on this machine.

## ⚙️ Settings

Everything is set per widget in Noctalia's widget settings. The full list with types and defaults is in the
[plugin page](claude-usage/README.md#settings).

| Group | What you can change |
| --- | --- |
| **Content** | Limit window (5h / weekly / both), usage % (used or left), `5h` / `7d` labels, progress bar, time to reset, tokens (with or without cache reads), cost at API prices |
| **When** | Details always, only when usage is high, or only on hover (animated, adjustable speed) |
| **Format** | Reset time `1:05` or `1h 5m`, the text shown when ready, tokens `290k` or `289731`, separators |
| **Icon** | None, any glyph, bundled star, custom image or usage ring; icon size |
| **Look** | Spacing, font weight, dimmed time and tokens, translucent panel with adjustable opacity |
| **Colors** | Color by usage, warning / critical thresholds, text / warning / critical colors |
| **Format** | Decimal places in percentages (0–2) |
| **Behaviour** | Refresh interval, left click opens the panel / runs a command / refreshes, right click refreshes, the command the panel starts Claude Code with |

### Custom icon

Set **Icon** to *Custom image* and pick an SVG or PNG with the file browser (or drop it in the plugin folder as
`logo.svg`). Light, single-color images blend best with the other bar icons.

## 🔍 How it works

- `fetch.sh` reads the OAuth token Claude Code already stores in `~/.claude/.credentials.json` and asks
  `api.anthropic.com/api/oauth/usage` for utilization and reset times. It never writes or refreshes the token.
- Token counts come from your local transcripts in `~/.claude/projects` (input + output + cache-creation
  tokens, deduplicated per message, inside the current window). Prompt-cache reads are counted separately; turn on
  **Include cache reads** to add them.
- That one request is the only network call. Nothing else leaves your machine.

If the token has expired, the tooltip says so — use Claude Code once and it refreshes.

## 🌍 Languages

The widget follows Noctalia's language setting. English and Polish are maintained by the author; the other
27 translations were machine-translated and are waiting for native speakers — fixes to
[`claude-usage/translations`](claude-usage/translations) are very welcome.

## 🔗 See also

[**Claude Code Usage**](https://github.com/noctalia-dev/community-plugins/tree/main/claudecode) (`jrohland/claudecode`)
is another Noctalia plugin for Claude Code usage, with a richer dashboard (costs, activity charts, profiles). Claude
Limits was written independently and takes a different direction:

- **Highly configurable, made to fit your bar** — almost every part can be switched on or off and
  restyled: icon (none, any glyph, bundled star, your own image or a usage ring), percent used or left with 0–2
  decimals, progress bar, time format, token format, separators, dimmed extras, spacing, font weight and colors.
- **Small by default** — one compact capsule; details can stay visible, appear only when usage is high, or slide
  out on hover with an adjustable animation.
- **Lightweight** — a shell script with `curl` + `jq`, no Python; one request per refresh for every bar and monitor.
- **Quick launcher** — the click panel starts Claude Code with a chosen model and session mode.

## 📄 License

[MIT](LICENSE). Not affiliated with or endorsed by Anthropic. Uses an undocumented usage endpoint that may change.
