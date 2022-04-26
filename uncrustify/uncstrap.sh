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

UNCRUSTIFY_LINK=""
UNCRUSTIFY_ARCHIVE="uncrustify.zip"
case "$(unamer)" in
  Darwin )
    # we will build binaries for macOS
    # TODO: build & fix link
    UNCRUSTIFY_LINK="https://dev.azure.com/projectmu/271ca9de-dc2a-4567-ad0f-bde903c9ce7e/_apis/build/builds/12516/artifacts?artifactName=Executable&api-version=7.0&%24format=zip"
  ;;

  Linux )
    UNCRUSTIFY_LINK="https://dev.azure.com/projectmu/271ca9de-dc2a-4567-ad0f-bde903c9ce7e/_apis/build/builds/12516/artifacts?artifactName=Executable&api-version=7.0&%24format=zip"
  ;;

  Windows )
    UNCRUSTIFY_LINK="https://dev.azure.com/projectmu/271ca9de-dc2a-4567-ad0f-bde903c9ce7e/_apis/build/builds/12518/artifacts?artifactName=Executable&api-version=7.0&%24format=zip"
  ;;

  * )
    abort "Unsupported OS distribution"
  ;;
esac

ret=0
"${MKDIR}" -p Uncrustify-analysis
cd Uncrustify-analysis || ret=$?
if [ $ret -ne 0 ]; then
  abort "Failed to cd to Uncrustify-analysis directory with code ${ret}"
fi

echo "Downloading Uncrustify..."
"${CURL}" -LfsS "${UNCRUSTIFY_LINK}" -o "${UNCRUSTIFY_ARCHIVE}" || ret=$?
if [ $ret -ne 0 ]; then
  abort "Failed to download Uncrustify with code ${ret}"
fi

"${UNZIP}" -q "${UNCRUSTIFY_ARCHIVE}" || ret=$?
if [ $ret -ne 0 ]; then
  abort "Failed to decompress Uncrustify with code ${ret}"
fi

cd Executable || ret=$?
if [ $ret -ne 0 ]; then
  abort "Failed to cd to Uncrustify Executable with code ${ret}"
fi

export UNC_EXEC=./uncrustify
if [ "$(unamer)" = "Windows" ]; then
  export UNC_EXEC=./uncrustify.exe
fi

"${CHMOD}" a+x "${UNC_EXEC}" || ret=$?
if [ $ret -ne 0 ]; then
  abort "Failed to chmod ${UNC_EXEC} with code ${ret}"
fi

"${MV}" "${UNC_EXEC}" ../.. || ret=$?
if [ $ret -ne 0 ]; then
  abort "Failed to move ${UNC_EXEC} to parent directory with code ${ret}"
fi

cd ../..
"${RM}" -rf Uncrustify-analysis || ret=$?
if [ $ret -ne 0 ]; then
  abort "Failed to cleanup Uncrustify-analysis dir"
fi

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
