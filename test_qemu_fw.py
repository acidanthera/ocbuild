#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import os
import re
import sys
import zipfile
import logging

import pexpect

TEST_LINUX_PATH = "./TestLinux"
TEST_WINPE_PATH = "./winpe.iso"
TESTCONSOLE_PATH = "./TestConsole"


def get_qemu_version() -> tuple:
    """
    Get QEMU version in system

    :return version tuple (major, minor, patch):
    """
    version = None
    p = pexpect.spawn('qemu-system-x86_64 -version')
    p.expect(pexpect.EOF)
    output = p.before.decode('utf-8')
    version_pattern = re.compile("(\\d+\\.)(\\d+\\.)(\\*|\\d+)")
    collection = version_pattern.findall(output)
    if collection:
        version = tuple(int(el.strip('.')) for el in collection[0])

    return version


def test_firmware(fw_path: str, boot_drive_path: str, expected_string: str, timeout: int, rdrand: bool, fw_arch: str) -> bool:
    """
    Run QEMU and check whether firmware can start given image

    :param fw_path: The path points to the firmware to run (OVMF)
    :param boot_drive_path: The path points to ESP or raw image to boot from
    :param expected_string: The expected string we wait for during image run
    :param timeout: Timeout for image run
    :param rdrand: Run with rdrand support or not
    :return the boolean result:
    """
    result = False
    qemu_version = get_qemu_version()
    if qemu_version is None:
        logging.error("Can't retrieve QEMU version!")
        return False

    qemu_x86_runner = f"qemu-system-x86_64 {'-enable-kvm ' if qemu_version < (6, 2, 0) else ''}"
    qemu_arm_runner = 'qemu-system-arm '
    qemu_arm64_runner = 'qemu-system-aarch64 '
    machine_string_x86 = f" -cpu Penryn{',+rdrand' if rdrand else ''} -smp 2 -machine q35 -m 2048 "
    machine_string_arm = ' -cpu cortex-a15 -smp 2 -machine virt,highmem=off ' \
                         ' -accel tcg,tb-size=1024 -m 2048 '
    machine_string_arm64 = ' -cpu cortex-a53 -smp 2 -machine virt,virtualization=on ' \
                           '-accel tcg,tb-size=1024 -m 2048 '
    if fw_arch == "x86":
        p = pexpect.spawn(qemu_x86_runner + machine_string_x86 +
                          '-bios ' + fw_path + ' -display none -serial stdio '
                          + boot_drive_path)
    elif fw_arch == "arm":
        p = pexpect.spawn(qemu_arm_runner + machine_string_arm +
                          '-bios ' + fw_path + ' -display none -serial stdio '
                          + boot_drive_path)
    elif fw_arch == "arm64":
        p = pexpect.spawn(qemu_arm64_runner + machine_string_arm64 +
                          '-bios ' + fw_path + ' -display none -serial stdio '
                          + boot_drive_path)
    else:
        logging.error("Unsupported arch specified!")
        return False

    p.timeout = timeout
    res = p.expect([expected_string, pexpect.TIMEOUT])
    if res == 0:
        print("OK")
        result = True
    else:
        logging.error("Timeout! Something went wrong, check log below")
        try:
            error_log = p.before.decode()
        except UnicodeDecodeError:
            error_log = p.before
        logging.error("Process output before timeout:\n %s", error_log)
    return result


def prepare_test_console(esp_path: str) -> bool:
    """
    Prepares ESP folder with TestConsole application

    :param esp_path: The path points to ESP folder
    :return the boolean result:
    """
    if not os.path.exists(esp_path):
        # Unpack TestConsole
        print("Preparing ESP with TestConsole")
        try:
            with zipfile.ZipFile('./external/TestConsole.zip', 'r') as zip_ref:
                zip_ref.extractall(esp_path)
        except Exception as e:
            logging.error("%s", e)
            return False
    return True


def prepare_test_linux_image(esp_path: str) -> bool:
    """
    Prepares ESP folder with tiny linux kernel with efistub and W^X patches
    It prints Hello World and gives simple shell /bin/sh

    :param esp_path: The path points to ESP folder
    :return the boolean result:
    """
    if not os.path.exists(esp_path):
        # Unpack TestLinux
        print("Preparing ESP with TestLinux")
        try:
            with zipfile.ZipFile('./external/TestLinux.zip', 'r') as zip_ref:
                zip_ref.extractall(esp_path)
        except Exception as e:
            logging.error("%s", e)
            return False
    return True


def parse_fw_arch(fw_arch: str) -> str:
    if fw_arch in ['i386', 'x86', 'IA32', 'X64', 'x64', 'x86_64', 'X86']:
        return 'x86'
    if fw_arch in ['arm', 'arm32', 'aarch32', 'AARCH32', 'ARM']:
        return 'arm'
    if fw_arch in ['AARCH64', 'aarch64', 'arm64', 'ARM64', 'AA64', 'aa64']:
        return 'arm64'
    return "Unknown"


def main():
    """ The QEMU-based firmware checker """
    parser = argparse.ArgumentParser(description='Run QEMU and determine whether firmware can start bootloader.')
    parser.add_argument('fw_path', type=str, help='Path to firmware.')
    parser.add_argument('--no-rdrand', dest='rdrand', action='store_false')
    parser.add_argument('--test-console-path', dest='user_testconsole_path', action='store')
    parser.add_argument('--test-linux-path', dest='user_testlinux_path', action='store')
    parser.add_argument('--test-linux', dest='test_linux', action='store_true')
    parser.add_argument('--test-winpe-path', dest='user_testwinpe_path', action='store')
    parser.add_argument('--test-winpe', dest='test_winpe', action='store_true')
    parser.add_argument('--fw-arch', dest='fw_arch', action='store')
    parser.set_defaults(rdrand=True)
    parser.set_defaults(test_linux=False)
    parser.set_defaults(fw_arch="x86")
    pexpect_timeout = 30  # default 30
    testconsole_path = TESTCONSOLE_PATH
    testlinux_path = TEST_LINUX_PATH
    testwinpe_path = TEST_WINPE_PATH

    args = parser.parse_args()
    logging.basicConfig(
        format="%(asctime)-15s [%(levelname)s] %(funcName)s: %(message)s",
        level=logging.INFO)

    fw_arch = parse_fw_arch(args.fw_arch)

    if not args.test_linux and args.user_testlinux_path:
        parser.error("--test-linux-path requires --test-linux")

    if args.user_testlinux_path is not None:
        testlinux_path = args.user_testlinux_path
    elif args.user_testconsole_path is not None:
        testconsole_path = args.user_testconsole_path
    elif args.user_testwinpe_path is not None:
        testwinpe_path = args.user_testwinpe_path

    if args.test_linux:
        if not prepare_test_linux_image(testlinux_path):
            sys.exit(1)
        boot_drive = '-hda fat:rw:' + testlinux_path
        expected_string = 'Hello World!'
        pexpect_timeout = 120
    elif args.test_winpe:
        boot_drive = '-cdrom ' + testwinpe_path
        expected_string = 'EVENT: The CMD command is now available'
        pexpect_timeout = 120
    else:
        if not prepare_test_console(testconsole_path):
            sys.exit(1)
        boot_drive = '-hda fat:rw:' + testconsole_path
        expected_string = 'GPT entry is not accessible'
    print("Testing ...")
    if test_firmware(args.fw_path, boot_drive, expected_string, pexpect_timeout, args.rdrand, fw_arch):
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()
