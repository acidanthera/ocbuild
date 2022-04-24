#!/bin/bash

#
#  uncstrap.sh
#  ocbuild
#
#  Copyright © 2022 PMheart. All rights reserved.
#

unamer() {
  NAME="$(uname)"

  if [ "$(echo "${NAME}" | grep MINGW)" != "" ] || [ "$(echo "${NAME}" | grep MSYS)" != "" ]; then
    echo "Windows"
  else
    echo "${NAME}"
  fi
}

updaterepo() {
  if [ ! -d "$2" ]; then
    git clone "$1" -b "$3" --depth=1 "$2" || exit 1
  fi
  pushd "$2" >/dev/null || exit 1
  git pull --rebase --autostash
  if [ "$2" != "UDK" ] && [ "$(unamer)" != "Windows" ]; then
    sym=$(find . -not -type d -not -path "./coreboot/*" -not -path "./UDK/*" -exec file "{}" ";" | grep CRLF)
    if [ "${sym}" != "" ]; then
      echo "Repository $1 named $2 contains CRLF line endings"
      echo "$sym"
      exit 1
    fi
  fi
  git submodule update --init --recommend-shallow || exit 1
  popd >/dev/null || exit 1
}

PROJECT_PATH="$(pwd)"
# shellcheck disable=SC2181
if [ $? -ne 0 ] || [ ! -d "${PROJECT_PATH}" ]; then
  echo "ERROR: Failed to determine working directory!"
  exit 1
fi

# Avoid conflicts with PATH overrides.
CHMOD="/bin/chmod"
CURL="/usr/bin/curl"
FIND="/usr/bin/find"
MKDIR="/bin/mkdir"
MV="/bin/mv"
RM="/bin/rm"
TAR="/usr/bin/tar"
UNZIP="/usr/bin/unzip"

TOOLS=(
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
    echo "ERROR: Missing ${tool}!"
    exit 1
  fi
done

# Download Uncrustify
# TODO: Find whether there are better ways to retrieve the latest version of Uncrustify.
UNCRUSTIFY_LINK="https://dev.azure.com/projectmu/271ca9de-dc2a-4567-ad0f-bde903c9ce7e/_apis/build/builds/12516/artifacts?artifactName=Executable&api-version=7.0&%24format=zip"
UNCRUSTIFY_ARCHIVE="uncrustify.zip"

UNCRUSTIFY_CONFIG_LINK="https://raw.githubusercontent.com/acidanthera/ocbuild/uncrustify/uncrustify/uncrustify.cfg"
UNCRUSTIFY_CONFIG_FILE="uncrustify.cfg"

ret=0
echo "Downloading Uncrustify..."
"${CURL}" -LfsS "${UNCRUSTIFY_LINK}" -o "${UNCRUSTIFY_ARCHIVE}" || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to download Uncrustify with code ${ret}!"
  exit 1
fi

echo "Downloading Uncrustify Config..."
"${CURL}" -LfsS "${UNCRUSTIFY_CONFIG_LINK}" -o "${UNCRUSTIFY_CONFIG_FILE}" || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to download Uncrustify Config with code ${ret}!"
  exit 1
fi

"${UNZIP}" -q "${UNCRUSTIFY_ARCHIVE}" || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to decompress Uncrustify with code ${ret}!"
  exit 1
fi

cd Executable || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to cd to Uncrustify Executable with code ${ret}!"
  exit 1
fi

"${CHMOD}" a+x ./uncrustify || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to chmod uncrustify with code ${ret}!"
  exit 1
fi

"${MV}" ./uncrustify .. || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to move uncrustify to parent directory with code ${ret}!"
  exit 1
fi

cd ..

# clone OpenCore repo
updaterepo "https://github.com/acidanthera/OpenCorePkg" OpenCorePkg master || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to clone OpenCorePkg/master with code ${ret}!"
  exit 1
fi

if [ "${PR_NUMBER}" != "" ]; then
  echo "Fetching Pull Request ${PR_NUMBER}..."

  git fetch origin "pull/${PR_NUMBER}/head:pr-${PR_NUMBER}" || ret=$?
  if [ $ret -ne 0 ]; then
    echo "ERROR: Failed to fetch OpenCorePkg PR ${PR_NUMBER} with code ${ret}!"
    exit 1
  fi

  git checkout "pr-${PR_NUMBER}" || ret=$?
  if [ $ret -ne 0 ]; then
    echo "ERROR: Failed to checkout OpenCorePkg to branch pr-${PR_NUMBER} with code ${ret}!"
    exit 1
  fi
fi

FILE_LIST="filelist.txt"
"${FIND}" \
  ./OpenCorePkg \
  \( \
    -path "./OpenCorePkg/UDK/*" -o \
    -path "./OpenCorePkg/Library/OcAppleImg4Lib/libDER/*" -o \
    -path "./OpenCorePkg/Library/OcAppleImg4Lib/libDERImg4/*" -o \
    -path "./OpenCorePkg/Library/OcCompressionLib/lzss/*" -o \
    -path "./OpenCorePkg/Library/OcCompressionLib/lzvn/*" -o \
    -path "./OpenCorePkg/Library/OcCompressionLib/zlib/*" -o \
    -path "./OpenCorePkg/Library/OcMp3Lib/helix/*" -o \
    -path "./OpenCorePkg/Staging/OpenHfsPlus/*" -o \
    -path "./OpenCorePkg/Utilities/acdtinfo/*" -o \
    -path "./OpenCorePkg/Utilities/BaseTools/*" -o \
    -path "./OpenCorePkg/Utilities/disklabel/*" -o \
    -path "./OpenCorePkg/Utilities/EfiResTool/*" -o \
    -path "./OpenCorePkg/Utilities/icnspack/*" -o \
    -path "./OpenCorePkg/Utilities/RsaTool/*" -o \
    -path "./OpenCorePkg/Utilities/WinNvram/*" -o \
    -name "RelocationCallGate.h" -o \
    -name "libDER_config.h" -o \
    -name "LegacyBcopy.h" -o \
    -name "MsvcMath32.c" -o \
    -name "lodepng.c" -o \
    -name "lodepng.h" -o \
    -name "Ubsan.c" -o \
    -name "Ubsan.h" -o \
    -name "UbsanPrintf.c" \
  \) \
  -prune -o \
  -type f \
  -name "*.[c\|h]" -print \
  > "${FILE_LIST}" || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to dump source file list to ${FILE_LIST}!"
  exit 1
fi

./uncrustify -c "${UNCRUSTIFY_CONFIG_FILE}" -F "${FILE_LIST}" --replace --no-backup --if-changed
cd OpenCorePkg || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to cd to OpenCorePkg directory!"
  exit 1
fi

git diff > ../uncrustify.diff || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to generate uncrustify diff with code ${ret}!"
  exit 1
fi

exit 0
