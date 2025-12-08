#!/usr/bin/env bash
# build.sh - Bundle all modules into single install.sh for distribution
#
# Usage: ./build.sh [VERSION]
#
# This script combines all modular source files into a single install.sh
# that can be distributed via GitHub raw URLs for curl|bash installation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
SRC_DIR="$SCRIPT_DIR/src"
DIST_DIR="$SCRIPT_DIR/dist"
OUTPUT="$DIST_DIR/install.sh"

VERSION="${1:-$(date +%Y.%m.%d)}"

echo "═══════════════════════════════════════════════════════════════"
echo "  Building pxe-server install.sh"
echo "  Version: ${VERSION}"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Verify all required files exist
REQUIRED_LIBS=(logging config preflight network network_static iso_download packages iso bootloaders nfs dnsmasq kiosk services)
missing=0
for lib in "${REQUIRED_LIBS[@]}"; do
    if [[ ! -f "$LIB_DIR/${lib}.sh" ]]; then
        echo "ERROR: Missing library: $LIB_DIR/${lib}.sh"
        missing=1
    fi
done

if [[ ! -f "$SRC_DIR/main.sh" ]]; then
    echo "ERROR: Missing main script: $SRC_DIR/main.sh"
    missing=1
fi

if [[ $missing -eq 1 ]]; then
    echo ""
    echo "Build failed: Missing required files"
    exit 1
fi

mkdir -p "$DIST_DIR"

# Start with shebang and header
cat > "$OUTPUT" <<'HEADER'
#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#
#  ██████╗ ██╗  ██╗███████╗    ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗
#  ██╔══██╗╚██╗██╔╝██╔════╝    ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗
#  ██████╔╝ ╚███╔╝ █████╗      ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝
#  ██╔═══╝  ██╔██╗ ██╔══╝      ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗
#  ██║     ██╔╝ ██╗███████╗    ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║
#  ╚═╝     ╚═╝  ╚═╝╚══════╝    ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝
#
# ═══════════════════════════════════════════════════════════════════════════════
# PXE Server Setup Script
# Secure Exam Lab - Network Boot / Diskless Systems
# ═══════════════════════════════════════════════════════════════════════════════
#
# One-liner installation:
#   curl -fsSL https://raw.githubusercontent.com/testpress/exam-netboot-infra/main/pxe-server/dist/install.sh | sudo bash
#
# With options:
#   curl -fsSL https://raw.githubusercontent.com/.../install.sh | sudo bash -s -- --help
#   curl -fsSL https://raw.githubusercontent.com/.../install.sh | sudo bash -s -- --dry-run -v
#   curl -fsSL https://raw.githubusercontent.com/.../install.sh | sudo bash -s -- -i /path/to/ubuntu.iso -y
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
IFS=$'\n\t'

HEADER

# Add version
echo "readonly VERSION=\"${VERSION}\"" >> "$OUTPUT"
echo "readonly BUILD_DATE=\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" >> "$OUTPUT"
echo "" >> "$OUTPUT"

# Bundle each library module
for lib in "${REQUIRED_LIBS[@]}"; do
    echo "Bundling: lib/${lib}.sh"
    echo "# ═══════════════════════════════════════════════════════════════════════════════" >> "$OUTPUT"
    echo "# lib/${lib}.sh" >> "$OUTPUT"
    echo "# ═══════════════════════════════════════════════════════════════════════════════" >> "$OUTPUT"
    # Skip shebang line if present (compatible with BSD and GNU sed)
    tail -n +2 "$LIB_DIR/${lib}.sh" >> "$OUTPUT" || cat "$LIB_DIR/${lib}.sh" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
done

# Add main script
echo "Bundling: src/main.sh"
echo "# ═══════════════════════════════════════════════════════════════════════════════" >> "$OUTPUT"
echo "# Main Entry Point" >> "$OUTPUT"
echo "# ═══════════════════════════════════════════════════════════════════════════════" >> "$OUTPUT"
tail -n +2 "$SRC_DIR/main.sh" >> "$OUTPUT" || cat "$SRC_DIR/main.sh" >> "$OUTPUT"

chmod +x "$OUTPUT"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Build Complete!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Output:  $OUTPUT"
echo "  Size:    $(wc -c < "$OUTPUT" | xargs) bytes"
echo "  Lines:   $(wc -l < "$OUTPUT" | xargs)"
echo ""
echo "  Test locally:"
echo "    sudo $OUTPUT --help"
echo "    sudo $OUTPUT --dry-run --verbose"
echo ""
echo "  Commit and push to GitHub, then use:"
echo "    curl -fsSL https://raw.githubusercontent.com/testpress/exam-netboot-infra/main/pxe-server/dist/install.sh | sudo bash"
echo ""
