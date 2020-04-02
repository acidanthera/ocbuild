#!/bin/bash

unset WORKSPACE
unset PACKAGES_PATH

BUILDDIR=$(pwd)

prompt() {
  echo "$1"
  if [ "$FORCE_INSTALL" != "1" ]; then
    read -p "Enter [Y]es to continue: " v
    if [ "$v" != "Y" ] && [ "$v" != "y" ]; then
      exit 1
    fi
  fi
}

updaterepo() {
  if [ ! -d "$2" ]; then
    git clone "$1" -b "$3" --depth=1 "$2" || exit 1
  fi
  pushd "$2" >/dev/null
  git pull
  if [ "$2" != "UDK" ]; then
    sym=$(find . -not -type d -exec file "{}" ";" | grep CRLF)
    if [ "${sym}" != "" ]; then
      echo "Repository $1 named $2 contains CRLF line endings"
      echo "$sym"
      exit 1
    fi
  fi
  popd >/dev/null
}

abortbuild() {
  echo "Build failed!"
  tail -500 build.log
  exit 1
}

buildme() {
  build "$@" &> build.log
}

if [ "${SELFPKG}" = "" ]; then
  echo "You are required to set SELFPKG variable!"
  exit 1
fi

if [ "${BUILDDIR}" != "$(printf "%s\n" ${BUILDDIR})" ]; then
  echo "EDK2 build system may still fail to support directories with spaces!"
  exit 1
fi

if [ "$(which clang)" = "" ] || [ "$(which git)" = "" ] || [ "$(clang -v 2>&1 | grep "no developer")" != "" ] || [ "$(git -v 2>&1 | grep "no developer")" != "" ]; then
  echo "Missing Xcode tools, please install them!"
  exit 1
fi

if [ "$(nasm -v)" = "" ] || [ "$(nasm -v | grep Apple)" != "" ]; then
  echo "Missing or incompatible nasm!"
  echo "Download the latest nasm from http://www.nasm.us/pub/nasm/releasebuilds/"
  prompt "Install last tested version automatically?"
  pushd /tmp >/dev/null
  rm -rf nasm-mac64.zip
  curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/nasm-mac64.zip" || exit 1
  nasmzip=$(cat nasm-mac64.zip)
  rm -rf nasm-*
  curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/${nasmzip}" || exit 1
  unzip -q "${nasmzip}" nasm*/nasm nasm*/ndisasm || exit 1
  sudo mkdir -p /usr/local/bin || exit 1
  sudo mv nasm*/nasm /usr/local/bin/ || exit 1
  sudo mv nasm*/ndisasm /usr/local/bin/ || exit 1
  rm -rf "${nasmzip}" nasm-*
  popd >/dev/null
fi

if [ "$(which mtoc)" == "" ]; then
  echo "Missing mtoc!"
  echo "To build mtoc follow: https://github.com/tianocore/tianocore.github.io/wiki/Xcode#mac-os-x-xcode"
  prompt "Install prebuilt mtoc automatically?"
  pushd /tmp >/dev/null
  rm -f mtoc mtoc-mac64.zip
  curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/mtoc-mac64.zip" || exit 1
  mtoczip=$(cat mtoc-mac64.zip)
  rm -rf mtoc-*
  curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/${mtoczip}" || exit 1
  unzip -q "${mtoczip}" mtoc || exit 1
  sudo mkdir -p /usr/local/bin || exit 1
  sudo cp mtoc /usr/local/bin/mtoc || exit 1
  popd >/dev/null
fi

if [ "$RELPKG" = "" ]; then
  RELPKG="$SELFPKG"
fi

if [ "$ARCHS" = "" ]; then
  ARCHS=('X64')
fi

if [ "$TOOLCHAINS" = "" ]; then
  if [ "$(uname)" = "Darwin" ]; then
    TOOLCHAINS=('XCODE5')
  else
    TOOLCHAINS=('CLANGPDB' 'GCC5')
  fi
fi

if [ "$TARGETS" = "" ]; then
  TARGETS=('DEBUG' 'RELEASE' 'NOOPT')
fi

if [ "$RTARGETS" = "" ]; then
  RTARGETS=('DEBUG' 'RELEASE')
fi

SKIP_TESTS=0
SKIP_BUILD=0
SKIP_PACKAGE=0
MODE=""

while true; do
  if [ "$1" == "--skip-tests" ]; then
    SKIP_TESTS=1
    shift
  elif [ "$1" == "--skip-build" ]; then
    SKIP_BUILD=1
    shift
  elif [ "$1" == "--skip-package" ]; then
    SKIP_PACKAGE=1
    shift
  else
    break
  fi
done

if [ "$1" != "" ]; then
  MODE="$1"
  shift
fi

echo "Primary toolchain ${TOOLCHAINS[0]} and arch ${ARCHS[0]}"

if [ ! -d "Binaries" ]; then
  mkdir Binaries || exit 1
  cd Binaries || exit 1
  for target in ${TARGETS[@]}; do
    ln -s ../UDK/Build/"${RELPKG}/${target}_${TOOLCHAINS[0]}/${ARCHS[0]}" "${target}" || exit 1
  done
  cd .. || exit 1
fi

if [ ! -f UDK/UDK.ready ]; then
  rm -rf UDK

  sym=$(find . -not -type d -exec file "{}" ";" | grep CRLF)
  if [ "${sym}" != "" ]; then
    echo "Error: the following files in the repository CRLF line endings:"
    echo "$sym"
    exit 1
  fi
fi

updaterepo "https://github.com/acidanthera/audk" UDK master || exit 1
cd UDK
HASH=$(git rev-parse origin/master)

if [ -d ../Patches ]; then
  if [ ! -f patches.ready ]; then
    for i in ../Patches/* ; do
      git apply --ignore-whitespace "$i" || exit 1
      git add * || exit 1
      git commit -m "Applied patch $i" || exit 1
    done
    touch patches.ready
  fi
fi

deps="${#DEPNAMES[@]}"
for ((i=0; $i<$deps; i++)); do
  updaterepo "${DEPURLS[$i]}" "${DEPNAMES[$i]}" "${DEPBRANCHES[$i]}" || exit 1
done

if [ ! -d "${SELFPKG}" ]; then
  ln -s .. "${SELFPKG}" || exit 1
fi

source edksetup.sh || exit 1

if [ "$SKIP_TESTS" != "1" ]; then
  echo "Testing..."
  make -C BaseTools -j || exit 1
  touch UDK.ready
fi

if [ "$SKIP_BUILD" != "1" ]; then
  echo "Building..."
  for arch in ${ARCHS[@]} ; do
    for toolchain in ${TOOLCHAINS[@]}; do
      for target in ${TARGETS[@]}; do
        if [ "$MODE" = "" ] || [ "$MODE" = "$target" ]; then
          echo "Building ${SELFPKG}/${SELFPKG}.dsc for $arch in $target with ${toolchain}..."
          if declare -f travis_wait; then
            travis_wait 60 buildme -a "$arch" -b "$target" -t "${toolchain}" -p "${SELFPKG}/${SELFPKG}.dsc" || abortbuild
          else
            buildme -a "$arch" -b "$target" -t "${toolchain}" -p "${SELFPKG}/${SELFPKG}.dsc" || abortbuild
          fi
        fi
      done
    done
  done
fi

cd .. || exit 1

if [ "$(type -t package)" = "function" ]; then
  if [ "$SKIP_PACKAGE" != "1" ]; then
    echo "Packaging..."
    for rtarget in ${RTARGETS[@]}; do
      if [ "$PACKAGE" = "" ] || [ "$PACKAGE" = "$rtarget" ]; then
        package "Binaries/$rtarget" "$rtarget" "$HASH" || exit 1
      fi
    done
  fi
fi
