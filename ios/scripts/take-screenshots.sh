#!/bin/bash
# take-screenshots.sh
# Builds Notifikations, launches on simulator, captures raw screenshots, frames them.
#
# Usage:
#   ./scripts/take-screenshots.sh            # iPhone 17 Pro Max (6.9")
#   ./scripts/take-screenshots.sh ipad       # iPad Pro 13-inch (M5)
#   ./scripts/take-screenshots.sh both       # iPhone + iPad

set -e

IPHONE_UDID="8718295C-FD34-4FEF-BAC6-788D203A9F1C"  # iPhone 17 Pro Max
IPAD_UDID="6107616A-4C98-41F2-A40C-077D6F196676"    # iPad Pro 13-inch (M5)

BUNDLE_ID="com.idanbu.notifications"
PROJECT="Notifications.xcodeproj"
SCHEME="Notifications"
DERIVED_DATA=".build/DerivedData"
RAW_DIR="./screenshots/raw"
FRAMED_DIR="./screenshots/framed"

MODE="${1:-iphone}"

build_and_install() {
  local UDID="$1"
  local PLATFORM="$2"  # iphonesimulator or ipadsimulator

  echo "==> Booting simulator $UDID..."
  xcrun simctl boot "$UDID" 2>/dev/null || true

  echo "==> Building $SCHEME for $PLATFORM..."
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    build 2>&1 | xcpretty || xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration Debug \
      -destination "platform=iOS Simulator,id=$UDID" \
      -derivedDataPath "$DERIVED_DATA" \
      build

  APP_PATH=$(find "$DERIVED_DATA" -name "Notifikations.app" -path "*iphonesimulator*" | head -1)
  echo "==> Installing $APP_PATH..."
  xcrun simctl install "$UDID" "$APP_PATH"
}

capture_screenshots() {
  local UDID="$1"
  local SUFFIX="$2"   # iphone or ipad
  local DEVICE_SUFFIX="$3"  # e.g. iphone-17-pro-max
  local OUT="$RAW_DIR/$SUFFIX"

  mkdir -p "$OUT"

  echo "==> Launching $BUNDLE_ID on $UDID..."
  xcrun simctl launch "$UDID" "$BUNDLE_ID"
  sleep 2

  echo "==> Capturing screenshots to $OUT..."

  capture_one() {
    local NAME="$1"
    local PROMPT="$2"
    echo ""
    echo "  >>> $PROMPT"
    echo "  Press ENTER when ready to capture $NAME..."
    read -r
    xcrun simctl io "$UDID" screenshot "$OUT/$NAME"
    echo "  Captured $NAME"
  }

  capture_one "01-home.png"        "Navigate to the HOME / main screen"
  capture_one "02-webhook-url.png" "Navigate to the WEBHOOK URL screen"
  capture_one "03-history.png"     "Navigate to the NOTIFICATION HISTORY screen"
  capture_one "04-api-docs.png"    "Navigate to the API DOCS / code examples screen"

  # Rename raw files to match framed naming convention (<name>-<device>.png)
  for f in "$OUT"/*.png; do
    NAME=$(basename "$f" .png)
    mv "$f" "$OUT/${NAME}-${DEVICE_SUFFIX}.png"
  done

  echo "==> Raw screenshots saved to $OUT"
}

frame_screenshots() {
  local SUFFIX="$1"
  local DEVICE="$2"   # iphone-17-pro-max or ipad-pro-13
  local IN="$RAW_DIR/$SUFFIX"
  local OUT="$FRAMED_DIR/$SUFFIX"

  mkdir -p "$OUT"
  echo "==> Framing screenshots with device=$DEVICE..."

  for IMG in "$IN"/*.png; do
    NAME=$(basename "$IMG")
    asc screenshots frame \
      --input "$IMG" \
      --output-dir "$OUT" \
      --device "$DEVICE" \
      --output json
    echo "  Framed $NAME"
  done

  echo "==> Framed screenshots saved to $OUT"
}

# ---- Run pipeline ----

cd "$(dirname "$0")/.."

if [[ "$MODE" == "iphone" || "$MODE" == "both" ]]; then
  build_and_install "$IPHONE_UDID" "iphonesimulator"
  capture_screenshots "$IPHONE_UDID" "iphone" "iphone-17-pro-max"
  frame_screenshots "iphone" "iphone-17-pro-max"
fi

if [[ "$MODE" == "ipad" || "$MODE" == "both" ]]; then
  build_and_install "$IPAD_UDID" "iphonesimulator"
  capture_screenshots "$IPAD_UDID" "ipad" "ipad-pro-13"
  echo "==> Skipping framing for iPad (no Koubou frame device available — raw screenshots are App Store ready)"
fi

echo ""
echo "Done! Raw:    ./screenshots/raw/"
echo "      Framed: ./screenshots/framed/"
echo ""
echo "Next steps:"
echo "  1. Open framed screenshots and add text overlays in Figma/Sketch"
echo "  2. Or run: asc screenshots review-generate --framed-dir ./screenshots/framed --raw-dir ./screenshots/raw/iphone --output-dir ./screenshots/review && asc screenshots review-open --output-dir ./screenshots/review"
