#!/bin/bash

CCTOOLS_VERSION=949.0.1
CCTOOLS_NAME=cctools-${CCTOOLS_VERSION}
CCTOOLS_ARCHIVE=${CCTOOLS_NAME}.tar.gz
CCTOOLS_LINK=https://opensource.apple.com/tarballs/cctools/${CCTOOLS_ARCHIVE}
MTOC_ARCHIVE="mtoc-${CCTOOLS_VERSION}-macosx.zip"
MTOC_LATEST_ARCHIVE="mtoc-mac64.zip"
MTOC_LATEST_HASH="mtoc-mac64.sha256"

SRC_DIR=$(dirname "$0")
pushd "$SRC_DIR" &>/dev/null || exit 1
SRC_DIR="$(pwd)"
popd &>/dev/null || exit 1

BUILD_DIR="/tmp/cctools.$(uuidgen)"
CCTOOLS_DIR="${BUILD_DIR}/${CCTOOLS_NAME}"
DIST_DIR="${BUILD_DIR}/dist"

quit() {
  rm -rf "${BUILD_DIR}"
  exit "$1"
}

abort() {
  echo "$1"
  quit 1
}

prompt() {
  echo "$1"
  if [ "$FORCE_INSTALL" != "1" ]; then
    read -rp "Enter [Y]es to continue: " v
    if [ "$v" != "Y" ] && [ "$v" != "y" ]; then
      quit 0
    fi
  fi
}

rm -rf "${SRC_DIR}/external"/mtoc-*                      || abort "Cannot delete original mtoc files"
mkdir "${BUILD_DIR}"                                     || abort "Cannot create build dir ${BUILD_DIR}"
cd "${BUILD_DIR}"                                        || abort "Cannot switch to build dir ${BUILD_DIR}"
curl -OL "${CCTOOLS_LINK}"                               || abort "Cannot download cctools from ${CCTOOLS_LINK}"
tar -xf "${CCTOOLS_ARCHIVE}"                             || abort "Cannot extract cctools ${CCTOOLS_ARCHIVE}"
cd "${CCTOOLS_DIR}"                                      || abort "Cannot switch to cctools dir ${CCTOOLS_DIR}"
patch -p1 < "${SRC_DIR}/patches/mtoc-permissions.patch"  || abort "Cannot apply mtoc-permissions.patch"
make LTO= EFITOOLS=efitools -C libstuff                  || abort "Cannot build libstuff"
make -C efitools                                         || abort "Cannot build efitools"
strip -x "${CCTOOLS_DIR}/efitools/mtoc.NEW"              || abort "Cannot strip mtoc"
mkdir "${DIST_DIR}"                                      || abort "Cannot create dist dir ${DIST_DIR}"
cd "${DIST_DIR}"                                         || abort "Cannot switch to dist dir ${DIST_DIR}"
cp "${CCTOOLS_DIR}/efitools/mtoc.NEW" "${DIST_DIR}/mtoc" || abort "Cannot copy mtoc to ${DIST_DIR}"
zip -qry "${SRC_DIR}/external/${MTOC_ARCHIVE}" mtoc      || abort "Cannot archive mtoc into ${MTOC_ARCHIVE}"
cd "${SRC_DIR}/external"                                 || abort "Cannot switch to ${SRC_DIR}/external"
ln -s "${MTOC_ARCHIVE}" "${MTOC_LATEST_ARCHIVE}"         || abort "Cannot update ${MTOC_LATEST_ARCHIVE} symlink"
shasum -a 256 "${DIST_DIR}/mtoc" | cut -d' ' -f1 > "${SRC_DIR}/external/${MTOC_LATEST_HASH}" || abort "Cannot update hash"

echo "Done, do not forget to commit the changes!"
prompt "Update current installed mtoc?"

sudo mkdir -p "/usr/local/bin"                           || abort "Cannot create PATH dir /usr/local/bin"
sudo cp "${DIST_DIR}/mtoc" "/usr/local/bin/mtoc"         || abort "Cannot update /usr/local/bin/mtoc"
quit 0
