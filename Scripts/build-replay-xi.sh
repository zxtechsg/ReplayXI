#!/bin/zsh
# Build Replay XI locally without signing or installation.
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
PROJECT_PATH="${PROJECT_ROOT}/ReplayXI.xcodeproj"
SCHEME="ReplayXI"
BUILD_SIMULATOR=1
BUILD_DEVICE=1

usage() {
  print -- "Usage: Scripts/build-replay-xi.sh [--sim-only | --device-only]"
  print -- "Builds Replay XI into .codex-derived/ with code signing disabled."
}

if (( $# > 1 )); then
  print -u2 -- "error: Expected at most one option."
  usage
  exit 64
fi

case "${1:-}" in
  "") ;;
  --sim-only) BUILD_DEVICE=0 ;;
  --device-only) BUILD_SIMULATOR=0 ;;
  -h|--help) usage; exit 0 ;;
  *)
    print -u2 -- "error: Unknown option: $1"
    usage
    exit 64
    ;;
esac

command -v xcodebuild >/dev/null 2>&1 || {
  print -u2 -- "error: xcodebuild is unavailable. Install Xcode and select its developer directory."
  exit 69
}

[[ -f "${PROJECT_PATH}/project.pbxproj" ]] || {
  print -u2 -- "error: ReplayXI.xcodeproj is missing at ${PROJECT_PATH}."
  exit 66
}

if (( BUILD_SIMULATOR )); then
  SIMULATOR_DERIVED_DATA="${PROJECT_ROOT}/.codex-derived/ReplayXI-Simulator"
  print -- "Building Replay XI Simulator Debug..."
  xcodebuild -quiet \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -destination 'generic/platform=visionOS Simulator' \
    CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath "${SIMULATOR_DERIVED_DATA}" \
    build
  print -- "Simulator build: ${SIMULATOR_DERIVED_DATA}"
fi

if (( BUILD_DEVICE )); then
  DEVICE_DERIVED_DATA="${PROJECT_ROOT}/.codex-derived/ReplayXI-Device"
  print -- "Building Replay XI generic-device Release..."
  xcodebuild -quiet \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination 'generic/platform=visionOS' \
    CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath "${DEVICE_DERIVED_DATA}" \
    build
  print -- "Device build: ${DEVICE_DERIVED_DATA}"
fi

print -- "Replay XI build completed. These artifacts are unsigned and are not installed."
