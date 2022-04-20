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


PROJECT_PATH="$(pwd)"
# shellcheck disable=SC2181
if [ $? -ne 0 ] || [ ! -d "${PROJECT_PATH}" ]; then
  echo "ERROR: Failed to determine working directory!"
  exit 1
fi

if [ "${COVERITY_SCAN_TOKEN}" = "" ]; then
  echo "ERROR: No COVERITY_SCAN_TOKEN provided!"
  exit 1
fi

if [ "${COVERITY_SCAN_EMAIL}" = "" ]; then
  echo "ERROR: No COVERITY_SCAN_EMAIL provided!"
  exit 1
fi

if [ "${GITHUB_REPOSITORY}" = "" ]; then
  echo "ERROR: No GITHUB_REPOSITORY provided!"
  exit 1
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
    echo "ERROR: Missing ${tool}!"
    exit 1
  fi
done

if [ "$(which gpg)" = "" ]; then
  echo "ERROR: Missing GPG installation!"
fi

# Download Coverity
COVERITY_SCAN_DIR="${PROJECT_PATH}/cov-scan"
COVERITY_SCAN_ARCHIVE=cov-analysis.dmg
COVERITY_SCAN_INSTALLER=cov-analysis.sh
COVERITY_SCAN_LINK="https://scan.coverity.com/download/cxx/macOSX"

ret=0
echo "Downloading Coverity build tool..."
"${CURL}" -LfsS "${COVERITY_SCAN_LINK}" -d "token=${COVERITY_SCAN_TOKEN}&project=${GITHUB_REPOSITORY}" -o "${COVERITY_SCAN_ARCHIVE}" || ret=$?

if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to download Coverity build tool with code ${ret}!"
  exit 1
fi

hdiutil attach "${COVERITY_SCAN_ARCHIVE}" || ret=$?

if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to mount Coverity build tool with code ${ret}!"
  exit 1
fi

cp "$(ls /Volumes/cov-analysis-macosx-*/cov-analysis-macosx-*)" "${COVERITY_SCAN_INSTALLER}" || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to copy Coverity installer with code ${ret}!"
  exit 1
fi

mkdir -p cov-analysis
cd cov-analysis || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to cd to cov-analysis ${ret}!"
  exit 1
fi

../"${COVERITY_SCAN_INSTALLER}" || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to extract Coverity build tool with code ${ret}!"
  exit 1
fi

COVERITY_EXTRACT_DIR=$(pwd)

if [ "${COVERITY_EXTRACT_DIR}" = "" ]; then
  echo "ERROR: Failed to find Coverity build tool directory!"
  exit 1
fi

cd ..

"${RM}" -rf "${COVERITY_SCAN_DIR}"
"${MV}" "${COVERITY_EXTRACT_DIR}" "${COVERITY_SCAN_DIR}" || ret=$?

if [ "${COVERITY_EXTRACT_DIR}" = "" ]; then
  echo "ERROR: Failed to move Coverity build tool from ${COVERITY_EXTRACT_DIR} to ${COVERITY_SCAN_DIR}!"
  exit 1
fi

# Coverity compatibility tools
COV_TOOLS_URL="https://raw.githubusercontent.com/acidanthera/ocbuild/master/coverity/"
COV_TOOLS=(
  "cov-csrutil"
)

# Export override variables
export COVERITY_RESULTS_DIR="${PROJECT_PATH}/cov-int"
export COVERITY_TOOLS_DIR="${PROJECT_PATH}/cov-tools"

export COVERITY_CSRUTIL_PATH="${COVERITY_TOOLS_DIR}/cov-csrutil"
export CC="/usr/bin/clang"
export CXX="/usr/bin/clang++"

# Prepare directory structure
"${RM}" -rf "${COVERITY_TOOLS_DIR}"
"${MKDIR}" "${COVERITY_TOOLS_DIR}" || ret=$?
if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to create cov-tools directory ${COVERITY_TOOLS_DIR} with code ${ret}!"
  exit 1
fi

# Prepare tools
cd cov-tools || exit 1

# Download tools to override
for tool in "${COV_TOOLS[@]}"; do
  url="${COV_TOOLS_URL}/${tool}"
  "${CURL}" -LfsO "${url}" || ret=$?
  if [ $ret -ne 0 ]; then
    echo "ERROR: Failed to download ${tool} with code ${ret}!"
    exit 1
  fi
  "${CHMOD}" a+x "${tool}" || ret=$?
  if [ $ret -ne 0 ]; then
    echo "ERROR: Failed to chmod ${tool} with code ${ret}!"
    exit 1
  fi
done

# Done with tools
cd .. || exit 1

# Refresh PATH to apply overrides
export PATH="${COVERITY_TOOLS_DIR}:${COVERITY_SCAN_DIR}/bin:${PATH}"

# Run Coverity
export COVERITY_UNSUPPORTED=1
# shellcheck disable=SC2086
cov-build --dir "${COVERITY_RESULTS_DIR}" ${COVERITY_BUILD_COMMAND} || ret=$?

if [ $ret -ne 0 ]; then
  echo "ERROR: Coverity build tool failed with code ${ret}!"
  exit 1
fi

# Upload results
COVERITY_RESULTS_FILE=results.tgz
${TAR} czf "${COVERITY_RESULTS_FILE}" -C "${COVERITY_RESULTS_DIR}/.." "$(basename "${COVERITY_RESULTS_DIR}")" || ret=$?

if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to compress Coverity results dir ${COVERITY_RESULTS_DIR} with code ${ret}!"
  exit 1
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
  upload && exit 0 || ret=$?
done

echo "ERROR: Failed to upload Coverity results ${COVERITY_RESULTS_FILE} with code ${ret}!"
exit 1
