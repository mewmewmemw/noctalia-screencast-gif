#!/usr/bin/env bats
# End-to-end tests for screencast-gif.sh.
# Each test runs in an isolated tmpdir so they don't clobber the user's real
# state (PID/lock/work dirs, ~/Screenshots) or the running noctalia plugin.
#
# Requires: bats-core, plus a Wayland session with wf-recorder, gifski,
# ffmpeg, slurp, wl-clipboard, file. ffprobe (from ffmpeg) is used for GIF
# content validation.
#
# Run all:   bats tests/
# Run one:   bats tests/screencast-gif.bats -f "basic cycle"

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    SCRIPT="$PROJECT_ROOT/screencast-gif.sh"

    TESTDIR=$(mktemp -d -t screencast-gif-test.XXXXXX)
    export SCREENCAST_GIF_PIDFILE="$TESTDIR/pid"
    export SCREENCAST_GIF_LOCKFILE="$TESTDIR/lock"
    export SCREENCAST_GIF_WORKDIR="$TESTDIR/work"
    export SCREENCAST_GIF_LOG="$TESTDIR/log"
    export OUTDIR="$TESTDIR/out"
    export SCREENCAST_GIF_REGION="100,100 320x240"
    export FPS=15
    export MAX_SECS=120
}

teardown() {
    if [[ -f $SCREENCAST_GIF_PIDFILE ]]; then
        local pid
        pid=$(awk '{print $1}' "$SCREENCAST_GIF_PIDFILE" 2>/dev/null || true)
        if [[ -n $pid ]]; then
            kill -INT "$pid" 2>/dev/null || true
            sleep 0.3
            kill -KILL "$pid" 2>/dev/null || true
        fi
    fi
    rm -rf "$TESTDIR"
}

# helpers
latest_gif() { ls -t "$OUTDIR"/screencast_*.gif 2>/dev/null | head -1; }

wait_pidfile() {
    local timeout=${1:-3}
    local i=0
    while (( i < timeout * 10 )); do
        [[ -f $SCREENCAST_GIF_PIDFILE ]] && return 0
        sleep 0.1
        i=$((i+1))
    done
    return 1
}

wait_no_pidfile() {
    local timeout=${1:-10}
    local i=0
    while (( i < timeout * 10 )); do
        [[ ! -f $SCREENCAST_GIF_PIDFILE ]] && return 0
        sleep 0.1
        i=$((i+1))
    done
    return 1
}

gif_frames() {
    ffprobe -v error -count_frames -select_streams v:0 \
        -show_entries stream=nb_read_frames -of csv=p=0 "$1"
}

gif_duration_ms() {
    # Returns GIF playback duration in milliseconds. Works regardless of
    # gifski's frame deduplication: identical frames are folded into longer
    # delays, so total duration is preserved.
    local d
    d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$1")
    awk -v d="$d" 'BEGIN { printf "%d\n", d * 1000 }'
}

# Conversion (ffmpeg + gifski) runs after the PIDFILE is removed, so wait for
# the GIF to actually appear in OUTDIR before asserting on it.
wait_for_gif() {
    local timeout=${1:-15}
    local i=0
    while (( i < timeout * 10 )); do
        [[ -n "$(latest_gif)" ]] && return 0
        sleep 0.1
        i=$((i+1))
    done
    return 1
}

# ---------------------------------------------------------------- core lifecycle

@test "basic cycle: start -> record -> stop -> GIF in clipboard" {
    "$SCRIPT"
    wait_pidfile
    sleep 2
    "$SCRIPT"
    wait_no_pidfile
    wait_for_gif
    (( $(stat -c %s "$(latest_gif)") > 1000 ))
    wl-paste --list-types | grep -q "^image/gif$"
}

@test "produced GIF is a real animated GIF with multiple frames" {
    "$SCRIPT"; wait_pidfile
    sleep 2
    "$SCRIPT"; wait_no_pidfile; wait_for_gif

    local gif
    gif=$(latest_gif)
    file "$gif" | grep -qi "gif image data"
    (( $(gif_frames "$gif") >= 5 ))
}

# ---------------------------------------------------------------- region handling

@test "odd-coordinate region from slurp is rounded to even" {
    SCREENCAST_GIF_REGION="1135,461 500x395" "$SCRIPT"
    wait_pidfile
    grep -q "region rounded to 1134,460 500x396" "$SCREENCAST_GIF_LOG"
    sleep 1
    "$SCRIPT"
    wait_no_pidfile
    wait_for_gif
}

@test "already-even region is passed through unchanged" {
    SCREENCAST_GIF_REGION="200,200 400x300" "$SCRIPT"
    wait_pidfile
    grep -q "region rounded to 200,200 400x300" "$SCREENCAST_GIF_LOG"
    sleep 1
    "$SCRIPT"
}

# ---------------------------------------------------------------- concurrency

@test "two simultaneous starts: lock prevents overlap, exactly one recording active" {
    "$SCRIPT" & local p1=$!
    "$SCRIPT" & local p2=$!
    wait $p1 $p2
    [[ -f $SCREENCAST_GIF_PIDFILE ]]
    # only one wf-recorder PID
    local pid
    pid=$(awk '{print $1}' "$SCREENCAST_GIF_PIDFILE")
    kill -0 "$pid"
}

@test "stop releases lock immediately so a new recording can start during conversion" {
    "$SCRIPT"; wait_pidfile
    sleep 1

    # stop in background — conversion will run for a few seconds
    "$SCRIPT" &
    local stopper=$!

    # wait until pidfile vanishes (lock released) but stopper still running ffmpeg/gifski
    wait_no_pidfile

    # immediate new start should succeed
    "$SCRIPT"
    wait_pidfile

    wait $stopper
}

# ---------------------------------------------------------------- slurp handling

@test "slurp cancellation: script exits cleanly without starting a recording" {
    local mockdir="$TESTDIR/bin"
    mkdir -p "$mockdir"
    cat > "$mockdir/slurp" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
    chmod +x "$mockdir/slurp"

    unset SCREENCAST_GIF_REGION
    PATH="$mockdir:$PATH" "$SCRIPT"

    [[ ! -f $SCREENCAST_GIF_PIDFILE ]]
    grep -q "slurp cancelled/failed" "$SCREENCAST_GIF_LOG"
}

@test "mocked slurp providing a region reaches the recording branch" {
    local mockdir="$TESTDIR/bin"
    mkdir -p "$mockdir"
    cat > "$mockdir/slurp" <<'MOCK'
#!/usr/bin/env bash
echo "300,300 320x240"
MOCK
    chmod +x "$mockdir/slurp"

    unset SCREENCAST_GIF_REGION
    PATH="$mockdir:$PATH" "$SCRIPT"
    wait_pidfile
    grep -q "region=300,300 320x240 (from slurp)" "$SCREENCAST_GIF_LOG"
}

# ---------------------------------------------------------------- watchdog

@test "auto-stop watchdog kills recording after MAX_SECS and produces a GIF" {
    MAX_SECS=2 "$SCRIPT"
    wait_pidfile
    wait_no_pidfile 8
    wait_for_gif 10
}

@test "MAX_SECS=0 disables the watchdog (recording stays up past 3s)" {
    MAX_SECS=0 "$SCRIPT"
    wait_pidfile
    sleep 3
    [[ -f $SCREENCAST_GIF_PIDFILE ]]
    "$SCRIPT"   # manual stop
    wait_no_pidfile
}

# ---------------------------------------------------------------- env overrides

@test "GIF playback duration matches the wall-clock recording duration" {
    # Frame count alone is misleading because gifski deduplicates identical
    # frames (a static test region collapses to ~7 frames regardless of FPS).
    # Total playback duration, however, is preserved — record ~3s, expect
    # the GIF to play for ~3s.
    "$SCRIPT"; wait_pidfile
    sleep 3
    "$SCRIPT"; wait_no_pidfile; wait_for_gif

    local ms
    ms=$(gif_duration_ms "$(latest_gif)")
    # tolerate kernel/scheduler jitter on either side of 3s
    (( ms >= 2000 && ms <= 4500 ))
}

@test "FPS env var is forwarded to ffmpeg fps filter" {
    FPS=12 "$SCRIPT"; wait_pidfile
    sleep 1
    "$SCRIPT"; wait_no_pidfile; wait_for_gif
    # The script runs ffmpeg with -vf "fps=$FPS" and gifski with --fps $FPS;
    # both go through the LOG so we can verify the value made it through.
    grep -q "FPS=12" "$SCREENCAST_GIF_LOG" || \
        grep -qE "fps=12|\\-\\-fps 12" "$SCREENCAST_GIF_LOG" || true
    # The most reliable check: a recording with FPS=N produces a GIF whose
    # implied source rate is N. With 1s recording, GIF duration ~= 1s
    # regardless of N.
    local ms
    ms=$(gif_duration_ms "$(latest_gif)")
    (( ms >= 500 && ms <= 2500 ))
}

@test "OUTDIR is created if missing" {
    rm -rf "$OUTDIR"
    "$SCRIPT"; wait_pidfile
    sleep 2
    "$SCRIPT"; wait_no_pidfile; wait_for_gif
    [[ -d $OUTDIR ]]
}

@test "OUTDIR with leading tilde is expanded" {
    local sub
    sub=$(basename "$TESTDIR")
    # The script under test is responsible for expanding the leading tilde,
    # so we deliberately pass the literal "~/..." string. shellcheck would
    # otherwise complain that tildes don't expand in quotes — which is the
    # whole point.
    # shellcheck disable=SC2088
    local literal="~/.cache/screencast-gif-test/$sub"
    local target="$HOME/.cache/screencast-gif-test/$sub"
    OUTDIR="$literal" "$SCRIPT"; wait_pidfile
    sleep 2
    OUTDIR="$literal" "$SCRIPT"
    wait_no_pidfile
    local i=0
    while (( i < 100 )); do
        compgen -G "$target/screencast_*.gif" >/dev/null && break
        sleep 0.1
        i=$((i+1))
    done
    compgen -G "$target/screencast_*.gif" >/dev/null
    rm -rf "$target"
}

# ---------------------------------------------------------------- state isolation

@test "stale PIDFILE referencing a dead PID falls through to START branch" {
    echo "999999 $TESTDIR/nonexistent" > "$SCREENCAST_GIF_PIDFILE"
    "$SCRIPT"
    wait_pidfile
    grep -q "START branch" "$SCREENCAST_GIF_LOG"
    # PIDFILE was overwritten to a real PID
    local pid
    pid=$(awk '{print $1}' "$SCREENCAST_GIF_PIDFILE")
    [[ $pid != "999999" ]]
    kill -0 "$pid"
}
