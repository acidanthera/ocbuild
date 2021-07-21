#!/bin/bash

ret=0

# Avoid conflicts with PATH overrides.
CHMOD="/bin/chmod"
CURL="/usr/bin/curl"
MKDIR="/bin/mkdir"
RM="/bin/rm"
UNZIP="/usr/bin/unzip"

if [ -z "${OVERRIDE_PYTHON3}" ]; then
  # Use whatever is in PATH
  OVERRIDE_PYTHON3=python3
fi

CLANG32_DIR="clang32"

CLANG32_SCRIPTS_URL="https://raw.githubusercontent.com/acidanthera/ocbuild/master/scripts/"
CLANG32_SCRIPTS=(
  "fix-macho32"
  "libtool32"
)

CLANG32_ZIP="clang-12.zip"

"${CURL}" -LfsO "https://github.com/acidanthera/ocbuild/releases/download/llvm-kext32-latest/${CLANG32_ZIP}" || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to download clang32 with code ${ret}!"
  exit 1
fi

"${MKDIR}" "${CLANG32_DIR}"
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to create clang32 directory with code ${ret}!"
  exit 1
fi

"${UNZIP}" -q "${CLANG32_ZIP}" -d "${CLANG32_DIR}" || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to extract downloaded clang32 with code ${ret}!"
  exit 1
fi

"${RM}" -rf "${CLANG32_ZIP}"

# Download tools to override
for tool in "${CLANG32_SCRIPTS[@]}"; do
  url="${CLANG32_SCRIPTS_URL}/${tool}"
  "${CURL}" -Lfs "${url}" -o "${CLANG32_DIR}/${tool}" || ret=$?
  if [ $ret -ne 0 ]; then
    echo "ERROR: Failed to download ${tool} with code ${ret}!"
    exit 1
  fi
  "${CHMOD}" a+x "${CLANG32_DIR}/${tool}" || ret=$?
  if [ $ret -ne 0 ]; then
    echo "ERROR: Failed to chmod ${tool} with code ${ret}!"
    exit 1
  fi
done

# macholib required for fix-macho32
"${OVERRIDE_PYTHON3}" -m pip install --disable-pip-version-check --user -q macholib || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to install macholib with code ${ret}!"
  exit 1
fi
