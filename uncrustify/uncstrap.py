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
    os.chdir(os.path.dirname(os.path.realpath(__file__)))
except OSError as ex:
    print(ex)
    abort('Failed to switch to current directory')

UNC_REPO = 'Uncrustify-repo'
UNC_LINK = 'https://projectmu@dev.azure.com/projectmu/Uncrustify/_git/Uncrustify'
UNC_CONF = 'unc-' + PROJECT_TYPE + '.cfg'
FILE_LIST = 'filelist.txt'
UNC_DIFF = 'uncrustify.diff'
BUILD_SCHEME = 'Release'

UNC_EXEC = 'uncrustify'
if DIST == 'Windows':
    UNC_EXEC += '.exe'


def dump_file_list(yml_file):
    with open(yml_file, mode='r', encoding='UTF-8') as buffer:
        yaml_buffer = yaml.safe_load(buffer)
        exclude_list = yaml_buffer['exclude_list']

        buffer.close()

    # Match .c and .h files
    file_list = [os.path.join(path, name) for path, subdirs, files in os.walk(os.getcwd()) for name in files if name.lower().endswith((".c", ".h"))]
    with open(FILE_LIST, 'w', encoding='UTF-8') as list_txt:
        for file in file_list:
            skip = False
            for excl in exclude_list:
                if os.path.normpath(excl) in os.path.normpath(file):
                    skip = True

            if skip:
                continue

            list_txt.write(file + '\n')

        list_txt.close()


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
        shutil.rmtree(UNC_REPO, onerror=onerror)

    proj_root = os.getcwd()

    Repo.clone_from(url, UNC_REPO)
    os.chdir(UNC_REPO)
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

    global UNC_EXEC
    exe = next((os.path.abspath(os.path.join(root, name)) for root, dirs, files in os.walk(os.getcwd()) for name in files if name == UNC_EXEC), None)

    shutil.move(exe, proj_root)

    # update UNC_EXEC path
    UNC_EXEC = proj_root + '/' + UNC_EXEC

    os.chdir(proj_root)

    shutil.rmtree(UNC_REPO, onerror=onerror)


def download_uncrustify_conf():
    response = requests.get('https://raw.githubusercontent.com/acidanthera/ocbuild/unc-build/uncrustify/configs/' + UNC_CONF)
    with open(UNC_CONF, 'wb') as conf:
        conf.write(response.content)


def run_uncrustify():
    if os.path.isfile(UNC_DIFF):
        os.remove(UNC_DIFF)

    unc_args = [UNC_EXEC, '-c', UNC_CONF, '-F', FILE_LIST, '--replace', '--no-backup', '--if-changed']
    subprocess.check_call(unc_args)

    with open(FILE_LIST, 'r', encoding='UTF-8') as list_buffer:
        lines = list_buffer.read().splitlines()
        list_buffer.close()

    repo = Repo(os.getcwd())
    with open(UNC_DIFF, 'w', encoding='UTF-8') as diff_txt:
        for line in lines:
            diff_output = repo.git.diff(line)
            if diff_output != '':
                print(diff_output + '\n')
                diff_txt.write(diff_output + '\n')

        diff_txt.close()

    file_cleanup = [FILE_LIST, UNC_EXEC, UNC_CONF]
    for file in file_cleanup:
        if os.path.isfile(file):
            os.remove(file)

    if os.stat(UNC_DIFF).st_size != 0:
        abort('Uncrustify detects codestyle problems! Please fix')
    else:
        print('All done! Uncrustify detects no problems!')
        os.remove(UNC_DIFF)


def main():
    dump_file_list(sys.argv[1])
    build_uncrustify(UNC_LINK)
    download_uncrustify_conf()
    run_uncrustify()


if __name__ == '__main__':
    try:
        main()
    except Exception as ex:
        print(f"Bailed beacuse: {ex}")
        sys.exit(1)
