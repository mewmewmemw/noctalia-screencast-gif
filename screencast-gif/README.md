# Screencast GIF — Noctalia plugin

A toggle-style screen recorder for [Hyprland](https://hyprland.org/) /
[Sway](https://swaywm.org/) / any wlroots-based Wayland compositor that:

- selects a screen region with `slurp`,
- records it with `wf-recorder`,
- converts the result to an animated `.gif` with `gifski`,
- copies the GIF straight to the Wayland clipboard (as `image/gif`),
- saves the file alongside in a configurable directory,
- shows a **red pill in the [noctalia](https://noctalia.dev/) bar** while
  recording is active, and turns back to neutral when the GIF is ready.

Press your hotkey once to pick a region and start recording, press again to
stop and grab the GIF — both from the keyboard and by clicking the pill.

## Why

Most existing Wayland screen recorders either give you a `.mp4` or open a GUI.
There was no off-the-shelf "press hotkey, draw region, get a GIF in clipboard,
with a visible recording indicator" tool — so this plugin glues the best
existing pieces (`wf-recorder` + `gifski`) together and exposes the whole
thing through a noctalia bar widget.

## Requirements

| Tool | Purpose | Arch package |
|---|---|---|
| [`wf-recorder`](https://github.com/ammen99/wf-recorder) | screen capture | `wf-recorder` |
| [`gifski`](https://gif.ski/) | high-quality GIF encoding | `gifski` |
| [`slurp`](https://github.com/emersion/slurp) | region selection | `slurp` |
| `ffmpeg` | extract frames from the captured mp4 | `ffmpeg` |
| `wl-clipboard` | clipboard plumbing (`wl-copy`) | `wl-clipboard` |
| `flock` (util-linux) | invocation locking | `util-linux` |
| `notify-send` | start/end notifications (optional) | `libnotify` |
| [noctalia-shell](https://noctalia.dev/) ≥ 4.6.6 | the shell hosting the bar widget | `noctalia-shell` |

```bash
sudo pacman -S --needed wf-recorder gifski slurp ffmpeg wl-clipboard libnotify
```

The plugin works on any wlroots compositor; the noctalia bar widget obviously
requires noctalia.

## Installation

```bash
git clone https://github.com/mewmewmemw/noctalia-screencast-gif \
    ~/.config/noctalia/plugins/screencast-gif
```

Then enable the plugin in noctalia's plugin manager (or set
`states["screencast-gif"].enabled = true` in `~/.config/noctalia/plugins.json`
and restart noctalia), and add the **Screencast GIF** widget to your bar
through noctalia's bar settings.

## Hyprland keybind

Bind a hotkey to invoke the plugin's IPC `toggle` (recommended — uses the
plugin's bundled script with your configured FPS / max-time / output dir):

```ini
bind = SHIFT, XF86Cut, exec, qs -c noctalia-shell ipc call plugin:screencast-gif toggle
```

Alternatively, run the script directly (will use defaults unless you override
the env vars yourself):

```ini
bind = SHIFT, XF86Cut, exec, ~/.config/noctalia/plugins/screencast-gif/screencast-gif.sh
```

(Pick whichever modifier+key you prefer; `SHIFT, XF86Cut` happens to be
`Fn+Shift+F10` on the maintainer's laptop.)

## Settings

Configurable via the plugin's settings panel in noctalia:

| Setting | Default | Notes |
|---|---|---|
| Output directory | `~/Screenshots` | Tilde is expanded. Created if missing. |
| Frame rate | `20` | 15–25 is a good balance between smoothness and file size. |
| Auto-stop after (seconds) | `120` | Safety net so you don't leave it recording forever. `0` disables. |

The settings are passed to the script via environment variables (`FPS`,
`MAX_SECS`, `OUTDIR`), so direct invocations of the script can override them
the same way.

## How it works

`screencast-gif.sh` is a toggle:

- **First call** acquires a lock, asks `slurp` for a region, rounds the
  coordinates to the nearest even values (h264 + yuv420p requires this), and
  starts `wf-recorder --no-dmabuf -D --pixel-format yuv420p` writing to a
  per-invocation directory under `/tmp/screencast-gif/`. The PID and that
  directory are written to `/tmp/screencast-gif.pid`. A backgrounded watchdog
  re-invokes the script after `MAX_SECS` to enforce the auto-stop.
- **Second call** sees the live PID in the pidfile, releases the lock
  immediately (so a third invocation can start a brand-new recording while
  conversion is still running), sends `SIGINT` to `wf-recorder`, waits for it
  to flush the mp4, then runs `ffmpeg` to extract frames and `gifski` to
  encode the GIF, copies it to the clipboard, and saves it to `OUTDIR`.

The QML side (`Main.qml`) polls `/tmp/screencast-gif.pid` once a second to
keep the bar widget's `recordingActive` flag in sync. Cheap, robust, and
independent of the daemon's notification quirks.

### Notable quirks handled

- **`Failed to copy frame too many times` from wf-recorder** — fixed by
  passing `--no-dmabuf` (forces CPU buffer copy instead of DMA-BUF).
- **Single-frame GIFs from static regions** — wf-recorder defaults to
  damage-tracking and only requests new frames when the screen changes,
  which collapses a quiet recording to a single frame. `-D` /
  `--no-damage` forces continuous capture.
- **Odd coordinates from slurp on fractional-scale monitors** — rounded to
  even values before being passed to `wf-recorder` (h264 + yuv420p won't
  encode odd dimensions).
- **`flock` leaked into the recording subprocess** — every backgrounded
  child closes inherited fds before exec'ing, so the recorder doesn't
  pin the lock and outlive its purpose.
- **Lock held during slow GIF conversion** — released as soon as the
  recorder is signalled, so a new recording can start immediately.
- **`wl-copy` keeping test harnesses alive** — `wl-copy` daemonises to
  serve the clipboard contents until they're replaced. The daemon
  inherits all parent fds; in particular, when the script is invoked
  from a test harness like `bats`, the daemon would keep the harness's
  output pipe open and prevent it from reaching EOF for the full
  watchdog duration. The script strips inherited fds before invoking
  `wl-copy`.

## Advanced

State file paths can be overridden via env vars, primarily so the test
suite (and any concurrent automation) can stay isolated from a live
recording:

| Env var | Default |
|---|---|
| `SCREENCAST_GIF_PIDFILE` | `/tmp/screencast-gif.pid` |
| `SCREENCAST_GIF_LOCKFILE` | `/tmp/screencast-gif.lock` |
| `SCREENCAST_GIF_WORKDIR` | `/tmp/screencast-gif` |
| `SCREENCAST_GIF_LOG` | `/tmp/screencast-gif.log` |
| `SCREENCAST_GIF_REGION` | (unset — fall back to `slurp`) |

The bar widget's polling assumes the defaults, so changing the pidfile
location will hide ongoing recordings from the bar pill — only do it
for tests or one-off scripted recordings.

## Tests

```bash
sudo pacman -S bats shellcheck     # one-time
bats tests/                        # full suite
./tests/lint.sh                    # shellcheck only
```

The suite is built on [bats-core][bats] and covers core lifecycle, region
rounding, concurrency, slurp cancellation, the auto-stop watchdog, env-var
overrides, and recovery from stale state. Each test runs in an isolated
tmpdir, so it's safe to run while noctalia and the plugin are live in your
session — your real recordings and `~/Screenshots` are not touched.

`tests/README.md` has the full breakdown. CI runs `shellcheck` on every
push; the bats suite itself needs a real wlroots Wayland session and is
local-only.

[bats]: https://github.com/bats-core/bats-core

## License

MIT — see [LICENSE](LICENSE).

## Credits

- [wf-recorder](https://github.com/ammen99/wf-recorder) by Ilia Bozhinov
- [gifski](https://github.com/ImageOptim/gifski) by Kornel Lesiński
- [noctalia-shell](https://github.com/noctalia-dev/noctalia-shell) and its
  plugin system, particularly the
  [screen-shot-and-record](https://github.com/noctalia-dev/noctalia-plugins/tree/main/screen-shot-and-record)
  plugin which served as the reference for the bar-widget recording-state
  pattern.
