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

if [ "${PROJECT_NAME}" = "" ]; then
  abort "Missing env variable PROJECT_NAME"
fi

export UNC_CONFIG_FILE="unc-${PROJECT_NAME}.cfg"

if [ "$(which cmake)" = "" ]; then
  abort "Missing cmake"
fi

export UNC_EXEC=./uncrustify
if [ "$(unamer)" = "Windows" ]; then
  export UNC_EXEC=./uncrustify.exe
fi

build_bin() {
  local scheme="Release"

  local link="$1"
  UNCRUSTIFY_REPO=Uncrustify-repo

  git clone "${link}" --depth=1 "${UNCRUSTIFY_REPO}" || abort "Failed to clone Uncrustify"
  cd "${UNCRUSTIFY_REPO}" || abort "Failed to cd to Uncrustify project repo"
  mkdir build || abort "Failed to make temporary build directory"
  cd build || abort "Failed to cd to temporary build directory"
  cmake .. || abort "Failed to generate makefile with cmake"
  cmake --build . --config "${scheme}" || abort "Failed to build Uncrustify"

  local prefix=./
  if [ "$(unamer)" = "Windows" ]; then
    prefix=./"${scheme}/"
  fi
  mv "${prefix}${UNC_EXEC}" ../.. || abort "Failed to move ${UNC_EXEC} to parent directory with code $?"

  cd ../..
  rm -rf "${UNCRUSTIFY_REPO}" || abort "Failed to cleanup Uncrustify repo dir with code $?"
}

download_conf() {
  curl -LfsS "https://raw.githubusercontent.com/acidanthera/ocbuild/unc-build/uncrustify/configs/${UNC_CONFIG_FILE}" -o "${UNC_CONFIG_FILE}" || abort "Failed to download ${CONFIG_NAME}"
}

UNCRUSTIFY_LINK="https://projectmu@dev.azure.com/projectmu/Uncrustify/_git/Uncrustify"
case "$(unamer)" in
  Darwin | Linux | Windows )
    build_bin "${UNCRUSTIFY_LINK}"
    download_conf
  ;;

  * )
    abort "Unsupported OS distribution"
  ;;
esac
