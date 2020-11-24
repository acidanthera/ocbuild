#!/bin/bash

#
#  covstrap.sh
#  Lilu
#
#  Copyright © 2018 vit9696. All rights reserved.
#

#
#  This script is supposed to quickly bootstrap Coverity Scan environment for GitHub Actions
#  to be later used with Lilu and plugins.
#
#  Latest version available at:
#  https://raw.githubusercontent.com/acidanthera/ocbuild/master/coverity/covstrap.sh
#
#  Example usage:
#  src=$(/usr/bin/curl -Lfs https://raw.githubusercontent.com/acidanthera/ocbuild/master/coverity/covstrap.sh) && eval "$src" || exit 1
#

PROJECT_PATH="$(pwd)"
if [ $? -ne 0 ] || [ ! -d "${PROJECT_PATH}" ]; then
  echo "ERROR: Failed to determine working directory!"
  exit 1
fi

# Avoid conflicts with PATH overrides.
CHMOD="/bin/chmod"
CURL="/usr/bin/curl"
MKDIR="/bin/mkdir"
RM="/bin/rm"
TAR="/usr/bin/tar"

TOOLS=(
  "${CHMOD}"
  "${CURL}"
  "${MKDIR}"
  "${RM}"
  "${TAR}"
)

for tool in "${TOOLS[@]}"; do
  if [ ! -x "${tool}" ]; then
    echo "ERROR: Missing ${tool}!"
    exit 1
  fi
done

# Download Coverity
COVERITY_SCAN_DIR="${PROJECT_PATH}/cov-scan"
COVERITY_SCAN_ARCHIVE=coverity_scan.tgz
COVERITY_SCAN_LINK="https://scan.coverity.com/download/macOSX?token=${COVERITY_SCAN_TOKEN}&project=${GITHUB_REPOSITORY}"

ret=0
echo "Downloading Coverity build tool..."
"${CURL}" -LfsS "${COVERITY_SCAN_LINK}" -o "${COVERITY_SCAN_ARCHIVE}" || ret=$?

if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to download Coverity build tool with code ${ret}!"
  exit 1
fi

"${RM}" -rf "${COVERITY_SCAN_DIR}"
"${MKDIR}" "${COVERITY_SCAN_DIR}" || ret=$?

if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to create cov-scan directory ${COVERITY_SCAN_DIR} with code ${ret}!"
  exit 1
fi

"${TAR}" xzf "${COVERITY_SCAN_ARCHIVE}" --strip 1 -C "${COVERITY_SCAN_DIR}" || ret=$?

if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to extract Coverity build tool ${COVERITY_SCAN_ARCHIVE} with code ${ret}!"
  exit 1
fi


# Coverity compatibility tools
COV_TOOLS_URL="https://raw.githubusercontent.com/acidanthera/ocbuild/master/coverity/"
COV_TOOLS=(
  "cov-cc"
  "cov-cxx"
  "cov-csrutil"
)

COV_OVERRIDES=(
  "clang"
  "clang++"
  "gcc"
  "g++"
)

COV_OVERRIDES_TARGETS=(
  "cov-cc"
  "cov-cxx"
  "cov-cc"
  "cov-cxx"
)

COV_OVERRIDE_NUM="${#COV_OVERRIDES[@]}"

# Export override variables
export COVERITY_RESULTS_DIR="${PROJECT_PATH}/cov-int"
export COVERITY_TOOLS_DIR="${PROJECT_PATH}/cov-tools"

export COVERITY_CSRUTIL_PATH="${COVERITY_TOOLS_DIR}/cov-csrutil"
export CC="${COVERITY_TOOLS_DIR}/cov-cc"
export CXX="${COVERITY_TOOLS_DIR}/cov-cxx"

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

# Generate compiler tools PATH overrides
for ((i=0; $i<$COV_OVERRIDE_NUM; i++)); do
  tool="${COV_OVERRIDES[$i]}"
  target="${COV_OVERRIDES_TARGETS[$i]}"
  echo "${target} \"\$@\"" > "${tool}" || ret=$?
  if [ $ret -ne 0 ]; then
    echo "ERROR: Failed to generate ${tool} override to ${target} with code ${ret}!"
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

${CURL} \
  --form project="${GITHUB_REPOSITORY}" \
  --form token="${COVERITY_SCAN_TOKEN}" \
  --form email="${COVERITY_SCAN_EMAIL}" \
  --form file="@${COVERITY_RESULTS_FILE}" \
  --form version="${GITHUB_SHA}" \
  --form description="GitHub Actions build" \
  "https://scan.coverity.com/builds?project=${GITHUB_REPOSITORY}" || ret=$?

if [ $ret -ne 0 ]; then
  echo "ERROR: Failed to upload Coverity results ${COVERITY_RESULTS_FILE} with code ${ret}!"
  exit 1
fi