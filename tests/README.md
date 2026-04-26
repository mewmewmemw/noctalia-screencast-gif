# Tests

End-to-end tests for `screencast-gif.sh`, written for [bats-core][bats].

## Why bats

Each test gets its own isolated tmpdir for PID, lock, work, log, and output
paths, so the suite never touches the user's real `/tmp/screencast-gif.*`
state or `~/Screenshots/`. That means it's safe to run while noctalia and the
plugin are live in your session — your actual recordings won't be killed and
your Screenshots folder won't be polluted.

## Setup

```bash
sudo pacman -S bats shellcheck   # Arch
# Debian/Ubuntu: sudo apt install bats shellcheck
```

The tests also need the same runtime tools as the plugin itself:
`wf-recorder`, `gifski`, `slurp`, `ffmpeg` (for `ffprobe`), `wl-clipboard`,
`file`. They must run from inside an actual wlroots Wayland session — bats
itself can't simulate one.

## Running

```bash
# all tests
bats tests/

# one specific test
bats tests/screencast-gif.bats -f "auto-stop watchdog"

# lint only
./tests/lint.sh
```

## What's covered

| Area | Tests |
|---|---|
| Core lifecycle | start → record → stop → GIF in clipboard; valid animated GIF with frames |
| Region handling | odd coords rounded to even; even coords passed through |
| Concurrency | two simultaneous starts (lock); immediate restart during conversion |
| Slurp | cancellation; mocked region |
| Watchdog | auto-stop after MAX_SECS; MAX_SECS=0 disables |
| Env overrides | FPS reflected in output; OUTDIR created; tilde expansion |
| State isolation | stale PIDFILE with dead PID falls through to START |

## CI

The shellcheck pass runs in GitHub Actions on every push. The bats suite
itself is local-only because it needs a real Wayland session — see
`.github/workflows/ci.yml` for context.

[bats]: https://github.com/bats-core/bats-core
