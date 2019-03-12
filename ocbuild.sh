#!/bin/bash

# set -x

#
# Script version.
#
gScriptVersion='1.0'

#
# Current directory (where this script lives in)
# If ${0} is a symlink, gThisDir will be set to its origin.
#
isLink="$(readlink ${0})"
if [[ ! -z "${isLink}" ]]; then
  gThisDir="$(echo "${isLink}" | sed -e "s/\/$(basename "${isLink}")//")"
else
  gThisDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
fi

#
# UDK directory where UDK lives or will be downloaded if missing.
#
gUDKDir=""


function importConfig() {
  local ocConf="${1}"

  if [[ ! -f "${ocConf}" ]]; then
    echo "${ocConf} is missing!"
    exit 1
  fi

  source "${ocConf}"
  if [[ $? -ne 0 ]]; then
    echo "Error importing ${ocConf}!"
    exit 1
  fi
}

function parseConfig() {
  echo TODO
}

function parseEnvVar() {
  local var="${1}"

  case "${var}" in
    'OC_UDK_PATH' )
      if [[ ! -z "${OC_UDK_PATH}" ]]; then
        gUDKDir="${OC_UDK_PATH}"
        echo "Environment variable OC_UDK_PATH is set, UDK will be downloaded to ${gUDKDir}"
      else
        if [[ ! -z "${oc_package_name}" ]]; then
          gUDKDir="${oc_package_name}/UDK"
          echo "Environment variable OC_UDK_PATH is NOT set, UDK will be downloaded to ${gUDKDir}"
        else
          echo "ERROR: variable oc_package_name is null!"
          exit 1
        fi
      fi

      wrapCheckDirectoryWritability "${gUDKDir}"
    ;;

    'OC_PACKAGES_PATH' )
      echo OC_PACKAGES_PATH passed here
    ;;

    'OC_WORKSPACE' )
      echo OC_WORKSPACE passed here
    ;;
  esac
}

function parseOcEnvVars() {
  local envVars=('OC_UDK_PATH' 'OC_PACKAGES_PATH' 'OC_WORKSPACE')
  for i in "${envVars[@]}"; do
    parseEnvVar "${i}"
  done
}

function checkDirectoryWritability() {
  local dir="${1}"

  if [[ ! -d "${dir}" ]]; then
    # code 1: no such directory
    echo "WARNING: Directory ${dir} does not exist!"
    return 1
  fi

  # create a test file and see if it fails
  # TODO: uuid generation support under Linux
  local testFile="${dir}/$(uuidgen)"
  echo > "${testFile}"
  if [[ $? -ne 0 ]]; then
    # code 2: write failure
    echo "WARNING: Failed to write to ${dir}"
    return 2
  fi

  # remove it and it turns to be success (code 0)
  [[ -e "${testFile}" ]] && rm "${testFile}"
  return 0
}

function wrapCheckDirectoryWritability() {
  local dir="${1}"

  checkDirectoryWritability "${dir}"
  if [[ $? -ne 0 ]]; then
    echo "${dir} is not writable!"
    exit 1
  fi
}

function checkCompiler() {
  # FIXME: for now the code is copied from
  # https://github.com/acidanthera/AppleSupportPkg/blob/8b21123310fcc8f37f24de5a30c20815875cac4e/macbuild.tool#L63
  # might we need more checks?

  if [ "$(which clang)" = "" ] || [ "$(which git)" = "" ] || [ "$(clang -v 2>&1 | grep "no developer")" != "" ] || [ "$(git -v 2>&1 | grep "no developer")" != "" ]; then
    echo 'Missing Xcode tools, please install them!'
    # code 1: missing Xcode tools
    # solution: no cure, just ask users to install Xcode manually
    return 1
  fi

  if [ "$(nasm -v)" = "" ] || [ "$(nasm -v | grep Apple)" != "" ]; then
    echo 'Missing or incompatible nasm!'
    # code 2: wrong nasm
    # solution: download compatible nasm and install it (only when --no-install passed)
    return 2
  fi

  if [ "$(which mtoc.NEW)" == "" ] || [ "$(which mtoc)" == "" ]; then
    echo 'Missing mtoc or mtoc.NEW!'
    # code 3: missing mtoc or mtoc.NEW
    # solution: download mtoc and install it (only when --no-install passed)
    return 3
  fi
}

function registerScript() {
  local pathArg="${1}"
  local sysDirPath="${2}"

  # parse --path now
  flag="$(echo "${pathArg}" | tr '[:upper:]' '[:lower:]')"
  if [[ "${flag}" == '--path' ]]; then
    # given --path
    shift
    sysDirPath="${1}"
    if [[ -z "${sysDirPath}" ]]; then
      echo 'System directory path should not be null!'
      exit 1
    elif [[ ! -d "${sysDirPath}" ]]; then
      echo "${sysDirPath} does NOT exist!"
      exit 1
    fi
  elif [[ -z "${flag}" ]]; then
    # no --path
    sysDirPath="/usr/local/bin"
    echo "No system directory given, using ${sysDirPath}"
    if [[ ! -d "${sysDirPath}" ]]; then
      mkdir -p "${sysDirPath}"
      if [[ $? -ne 0 ]]; then
        echo "Failed to create ${sysDirPath} with the current permission!"
        exit 1
      fi
    fi
  else
    # unknown, abort
    echo "Unknown argument (${1}) for registration!"
    exit 1
  fi

  # check writability
  wrapCheckDirectoryWritability "${sysDirPath}"

  # finally, add symlink to sysDirPath
  ln -sf "${0}" "${sysDirPath}"
  if [[ $? -ne 0 ]]; then
    echo "Failed to create symlink of ${0} inside ${sysDirPath}!"
    exit 1
  fi
}

function buildPackage() {
  echo TODO
}

function showHelp() {
  echo TODO

  exit 0
}

function showScriptVersion() {
  echo -e "\nVersion ${gScriptVersion}\n"

  exit 0
}

function parseOcBuildArgs() {
  local argument="$(echo "${1}" | tr '[:upper:]' '[:lower:]')"
  if [[ $# -eq 1 && "${argument}" == "-h" || "${argument}" == "--help"  ]]; then
    showHelp
  elif [[ $# -eq 1 && "${argument}" == "-v" || "${argument}" == "--version" ]]; then
    showScriptVersion
  fi

  while [[ "${1}" ]]; do
    local flag="$(echo "${1}" | tr '[:upper:]' '[:lower:]')"

    case "${flag}" in
      'register' )
        shift
        # now "${1}" is --path
        local pathArg="${1}"

        shift 
        # now "${1}" is the exact path
        local sysDirPath="${1}"

        registerScript "${pathArg}" "${sysDirPath}"
      ;;

      'upgrade' )
        # TODO
      ;;

      'prepare' )
        shift
        # now "${1}" is the args to be parsed (--no-install, path)
        while [[ "${1}" ]]; do
          flag="$(echo "${1}" | tr '[:upper:]' '[:lower:]')"

          case "${flag}" in
            --no-install )
              local noPrepareInstall=1
            ;;

            --path )
              # --path should not be used with --no-install simultaneously
              if [[ "${noPrepareInstall}" -eq 1 ]]; then
                echo '--path should not be used with --no-install simultaneously!'
                exit 1
              fi

              shift
              # now "${1}" is the exact path
              # TODO: install nasm/mtoc
            ;;
          esac

          # shift left after each time one arg gets parsed
          shift
        done
      ;;

      'configure' )
        # TODO
      ;;

      'build' )
        local target

        # TODO: parse this from ocbuild.config
        shift
        flag="$(echo "${1}" | tr '[:upper:]' '[:lower:]')"
        # parse --target now
        if [[ "${flag}" == '--target' ]]; then
          # given --target
          shift
          target="${1}"
          if [[ -z "${target}" ]]; then
            echo 'Build target should not be null!'
            exit 1
          else
            case "${target}" in
              'NOOPT' | 'DEBUG' | 'RELEASE' ) ;;

              * )
                echo "Unknown target (${target})!"
                exit 1
              ;;
            esac
          fi
        elif [[ -z "${flag}" ]]; then
          target='RELEASE'
          echo "No target passed, using ${target}"
        else
          echo "Unknown argument (${1}) for building!"
          exit 1
        fi

        source "${gUDKDir}/edksetup.sh" || exit 1
        # TODO: dsc
        build -a X64 -b "${target}" -t XCODE5 -p "${dsc}" || exit 1
      ;;

      'package' )
        # TODO
      ;;

      * )
        echo "Unknown arg (${1}), aborting"
        exit 1
      ;;
    esac

    # shift left after each time one arg gets parsed
    shift
  done

}

function main() {
  # parse environment variables
  parseOcEnvVars

  parseOcBuildArgs "${@}"
}

main "${@}"