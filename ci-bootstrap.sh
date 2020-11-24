#!/bin/bash

XCODE_DIR="/Applications/Xcode_VERSION.app/Contents/Developer"

# In GitHub Actions:
# env:
#  PROJECT_TYPE: "UEFI"

case "${PROJECT_TYPE}" in 
    UEFI)
        BUILD_DEVELOPER_DIR="${XCODE_DIR/VERSION/12.2}"
        ANALYZE_DEVELOPER_DIR="${XCODE_DIR/VERSION/12.2}"
        COVERITY_DEVELOPER_DIR="${XCODE_DIR/VERSION/12.2}"
        ;;
    
    KEXT | TOOL)
        BUILD_DEVELOPER_DIR="${XCODE_DIR/VERSION/12.2}"
        ANALYZE_DEVELOPER_DIR="${XCODE_DIR/VERSION/12.2}"
        COVERITY_DEVELOPER_DIR="${XCODE_DIR/VERSION/12.2}"
        ;;
    
    *)
        echo "ERROR: Invalid project type!"
        exit 1
        ;;
esac

SELECTED_DEVELOPER_DIR="${JOB_TYPE}_DEVELOPER_DIR"

if [ -z "${!SELECTED_DEVELOPER_DIR}" ]; then
    echo "ERROR: Invalid or missing job type!"
    exit 1
fi

echo "DEVELOPER_DIR=${!SELECTED_DEVELOPER_DIR}" >> $GITHUB_ENV

# Since GITHUB_ENV doesn't affect the current step, need to export DEVELOPER_DIR for subsequent commands.
export DEVELOPER_DIR="${!SELECTED_DEVELOPER_DIR}"

# Print runner details
echo -e '\033[0;36mmacOS version\033[0m'
sw_vers

echo -e '\033[0;36mgit version\033[0m'
git --version

echo -e '\033[0;36mbash version\033[0m'
bash --version

echo -e '\033[0;36mclang version\033[0m'
clang --version

echo -e '\033[0;36mXcode version\033[0m'
xcode-select --print-path
