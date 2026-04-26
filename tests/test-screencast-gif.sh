#!/usr/bin/env bash
# End-to-end test for screencast-gif.sh.
# Drives a full record → stop → GIF cycle without slurp or hotkey, then verifies
# the artifacts. Intended to be run from a Wayland session that has wf-recorder,
# gifski, ffmpeg and wl-copy available. Make sure no manual recording is in
# progress before running.
set -uo pipefail

SCRIPT="${SCRIPT:-$(dirname "$0")/../screencast-gif.sh}"
LOG=/tmp/screencast-gif.log
PIDFILE=/tmp/screencast-gif.pid
LOCKFILE=/tmp/screencast-gif.lock
WORKDIR=/tmp/screencast-gif

# Region sized to fit any sensible monitor; unrelated to the user's actual screen.
export SCREENCAST_GIF_REGION="${SCREENCAST_GIF_REGION:-100,100 320x240}"
export OUTDIR="${OUTDIR:-$HOME/Screenshots}"

cleanup() {
    pkill -INT -f "^wf-recorder" 2>/dev/null
    sleep 0.5
    pkill -KILL -f "^wf-recorder" 2>/dev/null
    rm -f "$PIDFILE" "$LOCKFILE"
    rm -rf "$WORKDIR"/[0-9]*
}
fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "OK: $*"; }

run() {
    local name=$1; shift
    echo "--- TEST: $name ---"
    cleanup
    : > "$LOG"
    "$@"
    local rc=$?
    echo "--- log ---"
    cat "$LOG"
    echo "--- /log ---"
    return $rc
}

assert_pid_alive() {
    [[ -f $PIDFILE ]] || fail "no PIDFILE"
    local pid=$(awk '{print $1}' "$PIDFILE")
    kill -0 "$pid" 2>/dev/null || fail "PID $pid not alive"
    ok "PID $pid alive"
}

assert_gif_created() {
    local before=$1
    local newest=$(ls -t "$OUTDIR"/screencast_*.gif 2>/dev/null | head -1)
    [[ -n $newest ]] || fail "no GIF produced"
    local mtime=$(stat -c %Y "$newest")
    (( mtime >= before )) || fail "GIF $newest is older than test start"
    local size=$(stat -c %s "$newest")
    (( size > 1000 )) || fail "GIF $newest suspiciously small ($size bytes)"
    ok "GIF $newest size=$size bytes"
}

assert_clipboard_has_gif() {
    local mime=$(wl-paste --list-types 2>/dev/null | grep -E "^image/gif$" || true)
    [[ -n $mime ]] || fail "clipboard does not hold image/gif (types: $(wl-paste --list-types 2>/dev/null | tr '\n' ',' ))"
    ok "clipboard holds image/gif"
}

test_basic_cycle() {
    local started=$(date +%s)
    "$SCRIPT"
    sleep 0.5
    assert_pid_alive
    sleep 2
    "$SCRIPT"
    [[ ! -f $PIDFILE ]] || fail "PIDFILE still present after stop"
    assert_gif_created "$started"
    assert_clipboard_has_gif
}

test_rapid_double_press_during_record() {
    local started=$(date +%s)
    "$SCRIPT"
    sleep 0.5
    assert_pid_alive
    sleep 1
    "$SCRIPT" &
    local p1=$!
    "$SCRIPT" &
    local p2=$!
    wait $p1 $p2
    [[ ! -f $PIDFILE ]] || fail "PIDFILE still present after double-stop"
    assert_gif_created "$started"
}

test_immediate_restart_after_stop() {
    local started=$(date +%s)
    "$SCRIPT"; sleep 1; assert_pid_alive
    sleep 1
    "$SCRIPT"
    "$SCRIPT"
    sleep 0.5
    assert_pid_alive
    sleep 2
    "$SCRIPT"
    [[ ! -f $PIDFILE ]] || fail "PIDFILE present after second stop"
    assert_gif_created "$started"
}

test_odd_region_is_rounded() {
    local started=$(date +%s)
    SCREENCAST_GIF_REGION="1135,461 500x395" "$SCRIPT"
    sleep 0.5
    assert_pid_alive
    grep -q "region rounded to 1134,460 500x396" "$LOG" || fail "expected region rounding to even coords"
    sleep 2
    "$SCRIPT"
    assert_gif_created "$started"
}

run "basic cycle" test_basic_cycle && ok "basic cycle PASSED" || fail "basic cycle FAILED"
run "rapid double-press during record" test_rapid_double_press_during_record && ok "double-press PASSED" || fail "double-press FAILED"
run "immediate restart after stop" test_immediate_restart_after_stop && ok "restart PASSED" || fail "restart FAILED"
run "odd region is rounded to even" test_odd_region_is_rounded && ok "odd region PASSED" || fail "odd region FAILED"
echo
echo "ALL TESTS PASSED"
