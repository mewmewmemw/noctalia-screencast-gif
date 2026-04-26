#!/usr/bin/env bash
# screencast-gif.sh — toggle screen recording, convert to GIF, copy to clipboard.
#
# Designed to be invoked twice as a toggle: first call selects a region with slurp
# and starts wf-recorder; second call stops the recorder, runs ffmpeg + gifski to
# produce a .gif, copies it to the Wayland clipboard as image/gif, and saves the
# file to OUTDIR.
#
# Environment variables (all optional):
#   FPS                  GIF frame rate. Default: 20.
#   MAX_SECS             Auto-stop after this many seconds. 0 disables. Default: 120.
#   OUTDIR               Where to save the GIF. Tilde is expanded. Default: ~/Screenshots.
#   SCREENCAST_GIF_REGION  Skip slurp and use this region (format: "X,Y WxH"). For tests.
#   SCREENCAST_GIF_LOG   Log file path. Default: /tmp/screencast-gif.log.

set -euo pipefail

LOGFILE=${SCREENCAST_GIF_LOG:-/tmp/screencast-gif.log}
exec >> "$LOGFILE" 2>&1
echo "=== $(date +%T.%N) invoked pid=$$ args='$*' ==="

LOCKFILE=/tmp/screencast-gif.lock
exec 9>"$LOCKFILE"
if ! flock -n 9; then
    echo "  another instance holds lock, exiting"
    exit 0
fi

PIDFILE=/tmp/screencast-gif.pid
WORKDIR=/tmp/screencast-gif
OUTDIR=${OUTDIR:-$HOME/Screenshots}
OUTDIR=${OUTDIR/#\~/$HOME}
FPS=${FPS:-20}
MAX_SECS=${MAX_SECS:-120}

notify() { notify-send -a screencast-gif "$@"; }

if [[ -f $PIDFILE ]] && kill -0 "$(awk '{print $1}' "$PIDFILE")" 2>/dev/null; then
    read -r PID RUNDIR < "$PIDFILE"
    echo "  STOP branch, PID=$PID rundir=$RUNDIR"
    rm -f "$PIDFILE"
    flock -u 9
    exec 9>&-

    kill -INT "$PID"
    while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done

    notify "Converting to GIF…"
    FRAMES="$RUNDIR/frames"
    mkdir -p "$FRAMES"
    ffmpeg -loglevel error -i "$RUNDIR/rec.mp4" -vf "fps=$FPS" "$FRAMES/%05d.png"

    mkdir -p "$OUTDIR"
    OUT="$OUTDIR/screencast_$(date +%Y%m%d_%H%M%S).gif"
    gifski -o "$OUT" --fps "$FPS" "$FRAMES"/*.png >/dev/null
    rm -rf "$RUNDIR"

    wl-copy --type image/gif < "$OUT"
    notify "GIF in clipboard" "$OUT"
else
    echo "  START branch"
    if [[ -n ${SCREENCAST_GIF_REGION:-} ]]; then
        REGION=$SCREENCAST_GIF_REGION
        echo "  region=$REGION (from env)"
    else
        echo "  calling slurp"
        REGION=$(slurp) || { echo "  slurp cancelled/failed (rc=$?)"; exit 0; }
        echo "  region=$REGION (from slurp)"
    fi
    # h264/yuv420p requires even dimensions; round X,Y down and W,H up to even.
    if [[ $REGION =~ ^([0-9]+),([0-9]+)\ ([0-9]+)x([0-9]+)$ ]]; then
        x=$(( ${BASH_REMATCH[1]} & ~1 ))
        y=$(( ${BASH_REMATCH[2]} & ~1 ))
        w=$(( (${BASH_REMATCH[3]} + 1) & ~1 ))
        h=$(( (${BASH_REMATCH[4]} + 1) & ~1 ))
        REGION="${x},${y} ${w}x${h}"
        echo "  region rounded to $REGION"
    fi

    RUN_ID=$(date +%s%N)
    RUNDIR="$WORKDIR/$RUN_ID"
    mkdir -p "$RUNDIR" "$OUTDIR"

    wf-recorder --no-dmabuf --pixel-format yuv420p -g "$REGION" -f "$RUNDIR/rec.mp4" >>"$LOGFILE" 2>&1 9>&- &
    PID=$!
    disown
    echo "$PID $RUNDIR" > "$PIDFILE"

    SELF="$(readlink -f "$0")"
    if (( MAX_SECS > 0 )); then
        (
            sleep "$MAX_SECS"
            if [[ -f $PIDFILE ]] && [[ "$(awk '{print $1}' "$PIDFILE" 2>/dev/null)" == "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
                "$SELF"
            fi
        ) >/dev/null 2>&1 9>&- &
        disown
    fi
fi
