#!/usr/bin/env python3

import os
import platform
import shutil
import stat
import subprocess
import sys

# pip install requests
import requests

# pip install pyyaml
import yaml

# pip install gitpython
from git import Repo


def abort(message):
    print('ERROR: ' + message + '!')
    sys.exit(1)


UNSUPPORTED_DIST = os.getenv('UNSUPPORTED_DIST', '0')
DIST = platform.uname().system
if UNSUPPORTED_DIST != 1:
    if DIST not in ('Darwin', 'Linux', 'Windows'):
        abort('Unsupported OS distribution ' + DIST)

PROJECT_TYPE = os.getenv('PROJECT_TYPE', '')
if PROJECT_TYPE != 'UEFI':
    abort('Unsupported project type ' + PROJECT_TYPE)

cmake_stat = shutil.which('cmake')
if cmake_stat is None:
    abort('Missing cmake')

try:
    os.chdir(os.getcwd())
except OSError as ex:
    print(ex)
    abort('Failed to switch to current directory')

UNC_REPO = 'Uncrustify-repo'
UNC_LINK = 'https://projectmu@dev.azure.com/projectmu/Uncrustify/_git/Uncrustify'
UNC_CONF = 'unc-' + PROJECT_TYPE + '.cfg'
SRC_LIST = 'unc-srclist.txt'
UNC_DIFF = 'uncrustify.diff'
BUILD_SCHEME = 'Release'


def dump_file_list(yml_file):
    with open(yml_file, mode='r', encoding='UTF-8') as buffer:
        yaml_buffer = yaml.safe_load(buffer)
        exclude_list = yaml_buffer['exclude_list']

    # Match .c and .h files
    file_list = [os.path.join(path, name) for path, subdirs, files in os.walk(os.getcwd()) for name in files if name.lower().endswith((".c", ".h"))]
    with open(SRC_LIST, 'w', encoding='UTF-8') as list_txt:
        for file in file_list:
            skip = False
            for excl in exclude_list:
                if os.path.normpath(excl) in os.path.normpath(file):
                    skip = True

            if skip:
                continue

            list_txt.write(file + '\n')


#
# shutil.rmtree error handling.
# From: https://stackoverflow.com/a/2656405
#
def onerror(func, path, *_):
    """
    Error handler for ``shutil.rmtree``.

    If the error is due to an access error (read only file)
    it attempts to add write permission and then retries.

    If the error is for another reason it re-raises the error.

    Usage : ``shutil.rmtree(path, onerror=onerror)``
    """
    # Is the error an access error?
    if not os.access(path, os.W_OK):
        os.chmod(path, stat.S_IWUSR)
        func(path)


def build_uncrustify(url):
    if os.path.isdir(UNC_REPO):
        shutil.rmtree(UNC_REPO, onexc=onerror)

    proj_root = os.getcwd()

    repo = Repo.clone_from(url, UNC_REPO)
    os.chdir(UNC_REPO)
    sha = repo.head.object.hexsha

    # write sha to a file, so that actions/upload-artifact has access to it
    sha_txt = 'unc-sha.txt'
    with open(sha_txt, 'w', encoding='UTF-8') as unc_sha:
        unc_sha.write(sha)
    shutil.move(sha_txt, proj_root)

    os.mkdir('build')
    os.chdir('build')
    cmake_args = ['cmake', '..']
    ret = subprocess.check_call(cmake_args)
    if ret != 0:
        abort('Failed to generate makefile with cmake')
    cmake_args = ['cmake', '--build', '.', '--config', BUILD_SCHEME]
    ret = subprocess.check_call(cmake_args)
    if ret != 0:
        abort('Failed to build Uncrustify ' + BUILD_SCHEME)

    exe = next((os.path.abspath(os.path.join(root, name)) for root, dirs, files in os.walk(os.getcwd()) for name in files if name in ('uncrustify', 'uncrustify.exe')), None)
    if exe is None:
        raise ValueError('Uncrustify binary is not found!')
    shutil.move(exe, proj_root)

    os.chdir(proj_root)


def download_uncrustify_conf():
    response = requests.get('https://raw.githubusercontent.com/acidanthera/ocbuild/master/uncstrap/configs/' + UNC_CONF, timeout=5)
    with open(UNC_CONF, 'wb') as conf:
        conf.write(response.content)


def download_uncrustify_bin():
    zip_name = 'Uncrustify-' + DIST + '.zip'
    if os.path.isfile(zip_name):
        os.remove(zip_name)

    response = requests.get('https://raw.githubusercontent.com/acidanthera/ocbuild/master/external/' + zip_name, timeout=5)
    real_filename = response.text

    response = requests.get('https://raw.githubusercontent.com/acidanthera/ocbuild/master/external/' + real_filename, timeout=5)
    with open(zip_name, 'wb') as archive:
        archive.write(response.content)

    unzip_args = ['unzip', '-qu', zip_name]
    ret = subprocess.check_call(unzip_args)
    if ret != 0:
        abort('Failed to unzip ' + zip_name)
    os.remove(zip_name)

    exe = next((os.path.abspath(os.path.join(root, name)) for root, dirs, files in os.walk(os.getcwd()) for name in files if name in ('uncrustify', 'uncrustify.exe')), None)
    if exe is None:
        raise ValueError('Uncrustify binary is not found!')

    exe_stat = os.stat(exe)
    os.chmod(exe, exe_stat.st_mode | stat.S_IEXEC)

    return exe


def run_uncrustify(unc_exec):
    if os.path.isfile(UNC_DIFF):
        os.remove(UNC_DIFF)

    unc_args = [unc_exec, '-c', UNC_CONF, '-F', SRC_LIST, '--replace', '--no-backup', '--if-changed']
    subprocess.check_call(unc_args)

    with open(SRC_LIST, 'r', encoding='UTF-8') as list_buffer:
        lines = list_buffer.read().splitlines()

    repo = Repo(os.getcwd())
    with open(UNC_DIFF, 'w', encoding='UTF-8') as diff_txt:
        for line in lines:
            diff_output = repo.git.diff(line)
            if diff_output != '':
                print(diff_output + '\n')
                diff_txt.write(diff_output + '\n')

    file_cleanup = [SRC_LIST, unc_exec, UNC_CONF]
    for file in file_cleanup:
        if os.path.isfile(file):
            os.remove(file)

    if os.stat(UNC_DIFF).st_size != 0:
        abort('Uncrustify detects codestyle problems! Please fix')

    print('All done! Uncrustify detects no problems!')
    os.remove(UNC_DIFF)


def main():
    if sys.argv[1] in ('-b', '--build'):
        build_uncrustify(UNC_LINK)
        sys.exit(0)

    dump_file_list(sys.argv[1])
    download_uncrustify_conf()
    unc_exec = download_uncrustify_bin()
    run_uncrustify(unc_exec)


if __name__ == '__main__':
    try:
        main()
    except Exception as ex:
        print(f"Bailed beacuse: {ex}")
        sys.exit(1)
