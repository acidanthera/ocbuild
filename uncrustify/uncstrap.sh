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

# Avoid conflicts with PATH overrides.
CAT="/bin/cat"
CHMOD="/bin/chmod"
CURL="/usr/bin/curl"
FIND="/usr/bin/find"
MKDIR="/bin/mkdir"
MV="/bin/mv"
RM="/bin/rm"
TAR="/usr/bin/tar"
UNZIP="/usr/bin/unzip"

TOOLS=(
  "${CAT}"
  "${CHMOD}"
  "${CURL}"
  "${FIND}"
  "${MKDIR}"
  "${MV}"
  "${RM}"
  "${TAR}"
  "${UNZIP}"
)

for tool in "${TOOLS[@]}"; do
  if [ ! -x "${tool}" ]; then
    abort "Missing ${tool}"
  fi
done

if [ "$(which cmake)" = "" ]; then
  abort "Missing cmake"
fi

build_bin() {
  local link="$1"
  
  git clone "${link}" --depth=1 Uncrustify || abort "Failed to clone Uncrustify"
  cd Uncrustify || abort "Failed to cd to Uncrustify project repo"
  mkdir build || abort "Failed to make temporary build directory"
  cd build || abort "Failed to cd to temporary build directory"
  cmake .. || abort "Failed to generate makefile with cmake"
  cmake --build . || abort "Failed to build Uncrustify"

  export UNC_EXEC=./uncrustify

  "${MV}" "${UNC_EXEC}" ../../.. || abort "Failed to move ${UNC_EXEC} to parent directory with code $?"

  cd ../../..
  "${RM}" -rf Uncrustify || abort "Failed to cleanup Uncrustify repo dir with code $?"
}

download_bin() {
  local link="$1"
  local UNCRUSTIFY_ARCHIVE="uncrustify.zip"

  "${MKDIR}" -p Uncrustify-analysis
  cd Uncrustify-analysis || abort "Failed to cd to Uncrustify-analysis directory with code $?"

  echo "Downloading Uncrustify..."
  "${CURL}" -LfsS "${link}" -o "${UNCRUSTIFY_ARCHIVE}" || abort "Failed to download Uncrustify with code $?"

  "${UNZIP}" -q "${UNCRUSTIFY_ARCHIVE}" || abort "Failed to decompress Uncrustify with code $?"

  cd Executable || abort "Failed to cd to Uncrustify Executable with code $?"

  export UNC_EXEC=./uncrustify
  if [ "$(unamer)" = "Windows" ]; then
    export UNC_EXEC=./uncrustify.exe
  fi

  "${CHMOD}" a+x "${UNC_EXEC}" || abort "Failed to chmod ${UNC_EXEC} with code $?"

  "${MV}" "${UNC_EXEC}" ../.. || abort "Failed to move ${UNC_EXEC} to parent directory with code $?"

  cd ../..
  "${RM}" -rf Uncrustify-analysis || abort "Failed to cleanup Uncrustify-analysis dir with code $?"
}

UNCRUSTIFY_LINK=""
case "$(unamer)" in
  Darwin )
    UNCRUSTIFY_LINK="https://projectmu@dev.azure.com/projectmu/Uncrustify/_git/Uncrustify"
    build_bin "${UNCRUSTIFY_LINK}"
  ;;

  Linux )
    UNCRUSTIFY_LINK="https://dev.azure.com/projectmu/271ca9de-dc2a-4567-ad0f-bde903c9ce7e/_apis/build/builds/12516/artifacts?artifactName=Executable&api-version=7.0&%24format=zip"
    download_bin "${UNCRUSTIFY_LINK}"
  ;;

  Windows )
    UNCRUSTIFY_LINK="https://dev.azure.com/projectmu/271ca9de-dc2a-4567-ad0f-bde903c9ce7e/_apis/build/builds/12518/artifacts?artifactName=Executable&api-version=7.0&%24format=zip"
    download_bin "${UNCRUSTIFY_LINK}"
  ;;

  * )
    abort "Unsupported OS distribution"
  ;;
esac

# "${UNC_EXEC}" -c ./Uncrustify-analysis/"${UNCRUSTIFY_CONFIG_FILE}" -F "${FILE_LIST}" --replace --no-backup --if-changed

# git diff > uncrustify.diff || ret=$?
# if [ $ret -ne 0 ]; then
#   abort "Failed to generate Uncrustify diff with code ${ret}"
# fi

# if [ "$(${CAT} uncrustify.diff)" != "" ]; then
#   # show the diff
#   "${CAT}" uncrustify.diff
#   abort "Uncrustify detects codestyle problems! Please fix"
# fi

exit 0
