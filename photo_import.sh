#!/bin/bash

# =============================================================================
# Script called photo_import.sh — macOS Photo Card Importer
# Copies RAW/JPEG files from a named volume to ~/Intake,
# logs the import to the Desktop as Card1.txt, then safely ejects.
# Must enter card name when running the script to assure it's the right Card
# =============================================================================

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║       📷  Photo Card Importer  📷        ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

print_step()  { echo -e "${CYAN}▶ $1${NC}"; }
print_ok()    { echo -e "${GREEN}  ✔  $1${NC}"; }
print_warn()  { echo -e "${YELLOW}  ⚠  $1${NC}"; }
print_error() { echo -e "${RED}  ✖  $1${NC}"; }

# ── Elevate privileges up front ───────────────────────────────────────────────

print_header



# ── Configuration ─────────────────────────────────────────────────────────────
INTAKE_DIR="$HOME/Intake"
LOG_FILE="$HOME/Desktop/Card1.txt"
EXTENSIONS=("CR3" "JPEG" "JPG" "NEF" "SRF" "SR2" "ARW" "ARQ")

# ── Step 1 — Get volume name from the user ────────────────────────────────────
print_step "Enter the name of your SD card / USB volume"
echo -e "  ${YELLOW}(This is the name shown in Finder under Locations)${NC}"
echo ""
read -rp "  Volume name: " VOLUME_NAME

if [[ -z "$VOLUME_NAME" ]]; then
    print_error "No volume name entered. Exiting."
    exit 1
fi

VOLUME_PATH="/Volumes/$VOLUME_NAME"

# ── Step 2 — Verify the volume is mounted ─────────────────────────────────────
echo ""
print_step "Checking for mounted volume: ${BOLD}$VOLUME_NAME${NC}"

if [[ ! -d "$VOLUME_PATH" ]]; then
    print_error "Volume '${VOLUME_NAME}' not found at ${VOLUME_PATH}."
    print_warn  "Make sure the card/drive is plugged in and the name matches exactly."
    exit 1
fi

print_ok "Volume found at ${VOLUME_PATH}"

# ── Step 3 — Find matching photo files (case-insensitive, full recursive scan) ─
echo ""
print_step "Scanning entire volume for photo files (all subdirectories)..."

# Build find arguments for all supported extensions
FIND_ARGS=()
for i in "${!EXTENSIONS[@]}"; do
    ext="${EXTENSIONS[$i]}"
    if [[ $i -gt 0 ]]; then
        FIND_ARGS+=("-o")
    fi
    FIND_ARGS+=("-iname" "*.${ext}")
done

# Collect matching files into an array — bash 3.2 compatible (no mapfile)
FOUND_FILES=()
while IFS= read -r -d '' FILE; do
    FOUND_FILES+=("$FILE")
done < <(find "$VOLUME_PATH" \( "${FIND_ARGS[@]}" \) -type f -print0 2>/dev/null)

if [[ ${#FOUND_FILES[@]} -eq 0 ]]; then
    print_error "No supported photo files found anywhere on '${VOLUME_NAME}'."
    print_warn  "Supported extensions: ${EXTENSIONS[*]}"
    exit 1
fi

print_ok "Found ${#FOUND_FILES[@]} photo file(s)"

# Show which subdirectories files were discovered in
echo ""
echo -e "  ${YELLOW}Directories containing matching files:${NC}"
DIRS_FOUND=()
for FILE_PATH in "${FOUND_FILES[@]}"; do
    DIR=$(dirname "$FILE_PATH")
    REL_DIR="${DIR#$VOLUME_PATH}"
    REL_DIR="${REL_DIR:-/}"
    ALREADY_LISTED=false
    for D in "${DIRS_FOUND[@]}"; do
        [[ "$D" == "$REL_DIR" ]] && ALREADY_LISTED=true && break
    done
    if [[ "$ALREADY_LISTED" == false ]]; then
        DIRS_FOUND+=("$REL_DIR")
        echo -e "  ${CYAN}  📁 ${VOLUME_NAME}${REL_DIR}${NC}"
    fi
done
echo ""

# ── Step 4 — Create ~/Intake if it doesn't exist ────────────────────────────
print_step "Verifying intake folder: ${INTAKE_DIR}"

if [[ ! -d "$INTAKE_DIR" ]]; then
    print_warn "Folder does not exist — creating it now..."
    mkdir -p "$INTAKE_DIR"
    if [[ $? -ne 0 ]]; then
        print_error "Failed to create ${INTAKE_DIR}. Check folder permissions."
        exit 1
    fi
    print_ok "Created ${INTAKE_DIR}"
else
    print_ok "Folder already exists"
    
fi

# ── Step 5 — Copy files ───────────────────────────────────────────────────────
echo ""
print_step "Copying files to ${INTAKE_DIR}..."
echo ""

IMPORT_TIME=$(date "+%Y-%m-%d %H:%M:%S")
COPIED_FILES=()
FAILED_FILES=()

for FILE_PATH in "${FOUND_FILES[@]}"; do
    FILENAME=$(basename "$FILE_PATH")
    DEST="${INTAKE_DIR}/${FILENAME}"

    # Handle duplicate filenames by appending a counter
    if [[ -e "$DEST" ]]; then
        BASE="${FILENAME%.*}"
        EXT="${FILENAME##*.}"
        COUNTER=1
        while [[ -e "${INTAKE_DIR}/${BASE}_${COUNTER}.${EXT}" ]]; do
            ((COUNTER++))
        done
        DEST="${INTAKE_DIR}/${BASE}_${COUNTER}.${EXT}"
        FILENAME="${BASE}_${COUNTER}.${EXT}"
        print_warn "Duplicate — renamed to: ${FILENAME}"
    fi

    cp "$FILE_PATH" "$DEST"

    if [[ $? -eq 0 ]]; then
        # Verify copy with MD5 checksum
        SRC_MD5=$(md5 -q "$FILE_PATH" 2>/dev/null)
        DST_MD5=$(md5 -q "$DEST"      2>/dev/null)

        if [[ "$SRC_MD5" == "$DST_MD5" ]]; then
            print_ok "Copied & verified: ${FILENAME}"
            COPIED_FILES+=("$FILENAME")
        else
            print_error "Checksum mismatch — copy may be corrupt: ${FILENAME}"
            FAILED_FILES+=("$FILENAME")
        fi
    else
        print_error "Failed to copy: ${FILENAME}"
        FAILED_FILES+=("$FILENAME")
    fi
done

# ── Step 6 — Write the Desktop log (Card1.txt) ───────────────────────────────
echo ""
print_step "Writing import log to Desktop (Card1.txt)..."

{
    echo "======================================================"
    echo "  PHOTO IMPORT LOG — Card1"
    echo "======================================================"
    echo "  Volume     : $VOLUME_NAME"
    echo "  Import Time: $IMPORT_TIME"
    echo "  Destination: $INTAKE_DIR"
    echo "------------------------------------------------------"
    echo ""
    echo "  FILES IMPORTED (${#COPIED_FILES[@]}):"
    if [[ ${#COPIED_FILES[@]} -gt 0 ]]; then
        for f in "${COPIED_FILES[@]}"; do
            echo "    ok  $f"
        done
    else
        echo "    (none)"
    fi

    if [[ ${#FAILED_FILES[@]} -gt 0 ]]; then
        echo ""
        echo "  FILES FAILED (${#FAILED_FILES[@]}):"
        for f in "${FAILED_FILES[@]}"; do
            echo "    !!  $f"
        done
    fi

    echo ""
    echo "======================================================"
    echo "  Total copied : ${#COPIED_FILES[@]}"
    echo "  Total failed : ${#FAILED_FILES[@]}"
    echo "======================================================"
} > "$LOG_FILE"

if [[ $? -eq 0 ]]; then
    print_ok "Log saved to: ${LOG_FILE}"
else
    print_error "Could not write log file to Desktop."
fi

# ── Step 7 — Abort if any files failed ───────────────────────────────────────
if [[ ${#FAILED_FILES[@]} -gt 0 ]]; then
    echo ""
    print_error "${#FAILED_FILES[@]} file(s) failed to copy or failed verification."
    print_warn  "The volume will NOT be ejected. Please resolve the errors above."
    exit 1
fi

# ── Step 8 — Eject the volume ─────────────────────────────────────────────────
echo ""
print_step "All files verified — ejecting '${VOLUME_NAME}'..."

diskutil eject "$VOLUME_PATH" > /dev/null 2>&1

if [[ $? -eq 0 ]]; then
    print_ok "Volume '${VOLUME_NAME}' safely ejected. You can remove your card/drive."
else
    print_warn "Could not auto-eject '${VOLUME_NAME}'. Please eject it manually in Finder."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║       Import complete! Happy editing.    ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
