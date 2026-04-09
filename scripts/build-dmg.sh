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
CLEAN_APP_PATH="${BUILD_ROOT}/${APP_NAME}-clean.app"
DMG_PATH="${ROOT_DIR}/${APP_NAME}.dmg"
SHA_PATH="${ROOT_DIR}/${APP_NAME}.dmg.sha256"
TEMP_DMG_PATH="${BUILD_ROOT}/${APP_NAME}-temp.dmg"
VOLUME_NAME="${APP_NAME}"

echo "[INFO] Building ${APP_NAME} (Release)..."
rm -rf "${BUILD_ROOT}"
mkdir -p "${STAGING_DIR}"

echo "[INFO] Sanitizing source inputs..."
find "${ROOT_DIR}/O.Paperclip" -name '.DS_Store' -delete
find "${ROOT_DIR}/bundled" -name '.DS_Store' -delete
xattr -cr "${ROOT_DIR}/O.Paperclip" 2>/dev/null || true
xattr -cr "${ROOT_DIR}/bundled" 2>/dev/null || true

xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "ERROR: App not found at ${APP_PATH}"
  exit 1
fi

echo "[INFO] Sanitizing app bundle for distribution..."
rm -rf "${CLEAN_APP_PATH}"
ditto --noextattr --norsrc "${APP_PATH}" "${CLEAN_APP_PATH}"
find "${CLEAN_APP_PATH}" -name '.DS_Store' -delete
xattr -cr "${CLEAN_APP_PATH}" 2>/dev/null || true
rm -rf "${CLEAN_APP_PATH}/Contents/Resources/.claude"
rm -f "${CLEAN_APP_PATH}/Contents/Resources/settings.local.json"

echo "[INFO] Applying ad hoc signature to app..."
codesign --force --deep --sign - --timestamp=none "${CLEAN_APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${CLEAN_APP_PATH}"

echo "[INFO] Preparing DMG staging directory..."
cp -R "${CLEAN_APP_PATH}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

rm -f "${DMG_PATH}" "${SHA_PATH}" "${TEMP_DMG_PATH}"

echo "[INFO] Creating DMG..."
hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "[INFO] Applying ad hoc signature to DMG..."
codesign --force --sign - --timestamp=none "${DMG_PATH}"
codesign --verify --verbose=2 "${DMG_PATH}"

echo "[INFO] Writing SHA256..."
shasum -a 256 "${DMG_PATH}" > "${SHA_PATH}"

echo "[INFO] DMG created at ${DMG_PATH}"
echo "[INFO] SHA256 written to ${SHA_PATH}"
