#!/usr/bin/env python3

import os
import platform
import shutil
import subprocess
import sys


def abort(message):
    print('ERROR: ' + message + '!')
    sys.exit(1)


# pip install gitpython
try:
    import git
    from git import Repo
except ImportError:
    abort('Failed to import git')

# pip install requests
try:
    import requests
except ImportError:
    abort('Failed to import requests')

# pip install yaml
try:
    import yaml
except ImportError:
    abort('Failed to import yaml')

try:
    os.chdir(os.path.dirname(os.path.realpath(__file__)))
except OSError:
    abort('Failed to switch to current directory')

UNSUPPORTED_DIST = os.getenv('UNSUPPORTED_DIST', default=0)
DIST = platform.uname().system
if UNSUPPORTED_DIST != 1:
    if DIST not in ('Darwin', 'Linux', 'Windows'):
        abort('Unsupported OS distribution ' + DIST)

PROJECT_TYPE = os.getenv('PROJECT_TYPE', default='<empty string>')
if PROJECT_TYPE != 'UEFI':
    abort('Unsupported project type ' + PROJECT_TYPE)

cmake_stat = shutil.which('cmake')
if cmake_stat is None:
    abort('Missing cmake')

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
        try:
            yaml_buffer = yaml.safe_load(buffer)
            try:
                exclude_list = yaml_buffer['exclude_list']
            except KeyError:
                abort('exclude_list is not found in ' + yml_file)
        except yaml.YAMLError:
            abort('Failed to read Uncrustify.yml')

    # Match .c and .h files
    file_list = [os.path.join(path, name) for path, subdirs, files in os.walk(os.getcwd()) for name in files if name.lower().endswith((".c", ".h"))]
    list_txt = open(FILE_LIST, 'w')
    for file in file_list:
        skip = False
        for excl in exclude_list:
            if os.path.normpath(excl) in os.path.normpath(file):
                skip = True

        if skip:
            continue

        try:
            list_txt.write(file + '\n')
        except IOError:
            abort('Failed to dump file list')
    list_txt.close()


"""
shutil.rmtree error handling.

From: https://stackoverflow.com/a/2656405
"""
def onerror(func, path, exc_info):
    """
    Error handler for ``shutil.rmtree``.

    If the error is due to an access error (read only file)
    it attempts to add write permission and then retries.

    If the error is for another reason it re-raises the error.

    Usage : ``shutil.rmtree(path, onerror=onerror)``
    """
    import stat
    # Is the error an access error?
    if not os.access(path, os.W_OK):
        os.chmod(path, stat.S_IWUSR)
        func(path)
    else:
        raise

def build_uncrustify(url):
    if os.path.isdir(UNC_REPO):
        try:
            shutil.rmtree(UNC_REPO, onerror=onerror)
        except OSError:
            abort('Failed to cleanup legacy ' + UNC_REPO)

    proj_root = os.getcwd()

    try:
        Repo.clone_from(url, UNC_REPO)
    except git.exc.GitCommandError:
        abort('Failed to clone ' + UNC_REPO)
    try:
        os.chdir(UNC_REPO)
    except OSError:
        abort('Failed to switch to ' + UNC_REPO)
    try:
        os.mkdir('build')
    except OSError:
        abort('Failed to make temporary build directory')
    try:
        os.chdir('build')
    except OSError:
        abort('Failed to cd to temporary build directory')

    cmake_args = [ 'cmake', '..' ]
    ret = subprocess.check_call(cmake_args)
    if ret != 0:
        abort('Failed to generate makefile with cmake')
    cmake_args = [ 'cmake', '--build', '.', '--config', BUILD_SCHEME ]
    ret = subprocess.check_call(cmake_args)
    if ret != 0:
        abort('Failed to build Uncrustify ' + BUILD_SCHEME)

    global UNC_EXEC
    try:
        exe = next((os.path.abspath(os.path.join(root, name)) for root, dirs, files in os.walk(os.getcwd()) for name in files if name == UNC_EXEC), None)
    except StopIteration:
        abort('Failed to find uncrustify binary')

    try:
        shutil.move(exe, proj_root)
    except FileNotFoundError:
        abort('Failed to locate uncrustify binary')

    # update UNC_EXEC path
    UNC_EXEC = proj_root + '/' + UNC_EXEC

    os.chdir(proj_root)

    try:
        shutil.rmtree(UNC_REPO, onerror=onerror)
    except OSError as exc:
        print(exc)
        abort('Failed to cleanup ' + UNC_REPO)

def download_uncrustify_conf():
    response = requests.get('https://raw.githubusercontent.com/acidanthera/ocbuild/unc-build/uncrustify/configs/' + UNC_CONF)
    with open(UNC_CONF, 'wb') as conf:
        conf.write(response.content)

def run_uncrustify():
    if os.path.isfile(UNC_DIFF):
        try:
            os.remove(UNC_DIFF)
        except OSError:
            abort('Failed to cleanup legacy ' + UNC_DIFF)

    unc_args = [ UNC_EXEC, '-c', UNC_CONF, '-F', FILE_LIST, '--replace', '--no-backup', '--if-changed' ]
    subprocess.check_call(unc_args)

    list_buffer = open(FILE_LIST, 'r')
    lines       = list_buffer.read().splitlines()
    list_buffer.close()
    repo        = Repo(os.getcwd())
    diff_txt    = open(UNC_DIFF, 'w')
    for l in lines:
        diff_output = repo.git.diff(l)
        if diff_output != '':
            print(diff_output + '\n')

            try:
                diff_txt.write(diff_output + '\n')
            except IOError:
                abort('Failed to generate git diff ' + l)
    diff_txt.close()

    file_cleanup = [ FILE_LIST, UNC_EXEC, UNC_CONF ]
    for fc in file_cleanup:
        if os.path.isfile(fc):
            try:
                os.remove(fc)
            except OSError as exc:
                print(exc)
                abort('Failed to cleanup legacy ' + fc)

    if os.stat(UNC_DIFF).st_size != 0:
        abort('Uncrustify detects codestyle problems! Please fix')
    else:
        print('All done! Uncrustify detects no problems!')
        try:
            os.remove(UNC_DIFF)
        except OSError:
            abort('Failed to remove empty ' + UNC_DIFF)

def main():
    dump_file_list(sys.argv[1])
    build_uncrustify(UNC_LINK)
    download_uncrustify_conf()
    run_uncrustify()

if __name__ == '__main__':
    main()
