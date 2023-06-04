#!/bin/bash

WORKDIR="$(pwd)"/tinylinux
SRCDIR="$WORKDIR"/src

if [ -z "${CROSS_COMPILE_ARM}" ]; then
    CROSS_COMPILE_ARM="arm-linux-gnueabi-"
fi

if [ -z "${CROSS_COMPILE_X86}" ]; then
  if [ "$(uname -m)" = "x86_64" ]; then
    CROSS_COMPILE_X86=""
  else
    CROSS_COMPILE_X86=x86_64-linux-gnu-
  fi
fi

if [ -z "${CROSS_COMPILE_ARM64}" ]; then
  if [ "$(uname -m)" = "x86_64" ]; then
    CROSS_COMPILE_ARM64="aarch64-linux-gnu-"
  else
    CROSS_COMPILE_ARM64=""
  fi
fi

if [ -z "${LINUX_KERNEL_TAG}" ]; then
  LINUX_KERNEL_TAG=v5.10.179
fi

if [ -z "${LINUX_REPO_URL}" ]; then
  LINUX_REPO_URL=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
fi

if [ -z "${BUSYBOX_VERSION}" ]; then
  BUSYBOX_VERSION=1.36.0
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
  echo "Currenty supported HOST arches is x86_64 and aarch64"
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
  echo " CROSS_COMPILE_X86   Specify cross toolchain prefix for X86 targets, for ex. x86_64-linux-gnu-"
  echo " CROSS_COMPILE_ARM   Specify cross toolchain prefix for ARM 32-bit targets, for ex. arm-linux-gnueabi-"
  echo " CROSS_COMPILE_ARM64 Specify cross toolchain prefix for ARM 64-bit targets, for ex. aarch64-linux-gnu-"
  echo ""
  echo "Note 1: when just building linux you must ensure that you placed a correct initrd.cpio.gz "
  echo "      into tinylinux folder"
  echo "Note 2: when cross-compiling don't forget to install required packages, for Debian:
              libc6-dev-i386-amd64-cross
              gcc-x86-64-linux-gnu
              lib32gcc-GCC_VERSION-dev-amd64-cross
              build-essential"
}

generate_initrd()
{
  local arch=$1
  local cross_compile=$2
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
          ARCH="$arch" \
          CROSS_COMPILE="$cross_compile" \
          -C "$SRCDIR"/busybox-"$BUSYBOX_VERSION"/ \
          defconfig || xfatal "Generating the busybox default config failed!"

  sed -i.orig 's/^#.*CONFIG_STATIC.*/CONFIG_STATIC=y/' "$SRCDIR"/busybox-"$BUSYBOX_VERSION"/.config

  make \
    ARCH="$arch" \
    CROSS_COMPILE="$cross_compile" \
    -C "$SRCDIR"/busybox-"$BUSYBOX_VERSION"/ \
    clean || xfatal "Cleaning busybox build aftifacts failed"

  if [ "$arch" = "i386" ]; then
    CPPFLAGS=-m32 LDFLAGS="-m32 --static" make -j"$(nproc)" ARCH="$arch" CROSS_COMPILE="$cross_compile" -C "$SRCDIR"/busybox-"$BUSYBOX_VERSION"/ install CONFIG_PREFIX="$WORKDIR"/initrd || xfatal "Busybox installation failed!"
  elif [ "$arch" = "arm" ]; then
    CPPFLAGS=-mbe32 LDFLAGS="-mbe32 --static" make -j"$(nproc)" ARCH="$arch" CROSS_COMPILE="$cross_compile" -C "$SRCDIR"/busybox-"$BUSYBOX_VERSION"/ install CONFIG_PREFIX="$WORKDIR"/initrd || xfatal "Busybox installation failed!"
  fi

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
  fakeroot bash -c "chown -R root:root ""$WORKDIR""/initrd; mknod -m 666 ""$WORKDIR""/initrd/dev/console c 5 1; find . | cpio -o -H newc | gzip -9 > ""$WORKDIR""/initrd_""$arch"".cpio.gz" || xfatal "Generating initrd.cpio.gz failed!"
  popd >/dev/null || exit 1
}

build_linux_image() {
  local arch=$1
  local cross_compile=$2
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
      "$WORKDIR"/patches/linux/"$LINUX_KERNEL_TAG"/* || xfatal "Applying Linux patches using git am failed!"

    popd >/dev/null || exit 1
  fi

  # Prepare config
  if [ "$arch" = "X64" ]; then
    cp "$WORKDIR"/configs/linux/"$LINUX_KERNEL_TAG"/tiny_kernel_x86-64.config "$SRCDIR"/linux/.config || exit 1
  elif [ "$arch" = "IA32" ]; then
    cp "$WORKDIR"/configs/linux/"$LINUX_KERNEL_TAG"/tiny_kernel_x86.config "$SRCDIR"/linux/.config || exit 1
  elif [ "$arch" = "ARM" ]; then
    cp "$WORKDIR"/configs/linux/"$LINUX_KERNEL_TAG"/tiny_kernel_arm.config "$SRCDIR"/linux/.config || exit 1
  elif [ "$arch" = "AARCH64" ]; then
    cp "$WORKDIR"/configs/linux/"$LINUX_KERNEL_TAG"/tiny_kernel_arm64.config "$SRCDIR"/linux/.config || exit 1
  else
    xfatal "Unsupported arch!"
  fi
  if [ "$arch" = "X64" ] || [ "$arch" = "IA32" ]; then
    # Copy initrd
    cp "$WORKDIR"/initrd_i386.cpio.gz "$SRCDIR"/linux || xfatal "Copying initrd_i386.cpio.gz failed, missing initrd?"
    # Update config
    yes "" | make \
              ARCH=x86 \
              CROSS_COMPILE="$cross_compile" \
              -C "$SRCDIR"/linux/ \
              oldconfig || xfatal "Updating kernel config failed!"
    # Build linux kernel
    make ARCH=x86 CROSS_COMPILE="$cross_compile" -C "$SRCDIR"/linux clean || xfatal "Cleaning linux build aftifacts failed"
    make ARCH=x86 CROSS_COMPILE="$cross_compile" -C "$SRCDIR"/linux -j"$(nproc)" || xfatal "Linux kernel compilation failed!"
    # Copy resulting kernel
    cp "$SRCDIR"/linux/arch/x86/boot/bzImage "$WORKDIR"/build/EFI/BOOT/BOOT"$arch".efi || exit 1
  elif [ "$arch" = "ARM" ]; then
    # Copy initrd
    cp "$WORKDIR"/initrd_arm.cpio.gz "$SRCDIR"/linux || xfatal "Copying initrd_arm.cpio.gz failed, missing initrd?"
    # Update config
    yes "" | make \
              ARCH=arm \
              CROSS_COMPILE="$cross_compile" \
              -C "$SRCDIR"/linux/ \
              oldconfig || xfatal "Updating kernel config failed!"
    # Build linux kernel
    make ARCH=arm CROSS_COMPILE="$cross_compile" -C "$SRCDIR"/linux clean || xfatal "Cleaning linux build aftifacts failed"
    make ARCH=arm CROSS_COMPILE="$cross_compile" -C "$SRCDIR"/linux -j"$(nproc)" || xfatal "Linux kernel compilation failed!"
    # Copy resulting kernel
    cp "$SRCDIR"/linux/arch/arm/boot/zImage "$WORKDIR"/build/EFI/BOOT/BOOT"$arch".efi || exit 1
  elif [ "$arch" = "AARCH64" ]; then
    # Copy initrd
    cp "$WORKDIR"/initrd_arm.cpio.gz "$SRCDIR"/linux || xfatal "Copying initrd_arm.cpio.gz failed, missing initrd?"
    # Update config
    yes "" | make \
              ARCH=arm64 \
              CROSS_COMPILE="$cross_compile" \
              -C "$SRCDIR"/linux/ \
              oldconfig || xfatal "Updating kernel config failed!"
    # Build linux kernel
    make ARCH=arm64 CROSS_COMPILE="$cross_compile" -C "$SRCDIR"/linux clean || xfatal "Cleaning linux build aftifacts failed"
    make ARCH=arm64 CROSS_COMPILE="$cross_compile" -C "$SRCDIR"/linux -j"$(nproc)" || xfatal "Linux kernel compilation failed!"
    # Copy resulting kernel
    if [ "${LINUX_KERNEL_TAG}" = "v6.3" ]; then
      cp "$SRCDIR"/linux/arch/arm64/boot/vmlinuz.efi "$WORKDIR"/build/EFI/BOOT/BOOTAA64.efi || exit 1
    else
      cp "$SRCDIR"/linux/arch/arm64/boot/Image "$WORKDIR"/build/EFI/BOOT/BOOTAA64.efi || exit 1
    fi
  fi
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

if [ "$(which cpio)" = "" ]; then
  xfatal "cpio should be available!"
fi

if [ "$(which bc)" = "" ]; then
  xfatal "bc should be available!"
fi

if [ "$(which bison)" = "" ]; then
  xfatal "bison should be available!"
fi

if [ "$(which zip)" = "" ]; then
  xfatal "zip should be available!"
fi

mkdir -p "$SRCDIR"
mkdir -p "$WORKDIR"/build/EFI/BOOT

if $BUILD_INITRD; then
  xecho "Creating x86 initrd_i386.cpio.gz"
  generate_initrd "i386" "$CROSS_COMPILE_X86" || xfatal "Error while generating initrd!"
  xecho "Creating arm initrd_arm.cpio.gz"
  generate_initrd "arm" "$CROSS_COMPILE_ARM" || xfatal "Error while generating initrd!"
  xecho "Done!"
fi

if $BUILD_LINUX; then
  xecho "Building Linux image x86_64"
  build_linux_image "X64" "$CROSS_COMPILE_X86" || xfatal "Error while building 64-bit Linux image!"
  xecho "Building Linux image x86"
  build_linux_image "IA32" "$CROSS_COMPILE_X86" || xfatal "Error while building 32-bit Linux image!"
  xecho "Build Linux image ARM 32-bit"
  build_linux_image "ARM" "$CROSS_COMPILE_ARM" || xfatal "Error while building ARM 32-bit Linux image!"
  xecho "Build Linux image ARM 64-bit"
  build_linux_image "AARCH64" "$CROSS_COMPILE_ARM64" || xfatal "Error while building ARM 64-bit Linux image!"
  # Zipping TestLinux.zip
  pushd "$WORKDIR"/build >/dev/null || exit 1
  rm ../../external/TestLinux.zip
  zip -r ../../external/TestLinux.zip ./EFI
  popd >/dev/null || exit 1
  xecho "Done! Package placed $(pwd)/external/TestLinux.zip"
fi
