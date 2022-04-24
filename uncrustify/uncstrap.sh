#!/bin/bash

#
#  uncstrap.sh
#  ocbuild
#
#  Copyright © 2022 PMheart. All rights reserved.
#

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
"${MKDIR}" -p Uncrustify-analysis
cd Uncrustify-analysis || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to cd to Uncrustify-analysis directory with code ${ret}!"
  exit 1
fi

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
"${RM}" -rf Executable || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to remove Executable directory with code ${ret}!"
  exit 1
fi

cd ..
FILE_LIST="filelist.txt"
"${FIND}" \
  . \
  \( \
    -path "./UDK" -o \
    -path "./Library/OcAppleImg4Lib/libDER" -o \
    -path "./Library/OcAppleImg4Lib/libDERImg4" -o \
    -path "./Library/OcCompressionLib/lzss" -o \
    -path "./Library/OcCompressionLib/lzvn" -o \
    -path "./Library/OcCompressionLib/zlib" -o \
    -path "./Library/OcMp3Lib/helix" -o \
    -path "./Staging/OpenHfsPlus" -o \
    -path "./Utilities/acdtinfo" -o \
    -path "./Utilities/BaseTools" -o \
    -path "./Utilities/disklabel" -o \
    -path "./Utilities/EfiResTool" -o \
    -path "./Utilities/icnspack" -o \
    -path "./Utilities/RsaTool" -o \
    -path "./Utilities/WinNvram" -o \
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

./Uncrustify-analysis/uncrustify -c ./Uncrustify-analysis/"${UNCRUSTIFY_CONFIG_FILE}" -F "${FILE_LIST}" --replace --no-backup --if-changed
"${RM}" -rf Uncrustify-analysis "${FILE_LIST}" || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to cleanup Uncrustify-analysis dir and file list!"
  exit 1
fi

git diff > ../uncrustify.diff || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to generate uncrustify diff with code ${ret}!"
  exit 1
fi

exit 0
