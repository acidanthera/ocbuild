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
  local link="$1"
  UNCRUSTIFY_REPO=Uncrustify-repo

  git clone "${link}" --depth=1 "${UNCRUSTIFY_REPO}" || abort "Failed to clone Uncrustify"
  cd "${UNCRUSTIFY_REPO}" || abort "Failed to cd to Uncrustify project repo"
  mkdir build || abort "Failed to make temporary build directory"
  cd build || abort "Failed to cd to temporary build directory"
  cmake .. || abort "Failed to generate makefile with cmake"
  cmake --build . || abort "Failed to build Uncrustify"

  mv "${UNC_EXEC}" ../.. || abort "Failed to move ${UNC_EXEC} to parent directory with code $?"

  cd ../..
  rm -rf "${UNCRUSTIFY_REPO}" || abort "Failed to cleanup Uncrustify repo dir with code $?"
}

download_bin() {
  local link="$1"
  local UNCRUSTIFY_ARCHIVE="uncrustify.zip"

  mkdir -p Uncrustify-analysis
  cd Uncrustify-analysis || abort "Failed to cd to Uncrustify-analysis directory with code $?"

  echo "Downloading Uncrustify..."
  curl -LfsS "${link}" -o "${UNCRUSTIFY_ARCHIVE}" || abort "Failed to download Uncrustify with code $?"

  unzip -q "${UNCRUSTIFY_ARCHIVE}" || abort "Failed to decompress Uncrustify with code $?"

  cd Executable || abort "Failed to cd to Uncrustify Executable with code $?"

  chmod a+x "${UNC_EXEC}" || abort "Failed to chmod ${UNC_EXEC} with code $?"

  mv "${UNC_EXEC}" ../.. || abort "Failed to move ${UNC_EXEC} to parent directory with code $?"

  cd ../..
  rm -rf Uncrustify-analysis || abort "Failed to cleanup Uncrustify-analysis dir with code $?"
}

download_conf() {
  curl -LfsS "https://raw.githubusercontent.com/acidanthera/ocbuild/unc-build/uncrustify/configs/${UNC_CONFIG_FILE}" -o "${UNC_CONFIG_FILE}" || abort "Failed to download ${CONFIG_NAME}"
}

UNCRUSTIFY_LINK="https://projectmu@dev.azure.com/projectmu/Uncrustify/_git/Uncrustify"
case "$(unamer)" in
  Darwin )
    # UNCRUSTIFY_LINK="https://projectmu@dev.azure.com/projectmu/Uncrustify/_git/Uncrustify"
    build_bin "${UNCRUSTIFY_LINK}"
    download_conf
  ;;

  Linux )
    # UNCRUSTIFY_LINK="https://dev.azure.com/projectmu/271ca9de-dc2a-4567-ad0f-bde903c9ce7e/_apis/build/builds/12516/artifacts?artifactName=Executable&api-version=7.0&%24format=zip"
    # download_bin "${UNCRUSTIFY_LINK}"
    build_bin "${UNCRUSTIFY_LINK}"
    download_conf
  ;;

  Windows )
    # UNCRUSTIFY_LINK="https://dev.azure.com/projectmu/271ca9de-dc2a-4567-ad0f-bde903c9ce7e/_apis/build/builds/12518/artifacts?artifactName=Executable&api-version=7.0&%24format=zip"
    # download_bin "${UNCRUSTIFY_LINK}"
    build_bin "${UNCRUSTIFY_LINK}"
    download_conf
  ;;

  * )
    abort "Unsupported OS distribution"
  ;;
esac
