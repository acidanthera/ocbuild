#!/bin/bash

WORKDIR="$(pwd)"/tinylinux
SRCDIR="$WORKDIR"/src

if [ -z "${CROSS_COMPILE}" ]; then
  if [ "$(uname -m)" = "x86_64" ]; then
    CROSS_COMPILE=""
  else
    CROSS_COMPILE=x86_64-linux-gnu-
  fi
fi

if [ -z "${LINUX_KERNEL_TAG}" ]; then
  LINUX_KERNEL_TAG=v6.3-rc1
fi

if [ -z "${LINUX_REPO_URL}" ]; then
  LINUX_REPO_URL=https://github.com/torvalds/linux.git
fi

if [ -z "${BUSYBOX_VERSION}" ]; then
  BUSYBOX_VERSION=1.35.0
fi

GIT_COMMITER_EMAIL=unknown@unknown.com
GIT_COMMITER_NAME=unknown
BUILD_INITRD=false
BUILD_LINUX=false

xecho() {
  printf '%s\n' "[$(date)] $1"
}

xfatal() {
  xecho "\033[0;31m$1\033[0m"
  exit 1
}

usage() {
  echo "This script builds 32-bit and 64-bit tiny linux images with efistub"
  echo "and creates a TestLinux package located at external/TestLinux.zip."
  echo ""
  echo "The following arguments are accepted:"
  echo " --build-initrd build initrd.cpio.gz"
  echo " --build-linux  build x86 and x86_64 linux images"
  echo " --build        build TestLinux package"
  echo ""
  echo "The following environment variables are accepted:"
  echo " LINUX_KERNEL_TAG    Linux kernel git repo tag to clone"
  echo " LINUX_REPO_URL      Linux kernel git repo url"
  echo " BUSYBOX_VERSION     The version of busybox tarball"
  echo " CROSS_COMPILE       Specify cross toolchain prefix, for ex. x86_64-linux-gnu-"
  echo ""
  echo "Note 1: when just building linux you must ensure that you placed a correct initrd.cpio.gz "
  echo "      into tinylinux folder"
  echo "Note 2: when cross-compiling don't forget to install required packages, for Debian:
              libc6-dev-i386-amd64-cross
              gcc-x86-64-linux-gnu
              build-essential"
}

generate_initrd()
{
  # Remove the initrd directory if exists
  if [ -d "$WORKDIR"/initrd ]; then
    rm -r "$WORKDIR"/initrd || xfatal "Error removing initrd directory!"
  fi
  # Remove busybox tarball if exists
  if [ -f "$WORKDIR"/busybox.tar.bz2 ]; then
    rm "$WORKDIR"/busybox.tar.bz2 || xfatal "Error removing busybox.tar.bz2!"
  fi
  # Remove busybox sources
  if [ -d "$SRCDIR"/busybox-"$BUSYBOX_VERSION" ]; then
    rm -r "$SRCDIR"/busybox-"$BUSYBOX_VERSION" || xfatal "Error removing busybox src directory!"
  fi

  # Creating the initrd directory
  mkdir -p "$WORKDIR"/initrd || xfatal "Can't create initrd folder!"

  # Downloading busybox
  curl https://busybox.net/downloads/busybox-"$BUSYBOX_VERSION".tar.bz2 \
      --output "$WORKDIR"/busybox.tar.bz2 || xfatal "Downloading the busybox tarball failed!"

  # Unpacking into sources dir
  tar -xf "$WORKDIR"/busybox.tar.bz2 -C "$SRCDIR" || exit 1

  # Build 32-bit busybox and install its binaries into rootfs
  yes "" | make \
          CROSS_COMPILE="$CROSS_COMPILE" \
          -C "$SRCDIR"/busybox-"$BUSYBOX_VERSION"/ \
          defconfig || xfatal "Generating the busybox default config failed!"

  sed -i.orig 's/^#.*CONFIG_STATIC.*/CONFIG_STATIC=y/' "$SRCDIR"/busybox-"$BUSYBOX_VERSION"/.config

  make \
    CROSS_COMPILE="$CROSS_COMPILE" \
    -C "$SRCDIR"/busybox-"$BUSYBOX_VERSION"/ \
    clean || xfatal "Cleaning busybox build aftifacts failed"

  CPPFLAGS=-m32 LDFLAGS="-m32 --static" make -j"$(nproc)" CROSS_COMPILE="$CROSS_COMPILE" -C "$SRCDIR"/busybox-"$BUSYBOX_VERSION"/ install CONFIG_PREFIX="$WORKDIR"/initrd || xfatal "Busybox installation failed!"

  # Creating the bin dev proc and sys directories
  mkdir -p "$WORKDIR"/initrd/bin \
           "$WORKDIR"/initrd/dev \
           "$WORKDIR"/initrd/proc \
           "$WORKDIR"/initrd/sys \
           "$WORKDIR"/initrd/etc || xfatal "Can't create initrd subfolders!"

  # Silences the warning according missing fstab
  touch "$WORKDIR"/initrd/etc/fstab

  #Creating the init file which will be mounting the root file system
  cat <<EOT >> "$WORKDIR"/initrd/bin/init
#!/bin/sh
mount -t sysfs sysfs /sys
mount -t proc proc /proc
mount -t devtmpfs udev /dev
sysctl -w kernel.printk="2 4 1 7"
echo "Hello World!"
/bin/sh
poweroff -f
EOT

  chmod +x "$WORKDIR"/initrd/bin/init
  pushd "$WORKDIR"/initrd/ >/dev/null || exit 1
  ln -s ./bin/init init

  # Creating the initrd.cpio.gz
  fakeroot bash -c "chown -R root:root ""$WORKDIR""/initrd; mknod -m 666 ""$WORKDIR""/initrd/dev/console c 5 1; find . | cpio -o -H newc | gzip -9 > ""$WORKDIR""/initrd.cpio.gz" || xfatal "Generating initrd.cpio.gz failed!"
  popd >/dev/null || exit 1
}

build_linux_image() {
  local arch=$1
  if [ ! -d "$SRCDIR"/linux ]; then
    # Clone Linux source tree
    git clone --depth 1 --branch \
      "$LINUX_KERNEL_TAG" \
      "$LINUX_REPO_URL" \
      "$SRCDIR"/linux || xfatal "Cloning the Linux kernel source from ${LINUX_REPO_URL} with tag ${LINUX_KERNEL_TAG} failed!"

    # Applies patches
    pushd "$WORKDIR/src/linux" >/dev/null || exit 1

    git config user.email "$GIT_COMMITER_EMAIL"
    git config user.name "$GIT_COMMITER_NAME"

    git am --keep-cr --scissors --whitespace=fix \
      "$WORKDIR"/patches/linux/* || xfatal "Applying Linux patches using git am failed!"

    popd >/dev/null || exit 1
  fi
  # Copy initrd
  cp "$WORKDIR"/initrd.cpio.gz "$SRCDIR"/linux || xfatal "Copying initrd.cpio.gz failed, missing initrd?"
  # Prepare config
  if [ "$arch" = "X64" ]; then
    cp "$WORKDIR"/tiny_kernel_x86-64.config "$SRCDIR"/linux/.config || exit 1
  elif [ "$arch" = "IA32" ]; then
    cp "$WORKDIR"/tiny_kernel_x86.config "$SRCDIR"/linux/.config || exit 1
  else
    xfatal "Unsupported arch!"
  fi
  # Update config
  yes "" | make \
            ARCH=x86 \
            CROSS_COMPILE="$CROSS_COMPILE" \
            -C "$SRCDIR"/linux/ \
            oldconfig || xfatal "Updating kernel config failed!"
  # Build linux kernel
  make ARCH=x86 CROSS_COMPILE="$CROSS_COMPILE" -C "$SRCDIR"/linux clean || xfatal "Cleaning linux build aftifacts failed"
  make ARCH=x86 CROSS_COMPILE="$CROSS_COMPILE" -C "$SRCDIR"/linux -j"$(nproc)" || xfatal "Linux kernel compilation failed!"
  # Copy resulting kernel
  cp "$SRCDIR"/linux/arch/x86/boot/bzImage "$WORKDIR"/build/EFI/BOOT/BOOT"$arch".efi || exit 1
}

if [ "$(uname)" != "Linux" ]; then
  echo "Please run this script on Linux!"
  exit 1
fi

# Print usage
if [ $# -eq 0 ] || [ "$1" == "--help" ]; then
  usage
  exit 0
fi

# Parse arguments
while [ "$1" != "" ]; do
  if [ "$1" = "--build" ]; then
    BUILD_INITRD=true
    BUILD_LINUX=true
  elif [ "$1" = "--build-linux" ]; then
    BUILD_LINUX=true
  elif [ "$1" = "--build-initrd" ]; then
    BUILD_INITRD=true
  else
    xfatal "Found unsupported argument $1!"
  fi
  shift
done

# Checks that all required utils is available
if [ "$(which tar)" = "" ]; then
  xfatal "tar should be available!"
fi

if [ "$(which git)" = "" ]; then
  xfatal "git should be available!"
fi

if [ "$(which bzip2)" = "" ]; then
  xfatal "bzip2 should be available!"
fi

if [ "$(which curl)" = "" ]; then
  xfatal "curl should be available!"
fi

if [ "$(which fakeroot)" = "" ]; then
  xfatal "fakeroot should be available!"
fi

if [ "$(which xz)" = "" ]; then
  xfatal "xz should be available!"
fi

if [ "$(which xz)" = "" ]; then
  xfatal "flex should be available!"
fi

mkdir -p "$SRCDIR"
mkdir -p "$WORKDIR"/build/EFI/BOOT

if $BUILD_INITRD; then
  xecho "Creating initrd.cpio.gz"
  generate_initrd || xfatal "Error while generating initrd!"
  xecho "Done!"
fi

if $BUILD_LINUX; then
  xecho "Building Linux image x86_64"
  build_linux_image "X64" || xfatal "Error while building 64-bit Linux image!"
  xecho "Building Linux image x86"
  build_linux_image "IA32" || xfatal "Error while building 32-bit Linux image!"
  # Zipping TestLinux.zip
  pushd "$WORKDIR"/build >/dev/null || exit 1
  rm ../../external/TestLinux.zip
  zip -r ../../external/TestLinux.zip ./EFI
  popd >/dev/null || exit 1
  xecho "Done! Package placed $(pwd)/external/TestLinux.zip"
fi
