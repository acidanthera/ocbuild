#!/bin/bash

#
#  uncstrap.sh
#  ocbuild
#
#  Copyright © 2022 PMheart. All rights reserved.
#

abort() {
  echo "ERROR: $1!"
  exit 1
}

unamer() {
  NAME="$(uname)"

  if [ "$(echo "${NAME}" | grep MINGW)" != "" ] || [ "$(echo "${NAME}" | grep MSYS)" != "" ]; then
    echo "Windows"
  else
    echo "${NAME}"
  fi
}

if [ "${UNSUPPORTED_DIST}" != 1 ]; then
  DIST="$(unamer)"
  case "${DIST}" in
    Darwin | Linux | Windows )
    ;;

    * )
      abort "Unsupported OS distribution ${DIST}"
    ;;
  esac
fi

case "${PROJECT_TYPE}" in
  UEFI )
  ;;

  * )
    abort "Unsupported project type ${PROJECT_TYPE}"
  ;;
esac

if [ "$(which cmake)" = "" ]; then
  abort "Missing cmake"
fi

export UNC_CONFIG="unc-${PROJECT_TYPE}.cfg"
export UNCRUSTIFY_REPO="Uncrustify-repo"
export FILE_LIST="filelist.txt"
export UNC_DIFF="uncrustify.diff"

UNCRUSTIFY_LINK="https://projectmu@dev.azure.com/projectmu/Uncrustify/_git/Uncrustify"
SCHEME="Release"

export UNC_EXEC=./uncrustify
if [ "${DIST}" = "Windows" ]; then
  export UNC_EXEC=./uncrustify.exe
fi

build_bin() {
  local link="$1"

  rm -rf "${UNCRUSTIFY_REPO}" || abort "Failed to cleanup legacy Uncrustify directory"

  git clone "${link}" --depth=1 "${UNCRUSTIFY_REPO}" || abort "Failed to clone ${UNCRUSTIFY_REPO}"
  
  cd "${UNCRUSTIFY_REPO}" || abort "Failed to cd to ${UNCRUSTIFY_REPO}"
  mkdir build || abort "Failed to make temporary build directory"
  cd build || abort "Failed to cd to temporary build directory"
  cmake .. || abort "Failed to generate makefile with cmake"
  cmake --build . --config "${SCHEME}" || abort "Failed to build Uncrustify ${SCHEME}"

  local prefix=./
  if [ "$(unamer)" = "Windows" ]; then
    # Windows has special bin path
    prefix=./"${SCHEME}/"
  fi
  mv "${prefix}${UNC_EXEC}" ../.. || abort "Failed to move ${UNC_EXEC} to parent directory with code $?"

  cd ../..
  rm -rf "${UNCRUSTIFY_REPO}" || abort "Failed to cleanup ${UNCRUSTIFY_REPO} dir with code $?"
}

download_conf() {
  curl -LfsS "https://raw.githubusercontent.com/acidanthera/ocbuild/unc-build/uncrustify/configs/${UNC_CONFIG}" -o "${UNC_CONFIG}" || abort "Failed to download ${CONFIG_NAME}"
}

build_bin "${UNCRUSTIFY_LINK}"
download_conf
