#!/bin/bash

#
#  covstrap.sh
#  ocbuild
#
#  Copyright © 2018 vit9696. All rights reserved.
#

#
#  This script is supposed to quickly bootstrap Coverity Scan environment for GitHub Actions
#  to be later used with Acidanthera products.
#
#  Latest version available at:
#  https://raw.githubusercontent.com/acidanthera/ocbuild/master/coverity/covstrap.sh
#
#  Example usage:
#  src=$(/usr/bin/curl -Lfs https://raw.githubusercontent.com/acidanthera/ocbuild/master/coverity/covstrap.sh) && eval "$src" || exit 1
#

abort() {
  echo "ERROR: $1!"
  exit 1
}

PROJECT_PATH="$(pwd)"
# shellcheck disable=SC2181
if [ $? -ne 0 ] || [ ! -d "${PROJECT_PATH}" ]; then
  abort "Failed to determine working directory"
fi

if [ "${COVERITY_SCAN_TOKEN}" = "" ]; then
  abort "No COVERITY_SCAN_TOKEN provided"
fi

if [ "${COVERITY_SCAN_EMAIL}" = "" ]; then
  abort "No COVERITY_SCAN_EMAIL provided"
fi

if [ "${GITHUB_REPOSITORY}" = "" ]; then
  abort "No GITHUB_REPOSITORY provided"
fi

# Avoid conflicts with PATH overrides.
CHMOD="/bin/chmod"
CURL="/usr/bin/curl"
MKDIR="/bin/mkdir"
MV="/bin/mv"
RM="/bin/rm"
TAR="/usr/bin/tar"

TOOLS=(
  "${CHMOD}"
  "${CURL}"
  "${MKDIR}"
  "${MV}"
  "${RM}"
  "${TAR}"
)
for tool in "${TOOLS[@]}"; do
  if [ ! -x "${tool}" ]; then
    abort "Missing ${tool}"
  fi
done

# Download Coverity
COVERITY_SCAN_DIR="${PROJECT_PATH}/cov-scan"
COVERITY_SCAN_ARCHIVE=cov-analysis.dmg
COVERITY_SCAN_INSTALLER=cov-analysis.sh
COVERITY_SCAN_LINK="https://scan.coverity.com/download/cxx/macOS"

ret=0
echo "Downloading Coverity build tool..."
"${CURL}" -LfsS "${COVERITY_SCAN_LINK}" -d "token=${COVERITY_SCAN_TOKEN}&project=${GITHUB_REPOSITORY}" -o "${COVERITY_SCAN_ARCHIVE}" || ret=$?
if [ $ret -ne 0 ]; then
  abort "Failed to download Coverity build tool with code ${ret}"
fi

hdiutil attach "${COVERITY_SCAN_ARCHIVE}" || ret=$?
if [ $ret -ne 0 ]; then
  abort "Failed to mount Coverity build tool with code ${ret}"
fi

cp "$(ls /Volumes/cov-analysis-macosx-*/cov-analysis-macosx-*)" "${COVERITY_SCAN_INSTALLER}" || ret=$?
if [ $ret -ne 0 ]; then
  abort "Failed to copy Coverity installer with code ${ret}"
fi

mkdir -p cov-analysis
cd cov-analysis || ret=$?
if [ $ret -ne 0 ]; then
  abort "Failed to cd to cov-analysis ${ret}"
fi

../"${COVERITY_SCAN_INSTALLER}" || ret=$?
if [ $ret -ne 0 ]; then
  abort "Failed to extract Coverity build tool with code ${ret}"
fi

COVERITY_EXTRACT_DIR=$(pwd)
if [ "${COVERITY_EXTRACT_DIR}" = "" ]; then
  abort "Failed to find Coverity build tool directory"
fi

cd ..
"${RM}" -rf "${COVERITY_SCAN_DIR}"
"${MV}" "${COVERITY_EXTRACT_DIR}" "${COVERITY_SCAN_DIR}" || ret=$?
if [ "${COVERITY_EXTRACT_DIR}" = "" ]; then
  abort "Failed to move Coverity build tool from ${COVERITY_EXTRACT_DIR} to ${COVERITY_SCAN_DIR}"
fi

# Export override variables
export COVERITY_RESULTS_DIR="${PROJECT_PATH}/cov-int"
export CC="/usr/bin/clang"
export CXX="/usr/bin/clang++"

# Refresh PATH to apply overrides
export PATH="${COVERITY_SCAN_DIR}/bin:${PATH}"

# Run Coverity
export COVERITY_UNSUPPORTED=1
# Configure Coverity for an unsupported compiler.
cov-configure --clang || ret=$?
if [ $ret -ne 0 ]; then
  abort "Coverity configure for clang failed with code ${ret}"
fi
# shellcheck disable=SC2086
cov-build --dir "${COVERITY_RESULTS_DIR}" ${COVERITY_BUILD_COMMAND} || ret=$?
if [ $ret -ne 0 ]; then
  abort "Coverity build tool failed with code ${ret}"
fi

# Upload results
COVERITY_RESULTS_FILE=results.tgz
${TAR} czf "${COVERITY_RESULTS_FILE}" -C "${COVERITY_RESULTS_DIR}/.." "$(basename "${COVERITY_RESULTS_DIR}")" || ret=$?
if [ $ret -ne 0 ]; then
  abort "Failed to compress Coverity results dir ${COVERITY_RESULTS_DIR} with code ${ret}"
fi

upload () {
  ${CURL} \
    --form project="${GITHUB_REPOSITORY}" \
    --form token="${COVERITY_SCAN_TOKEN}" \
    --form email="${COVERITY_SCAN_EMAIL}" \
    --form file="@${COVERITY_RESULTS_FILE}" \
    --form version="${GITHUB_SHA}" \
    --form description="GitHub Actions build" \
    "https://scan.coverity.com/builds?project=${GITHUB_REPOSITORY}"
  return $?
}

for i in {1..3}
do
  echo "Uploading results... (Trial $i/3)"
  upload && exit 0 || ret=$?
done
abort "Failed to upload Coverity results ${COVERITY_RESULTS_FILE} with code ${ret}"
