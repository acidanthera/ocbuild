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

if [ "${WORK_BRANCH}" = "" ]; then
  echo "ERROR: Working branch is empty!"
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
updaterepo "https://github.com/acidanthera/OpenCorePkg" OpenCorePkg "${WORK_BRANCH}" || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to clone OpenCorePkg branch ${WORK_BRANCH} with code ${ret}!"
  exit 1
fi

FILE_LIST="filelist.txt"
# Exclude MsvcMath32.c as it is written in asm
"${FIND}" ./OpenCorePkg ! -name 'MsvcMath32.c' -name '*.c' -o -name '*.h' > "${FILE_LIST}" || ret=$?
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
