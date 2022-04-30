#!/usr/bin/env python3

from glob import glob
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
# FIXME: Drop this print
print('Current dist: ' + DIST)
if UNSUPPORTED_DIST != 1:
  if DIST != 'Darwin' and DIST != 'Linux' and DIST != 'Windows':
    abort('Unsupported OS distribution ' + DIST)

PROJECT_TYPE = os.getenv('PROJECT_TYPE', default='<empty string>')
if PROJECT_TYPE != 'UEFI':
  abort('Unsupported project type ' + PROJECT_TYPE)

cmake_stat = shutil.which('cmake')
if cmake_stat is None:
  abort('Missing cmake')

UNC_REPO='Uncrustify-repo'
UNC_LINK='https://projectmu@dev.azure.com/projectmu/Uncrustify/_git/Uncrustify'
UNC_CONF='unc-' + PROJECT_TYPE + '.cfg'
FILE_LIST='filelist.txt'
UNC_DIFF='uncrustify.diff'
BUILD_SCHEME='Release'

UNC_EXEC='./uncrustify'
# FIXME: Check Windows
if DIST == 'Windows':
  UNC_EXEC='./uncrustify.exe'

def dump_file_list(yml_file):
  with open(yml_file, 'r') as buffer:
    try:
      yaml_buffer = yaml.safe_load(buffer)
      try:
        exclude_list = yaml_buffer['exclude_list']
      except KeyError:
        abort('exclude_list is not found in ' + yml_file)
    except yaml.YAMLError:
      abort('Failed to read Uncrustify.yml')

  # Match .c and .h files
  file_list = [y for x in os.walk(os.getcwd()) for y in glob(os.path.join(x[0], '*.[c|h]'))]
  list_txt  = open(FILE_LIST, 'w')
  for f in file_list:
    skip = False
    for e in exclude_list:
      if e in f:
        skip = True

    if skip:
      continue

    try:
      list_txt.write(f + '\n')
    except IOError:
      abort('Failed to dump file list')

def build_uncrustify(url):
  if os.path.isdir(UNC_REPO):
    try:
      shutil.rmtree(UNC_REPO)
    except OSError:
      abort('Failed to cleanup legacy ' + UNC_REPO)

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

  cmake_args = 'cmake ' + '..'
  ret = subprocess.check_call(cmake_args, shell=True)
  if ret != 0:
    abort('Failed to generate makefile with cmake')
  cmake_args = 'cmake --build . --config ' + BUILD_SCHEME
  ret = subprocess.check_call(cmake_args, shell=True)
  if ret != 0:
    abort('Failed to build Uncrustify ' + BUILD_SCHEME)

  # FIXME: Check Windows
  prefix = './'
  if DIST == 'Windows':
    prefix = './' + BUILD_SCHEME + '/'
  try:
    shutil.move(prefix + UNC_EXEC, '../..')
  except OSError:
    abort('Failed to move ' + UNC_EXEC + ' to parent directory')

  os.chdir('../..')
  try:
    shutil.rmtree(UNC_REPO)
  except OSError:
    abort('Failed to cleanup ' + UNC_REPO)

def download_uncrustify_conf():
  response = requests.get('https://raw.githubusercontent.com/acidanthera/ocbuild/unc-build/uncrustify/configs/' + UNC_CONF)
  with open(UNC_CONF, 'wb') as f:
    f.write(response.content)

def run_uncrustify():
  if os.path.isfile(UNC_DIFF):
    try:
      os.remove(UNC_DIFF)
    except OSError:
      abort('Failed to cleanup legacy' + UNC_DIFF)

  unc_args = UNC_EXEC + ' -c ' + UNC_CONF + ' -F ' + FILE_LIST + ' --replace --no-backup --if-changed'
  ret = subprocess.check_call(unc_args, shell=True)
  if ret != 0:
    abort('Failed to run Uncrustify')

  list_buffer = open(FILE_LIST, 'r')
  lines       = list_buffer.read().splitlines()
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

  file_cleanup = [ FILE_LIST, UNC_EXEC, UNC_CONF ]
  for fc in file_cleanup:
    if os.path.isfile(fc):
      try:
        os.remove(fc)
      except OSError:
        abort('Failed to cleanup legacy' + fc)

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
