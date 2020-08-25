#!/bin/bash

unset WORKSPACE
unset PACKAGES_PATH

BUILDDIR=$(pwd)

prompt() {
  echo "$1"
  if [ "$FORCE_INSTALL" != "1" ]; then
    read -rp "Enter [Y]es to continue: " v
    if [ "$v" != "Y" ] && [ "$v" != "y" ]; then
      exit 1
    fi
  fi
}

updaterepo() {
  if [ ! -d "$2" ]; then
    git clone "$1" -b "$3" --depth=1 "$2" || exit 1
  fi
  pushd "$2" >/dev/null || exit 1
  git pull
  if [ "$2" != "UDK" ] && [ "$(unamer)" != "Windows" ]; then
    sym=$(find . -not -type d -exec file "{}" ";" | grep CRLF)
    if [ "${sym}" != "" ]; then
      echo "Repository $1 named $2 contains CRLF line endings"
      echo "$sym"
      exit 1
    fi
  fi
  git submodule update --init --recommend-shallow || exit 1
  popd >/dev/null || exit 1
}

abortbuild() {
  echo "Build failed!"
  tail -120 build.log
  exit 1
}

pingme() {
  local timeout=200 # in 30s
  local count=0
  local cmd_pid=$1
  shift

  while [ $count -lt $timeout ]; do
    count=$(( count + 1 ))
    printf "."
    sleep 30
  done

  ## ShellCheck Exception(s)
  ## https://github.com/koalaman/shellcheck/wiki/SC2028
  ## https://github.com/koalaman/shellcheck/wiki/SC2145
  # shellcheck disable=SC2028,SC2145
  echo "\n\033[31;1mTimeout reached. Terminating $@.\033[0m"
  kill -9 "${cmd_pid}"
}

buildme() {
  local cmd_pid
  local mon_pid
  local result

  build "$@" &>build.log &
  cmd_pid=$!

  pingme $! build "$@" &
  mon_pid=$!

  ## ShellCheck Exception(s)
  ## https://github.com/koalaman/shellcheck/wiki/SC2069
  # shellcheck disable=SC2069
  { wait $cmd_pid 2>/dev/null; result=$?; ps -p$mon_pid 2>&1>/dev/null && kill $mon_pid; } || return 1
  return $result
}

symlink() {
  if [ "$(unamer)" = "Windows" ]; then
    # This requires extra permissions.
    # cmd <<< "mklink /D \"$2\" \"${1//\//\\}\"" > /dev/null
    rm -rf "$2"
    mkdir -p "$2" || exit 1
    for i in "$1"/* ; do
      if [ "$(echo "${i}" | grep "$(basename "$(pwd)")")" != "" ]; then
        continue
      fi
      cp -r "$i" "$2" || exit 1
    done
  elif [ ! -d "$2" ]; then
    ln -s "$1" "$2" || exit 1
  fi
}

unamer() {
  NAME="$(uname)"

  if [ "$(echo "${NAME}" | grep MINGW)" != "" ] || [ "$(echo "${NAME}" | grep MSYS)" != "" ]; then
    echo "Windows"
  else
    echo "${NAME}"
  fi
}

echo "Building on $(unamer)"

if [ "$(unamer)" = "Windows" ]; then
  cmd <<< 'chcp 437'
  export PYTHON_COMMAND="python"
fi

if [ "${SELFPKG}" = "" ]; then
  echo "You are required to set SELFPKG variable!"
  exit 1
fi

if [ "${SELFPKG_DIR}" = "" ]; then
  SELFPKG_DIR="${SELFPKG}"
fi

if [ "${BUILDDIR}" != "$(printf "%s\n" "${BUILDDIR}")" ] ; then
  echo "EDK2 build system may still fail to support directories with spaces!"
  exit 1
fi

if [ "$(which git)" = "" ]; then
  echo "Missing git, please install it!"
  exit 1
fi

if [ "$(which zip)" = "" ]; then
  echo "Missing zip, please install it!"
  exit 1
fi

if [ "$(unamer)" = "Darwin" ]; then
  if [ "$(which clang)" = "" ] || [ "$(clang -v 2>&1 | grep "no developer")" != "" ] || [ "$(git -v 2>&1 | grep "no developer")" != "" ]; then
    echo "Missing Xcode tools, please install them!"
    exit 1
  fi
fi

# On Windows nasm and python may not be in PATH.
if [ "$(unamer)" = "Windows" ]; then
  export PATH="/c/Python38:$PATH:/c/Program Files/NASM:/c/tools/ASL"
fi

if [ "$(nasm -v)" = "" ] || [ "$(nasm -v | grep Apple)" != "" ]; then
  echo "Missing or incompatible nasm!"
  echo "Download the latest nasm from http://www.nasm.us/pub/nasm/releasebuilds"
  echo "Current PATH: $PATH -- $(which nasm)"
  # On Darwin we can install prebuilt nasm. On Linux let users handle it.
  if [ "$(unamer)" = "Darwin" ]; then
    prompt "Install last tested version automatically?"
  else
    exit 1
  fi
  pushd /tmp >/dev/null || exit 1
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
  popd >/dev/null || exit 1
fi

if [ "$(iasl -v)" = "" ]; then
  echo "Missing iasl!"
  echo "Download the latest iasl from https://acpica.org/downloads"
  # On Darwin we can install prebuilt iasl. On Linux let users handle it.
  if [ "$(unamer)" = "Darwin" ]; then
    prompt "Install last tested version automatically?"
  else
    exit 1
  fi
  pushd /tmp >/dev/null || exit 1
  rm -rf iasl-macosx.zip
  curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/iasl-macosx.zip" || exit 1
  iaslzip=$(cat iasl-macosx.zip)
  rm -rf iasl
  curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/${iaslzip}" || exit 1
  unzip -q "${iaslzip}" iasl || exit 1
  sudo mkdir -p /usr/local/bin || exit 1
  sudo mv iasl /usr/local/bin/ || exit 1
  rm -rf "${iaslzip}" iasl
  popd >/dev/null || exit 1
fi

if [ "${MTOC_HASH}" = "" ]; then
  MTOC_HASH=$(curl -L "https://github.com/acidanthera/ocbuild/raw/master/external/mtoc-mac64.sha256") || exit 1
fi

if [ "${MTOC_HASH}" = "" ]; then
  echo "Cannot obtain the latest compatible mtoc hash!"
  exit 1
fi

# On Darwin we need mtoc. Only for XCODE5, but do not care for now.
if [ "$(unamer)" = "Darwin" ]; then
  valid_mtoc=false
else
  valid_mtoc=true
fi

if [ "$(which mtoc)" != "" ]; then
  mtoc_path=$(which mtoc)
  mtoc_hash_user=$(shasum -a 256 "${mtoc_path}" | cut -d' ' -f1)
  if [ "${MTOC_HASH}" = "${mtoc_hash_user}" ]; then
    valid_mtoc=true
  elif [ "${IGNORE_MTOC_VERSION}" = "1" ]; then
    echo "Forcing the use of UNKNOWN mtoc version due to IGNORE_MTOC_VERSION=1"
    valid_mtoc=true
  elif [ "${mtoc_path}" != "/usr/local/bin/mtoc" ]; then
    echo "Custom UNKNOWN mtoc is installed to ${mtoc_path}!"
    echo "Hint: Remove this mtoc or use IGNORE_MTOC_VERSION=1 at your own risk."
    exit 1
  else
    echo "Found incompatible mtoc installed to ${mtoc_path}!"
    echo "Expected SHA-256: ${MTOC_HASH}"
    echo "Found SHA-256:    ${mtoc_hash_user}"
    echo "Hint: Reinstall this mtoc or use IGNORE_MTOC_VERSION=1 at your own risk."
  fi
fi

if ! $valid_mtoc; then
  echo "Missing or incompatible mtoc!"
  echo "To build mtoc follow: https://github.com/tianocore/tianocore.github.io/wiki/Xcode#mac-os-x-xcode"
  prompt "Install prebuilt mtoc automatically?"
  pushd /tmp >/dev/null || exit 1
  rm -f mtoc mtoc-mac64.zip
  curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/mtoc-mac64.zip" || exit 1
  mtoczip=$(cat mtoc-mac64.zip)
  rm -rf mtoc-*
  curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/${mtoczip}" || exit 1
  unzip -q "${mtoczip}" mtoc || exit 1
  sudo mkdir -p /usr/local/bin || exit 1
  sudo rm -f /usr/local/bin/mtoc /usr/local/bin/mtoc.NEW || exit 1
  sudo cp mtoc /usr/local/bin/mtoc || exit 1
  popd >/dev/null || exit 1

  mtoc_path=$(which mtoc)
  mtoc_hash_user=$(shasum -a 256 "${mtoc_path}" | cut -d' ' -f1)
  if [ "${MTOC_HASH}" != "${mtoc_hash_user}" ]; then
    echo "Failed to install a compatible version of mtoc!"
    echo "Expected SHA-256: ${MTOC_HASH}"
    echo "Found SHA-256:    ${mtoc_hash_user}"
    exit 1
  fi
fi

if [ "$RELPKG" = "" ]; then
  RELPKG="$SELFPKG"
fi

if [ "$ARCHS" = "" ]; then
  ARCHS=('X64')
fi

if [ "$TOOLCHAINS" = "" ]; then
  if [ "$(unamer)" = "Darwin" ]; then
    TOOLCHAINS=('XCODE5')
  elif [ "$(unamer)" = "Windows" ]; then
    TOOLCHAINS=('VS2017')
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
fi

if [ ! -f UDK/UDK.ready ]; then
  rm -rf UDK

  if [ "$(unamer)" != "Windows" ]; then
    sym=$(find . -not -type d -exec file "{}" ";" | grep CRLF)
    if [ "${sym}" != "" ]; then
      echo "Error: the following files in the repository CRLF line endings:"
      echo "$sym"
      exit 1
    fi
  fi
fi

updaterepo "https://github.com/acidanthera/audk" UDK master || exit 1
cd UDK || exit 1
HASH=$(git rev-parse origin/master)

if [ -d ../Patches ]; then
  if [ ! -f patches.ready ]; then
    git config user.name ocbuild
    git config user.email ocbuild@acidanthera.local
    for i in ../Patches/* ; do
      git apply --ignore-whitespace "$i" || exit 1
      git add .
      git commit -m "Applied patch $i" || exit 1
    done
    touch patches.ready
  fi
fi

deps="${#DEPNAMES[@]}"
for (( i=0; i<deps; i++ )) ; do
  updaterepo "${DEPURLS[$i]}" "${DEPNAMES[$i]}" "${DEPBRANCHES[$i]}" || exit 1
done

# Allow building non-self packages.
if [ ! -e "${SELFPKG_DIR}" ]; then
  symlink .. "${SELFPKG_DIR}" || exit 1
fi

source edksetup.sh || exit 1

if [ "$SKIP_TESTS" != "1" ]; then
  echo "Testing..."
  if [ "$(unamer)" = "Windows" ]; then
    # Configure Visual Studio environment. Requires:
    # 1. choco install microsoft-build-tools visualcpp-build-tools nasm zip
    # 2. iasl in PATH for MdeModulePkg
    tools="${EDK_TOOLS_PATH}"
    tools="${tools//\//\\}"
    tools="${tools/\\c\\/C:\\}"
    echo "Expanded EDK_TOOLS_PATH from ${EDK_TOOLS_PATH} to ${tools}"
    export EDK_TOOLS_PATH="${tools}"
    export BASE_TOOLS_PATH="${tools}"
    VS2017_BUILDTOOLS="C:\\Program Files (x86)\\Microsoft Visual Studio\\2017\\BuildTools"
    VS2017_BASEPREFIX="${VS2017_BUILDTOOLS}\\VC\\Tools\\MSVC\\"
    # Intended to use ls here to get first entry.
    # REF: https://github.com/koalaman/shellcheck/wiki/SC2012
    # shellcheck disable=SC2012
    cd "${VS2017_BASEPREFIX}" || exit 1
    # Incorrect diagnostic due to action.
    # REF: https://github.com/koalaman/shellcheck/wiki/SC2035
    # shellcheck disable=SC2035
    VS2017_DIR="$(find * -maxdepth 0 -type d -print -quit)"
    if [ "${VS2017_DIR}" = "" ]; then
      echo "No VS2017 MSVC compiler"
      exit 1
    fi
    cd - || exit 1
    export VS2017_PREFIX="${VS2017_BASEPREFIX}${VS2017_DIR}\\"

    WINSDK_BASE="/c/Program Files (x86)/Windows Kits/10/bin"
    if [ -d "${WINSDK_BASE}" ]; then
      for dir in "${WINSDK_BASE}"/*/; do
        if [ -f "${dir}x86/rc.exe" ]; then
          WINSDK_PATH_FOR_RC_EXE="${dir}x86/rc.exe"
          WINSDK_PATH_FOR_RC_EXE="${WINSDK_PATH_FOR_RC_EXE//\//\\}"
          WINSDK_PATH_FOR_RC_EXE="${WINSDK_PATH_FOR_RC_EXE/\\c\\/C:\\}"
          break
        fi
      done
    fi
    if [ "${WINSDK_PATH_FOR_RC_EXE}" != "" ]; then
      export WINSDK_PATH_FOR_RC_EXE
    else
      echo "Failed to find rc.exe"
      exit 1
    fi
    BASE_TOOLS="$(pwd)/BaseTools"
    export PATH="${BASE_TOOLS}/Bin/Win32:${BASE_TOOLS}/BinWrappers/WindowsLike:$PATH"
    # Extract header paths for cl.exe to work.
    eval "$(python -c '
import sys, os, subprocess
import distutils.msvc9compiler as msvc
msvc.find_vcvarsall=lambda _: sys.argv[1]
envs=msvc.query_vcvarsall(sys.argv[2])
for k,v in envs.items():
    k = k.upper()
    v = ":".join(subprocess.check_output(["cygpath","-u",p]).decode("ascii").rstrip() for p in v.split(";"))
    v = v.replace("'\''",r"'\'\\\'\''")
    print("export %(k)s='\''%(v)s'\''" % locals())
' "${VS2017_BUILDTOOLS}\\Common7\\Tools\\VsDevCmd.bat" '-arch=amd64')"
    # Normal build similar to Unix.
    cd BaseTools || exit 1
    nmake        || exit 1
    cd ..        || exit 1
  else
    make -C BaseTools -j || exit 1
  fi
  touch UDK.ready
fi

if [ "$SKIP_BUILD" != "1" ]; then
  echo "Building..."
  for arch in "${ARCHS[@]}" ; do
    for toolchain in "${TOOLCHAINS[@]}" ; do
      for target in "${TARGETS[@]}" ; do
        if [ "$MODE" = "" ] || [ "$MODE" = "$target" ]; then
          echo "Building ${SELFPKG_DIR}/${SELFPKG}.dsc for $arch in $target with ${toolchain}..."
          buildme -a "$arch" -b "$target" -t "${toolchain}" -p "${SELFPKG_DIR}/${SELFPKG}.dsc" || abortbuild
          echo " - OK"
        fi
      done
    done
  done
fi

cd .. || exit 1

if [ "$(type -t package)" = "function" ]; then
  if [ "$SKIP_PACKAGE" != "1" ]; then
    echo "Packaging..."
    if [ "$NO_ARCHIVES" != "1" ]; then
      rm -f Binaries/*.zip
    fi
    for rtarget in "${RTARGETS[@]}" ; do
      if [ "$PACKAGE" = "" ] || [ "$PACKAGE" = "$rtarget" ]; then
        package "UDK/Build/${RELPKG}/${rtarget}_${TOOLCHAINS[0]}/${ARCHS[0]}" "$rtarget" "$HASH" || exit 1
        if [ "$NO_ARCHIVES" != "1" ]; then
          cp "UDK/Build/${RELPKG}/${rtarget}_${TOOLCHAINS[0]}/${ARCHS[0]}"/*.zip Binaries || echo skipping
        fi
      fi
    done
  fi
fi
