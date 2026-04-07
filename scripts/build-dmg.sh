#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_ROOT="${ROOT_DIR}/build/dmg"
DERIVED_DATA_DIR="${BUILD_ROOT}/DerivedData"
STAGING_DIR="${BUILD_ROOT}/staging"
APP_NAME="O.Paperclip"
PROJECT_PATH="${ROOT_DIR}/${APP_NAME}.xcodeproj"
APP_PATH="${DERIVED_DATA_DIR}/Build/Products/Release/${APP_NAME}.app"
DMG_PATH="${ROOT_DIR}/${APP_NAME}.dmg"
TEMP_DMG_PATH="${BUILD_ROOT}/${APP_NAME}-temp.dmg"
VOLUME_NAME="${APP_NAME}"

echo "[INFO] Building ${APP_NAME} (Release)..."
rm -rf "${BUILD_ROOT}"
mkdir -p "${STAGING_DIR}"

xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "ERROR: App not found at ${APP_PATH}"
  exit 1
fi

echo "[INFO] Sanitizing app bundle for distribution..."
find "${APP_PATH}" -name '.DS_Store' -delete
xattr -cr "${APP_PATH}" 2>/dev/null || true
rm -rf "${APP_PATH}/Contents/Resources/.claude"
rm -f "${APP_PATH}/Contents/Resources/settings.local.json"

echo "[INFO] Preparing DMG staging directory..."
cp -R "${APP_PATH}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

rm -f "${DMG_PATH}" "${TEMP_DMG_PATH}"

echo "[INFO] Creating DMG..."
hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "[INFO] DMG created at ${DMG_PATH}"
