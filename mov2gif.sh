#!/bin/bash
#
# mov2gif.sh - Convert a .mov file into a small GIF for sharing.
#
#   1. Installs Homebrew if it's missing
#   2. Installs ffmpeg if it's missing
#   3. Prompts for the input file and the desired GIF name
#   4. Converts, then exits. On any failure, the error is appended to
#      ~/Desktop/ErrorGIFConverLog.txt and the script exits non-zero.
#
# Usage:  chmod +x mov2gif.sh && ./mov2gif.sh

#### This is set to Low by default if you want higher quality remove the # from 
#### the second section of FPS & WIDTH an add the # back to the first section
#
#
# --- Settings default for lower for a smaller file -------------------------------
FPS=10          # frames per second
WIDTH=320       # max width in pixels (height scales automatically)

# -- Settings for higher quality but larger file size -----------------------------
#FPS=12 
#WIDTH=480

ERROR_LOG="$HOME/Desktop/ErrorGIFConverLog.txt"
TMP_LOG="$(mktemp)"
trap 'rm -f "$TMP_LOG"' EXIT

# --- Helpers -----------------------------------------------------------------

# Write the error (plus any captured command output) to the Desktop log and quit.
fail() {
  {
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "ERROR: $1"
    if [ -s "$TMP_LOG" ]; then
      echo "--- Details ---"
      cat "$TMP_LOG"
    fi
    echo
  } >> "$ERROR_LOG"
  echo "ERROR: $1"
  echo "Details saved to: $ERROR_LOG"
  exit 1
}

# Run a command, show its output live, and keep a copy in $TMP_LOG.
# Returns the command's own exit code (not tee's).
run_logged() {
  : > "$TMP_LOG"
  "$@" 2>&1 | tee "$TMP_LOG"
  return "${PIPESTATUS[0]}"
}

# Clean up what Terminal gives you when you drag a file in or paste a path:
# trims spaces, removes "\ " escapes and surrounding quotes, expands ~.
clean_path() {
  local p="$1"
  p="${p#"${p%%[![:space:]]*}"}"
  p="${p%"${p##*[![:space:]]}"}"
  p="${p//\\/}"
  p="${p#\'}"; p="${p%\'}"
  p="${p#\"}"; p="${p%\"}"
  if [[ "$p" == "~"* ]]; then p="$HOME${p:1}"; fi
  printf '%s' "$p"
}

# Make `brew` available in this shell (Apple Silicon and Intel locations).
load_brew() {
  command -v brew >/dev/null 2>&1 && return 0
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$b" ]; then
      eval "$("$b" shellenv)"
      return 0
    fi
  done
  return 1
}

# --- 0. Sanity check ---------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || fail "This script is written for macOS."

# --- 1. Homebrew -------------------------------------------------------------
if ! load_brew; then
  echo "Homebrew not found. Installing it now (you may be asked for your password)..."
  INSTALLER="$(mktemp)"
  curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
    -o "$INSTALLER" 2> "$TMP_LOG" || { rm -f "$INSTALLER"; fail "Could not download the Homebrew installer."; }
  run_logged /bin/bash "$INSTALLER" || { rm -f "$INSTALLER"; fail "Homebrew installation failed."; }
  rm -f "$INSTALLER"
  load_brew || fail "Homebrew installed, but 'brew' could not be found afterwards."
fi

# --- 2. ffmpeg ---------------------------------------------------------------
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg not found. Installing via Homebrew (this can take several minutes)..."
  run_logged brew install ffmpeg || fail "ffmpeg installation failed."
  command -v ffmpeg >/dev/null 2>&1 || fail "ffmpeg installed, but it could not be found afterwards."
fi

# --- 3. Prompts --------------------------------------------------------------
read -r -p "Drag your .mov file here (or type the path), then press Enter: " RAW_IN
INPUT="$(clean_path "$RAW_IN")"
: > "$TMP_LOG"
[ -n "$INPUT" ] || fail "No input file was provided."
[ -f "$INPUT" ] || fail "Input file not found: $INPUT"

read -r -p "Name for the GIF (extension optional): " RAW_NAME
NAME="$(clean_path "$RAW_NAME")"
NAME="${NAME##*/}"                  # keep just the name, ignore any folder typed in
NAME="${NAME%.[gG][iI][fF]}"        # drop .gif if they typed it
[ -n "$NAME" ] || fail "No GIF name was provided."

OUTPUT="$(dirname "$INPUT")/$NAME.gif"   # saved next to the original .mov

if [ -e "$OUTPUT" ]; then
  read -r -p "$OUTPUT already exists. Overwrite? [y/N] " ANSWER
  [[ "$ANSWER" =~ ^[Yy]$ ]] || { echo "Cancelled. Nothing was changed."; exit 0; }
fi

# --- 4. Convert --------------------------------------------------------------
# Two-pass palette (palettegen/paletteuse) keeps colors clean at a small size.
echo "Converting..."
run_logged ffmpeg -nostdin -y -hide_banner -loglevel error -i "$INPUT" \
  -vf "fps=$FPS,scale='min($WIDTH,iw)':-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" \
  -loop 0 "$OUTPUT" || fail "ffmpeg could not convert: $INPUT"

[ -s "$OUTPUT" ] || fail "ffmpeg finished but the GIF is missing or empty: $OUTPUT"

echo "Done: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
exit 0
