# noctalia-screencast-gif

![Bar widget recording demo](screencast-gif/demo.gif)

Public repository hosting the **Screencast GIF** plugin for
[noctalia-shell](https://github.com/noctalia-dev/noctalia-shell).

The plugin itself lives under [`screencast-gif/`](screencast-gif/) — see its
[README](screencast-gif/README.md) for what it does, requirements, settings,
and the design notes.

## Install

### Option A — add this repo as a custom source in noctalia

Open noctalia's plugin manager, add a custom source pointing at
`https://github.com/mewmewmemw/noctalia-screencast-gif`, then enable
**Screencast GIF** and add the bar widget.

### Option B — manual install

```bash
git clone --depth 1 https://github.com/mewmewmemw/noctalia-screencast-gif /tmp/noctalia-screencast-gif
cp -r /tmp/noctalia-screencast-gif/screencast-gif ~/.config/noctalia/plugins/
```

Then enable it in noctalia (or set
`states["screencast-gif"].enabled = true` in
`~/.config/noctalia/plugins.json`) and add the **Screencast GIF** widget to
your bar.

### Hyprland keybind

```ini
bind = SHIFT, XF86Cut, exec, qs -c noctalia-shell ipc call plugin:screencast-gif toggle
```

(Pick whatever modifier+key you like. `SHIFT, XF86Cut` is `Fn+Shift+F10` on
the maintainer's laptop.)

## Repository layout

```
.
├── screencast-gif/          # the plugin itself (this is what gets installed)
│   ├── manifest.json
│   ├── README.md            # plugin docs, requirements, settings, design
│   ├── preview.png          # 16:9 thumbnail used by noctalia's plugin gallery
│   ├── Main.qml             # IPC + recording-state polling
│   ├── BarWidget.qml        # bar pill (red = recording)
│   ├── Settings.qml         # plugin settings UI
│   └── screencast-gif.sh    # the wf-recorder + gifski + wl-copy pipeline
├── tests/                   # bats-core suite + shellcheck driver
│   ├── screencast-gif.bats
│   ├── lint.sh
│   └── README.md
├── registry.json            # noctalia plugin registry (single entry)
└── .github/workflows/ci.yml # shellcheck on every push
```

## Tests

```bash
sudo pacman -S bats shellcheck     # one-time
bats tests/                        # full suite (15 cases, ~40s)
./tests/lint.sh                    # shellcheck only
```

The bats suite drives a real `wf-recorder + slurp + wl-copy` pipeline and
therefore needs a live wlroots Wayland session. CI only runs the lint step
for that reason. See [tests/README.md](tests/README.md).

## Contributing

Bug reports and PRs welcome. The code is small (one shell script + four
QML files). The plugin docs in
[`screencast-gif/README.md`](screencast-gif/README.md#how-it-works) cover
the "How it works" and "Notable quirks handled" sections — read those before
opening a PR that touches the recorder pipeline.

## License

[MIT](LICENSE).
