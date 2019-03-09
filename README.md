ocbuild
=======

*** This is still a work in progress and should NOT be used for the time being! ***

The tool designed to build, package, and manage UEFI UDK packages in [acidanthera](https://github.com/acidanthera).

- Standalone, i.e. building each package requires bootstrapping ocbuild if it was not installed previously.
- Controllable through environment variables (specifying paths and policy overrides).
- Supports flexible command set for performing actions on Linux and Darwin.

#### Configuration

Tool configuration is read from `ocbuild.config` file in the root of each package, which is
essentially a shell script compatible with bash 3.2 (bundled with macOS), responsible for
defining a set of variables later used for package compilation.

* `oc_project_name` - project name used in release archives.
* `oc_package_name` - package name used in directory name.
* `oc_version_header_file` - relative path to local C header file containing version number. Optional.

    Version format is unspecified, but should be defined as follows:
    ```C
    #define ${oc_version_macro_name} L"${VERSION_DATA}"
    ```

* `oc_version_macro_name` - define name containing string literal version in
    `oc_version_header_file`. Optional.
* `oc_dependency_repos` - an array of git repositories for dependencies.
* `oc_dependency_names` - an array of dependency names, used for directories.
* `oc_dependency_branches` - an array of dependency branches used for cloning.
* `oc_build_targets` - an array of build targets (like `NOOPT` or `RELEASE`).
* `oc_release_support` - boolean to enable/disable release packaging. It is required to provide
    `oc_release_targets`, `oc_release_files`, `oc_release_dirs`, `oc_version_header_file`,
    `oc_version_macro_name` values when this is set to `true`. Otherwise these values are ignored.
    Optional and false by default.
* `oc_release_targets` - an array of release targets (like `NOOPT` or `RELEASE`). Optional.
* `oc_release_files` - an array of release files. Optional.
* `oc_release_dirs` - an array of release file directories (use "" for root). Optional.

Regardless of whether dependencies have or do not have `ocbuild.config` files, they are not
processed for security reasons. File paths are supposed to be sanitised for being placed within
the current directory, yet it is user's concern not to run untrusted configuration.

Example:

```bash
oc_project_name='AppleSupport'
oc_package_name='AppleSupportPkg'
oc_release_support=true
oc_version_header_file='Include/AppleSupportPkgVersion.h'
oc_version_macro_name='APPLE_SUPPORT_VERSION'
oc_dependency_repos=(
  'https://github.com/acidanthera/EfiPkg'
  'https://github.com/acidanthera/OcSupportPkg'
  )
oc_dependency_names=(
  'EfiPkg'
  'OcSupportPkg'
  )
oc_dependency_branches=(
  'master'
  'master'
  )
oc_build_targets=(
  'NOOPT'
  'DEBUG'
  'RELEASE'
  )
oc_release_targets=(
  'NOOPT'
  'DEBUG'
  'RELEASE'
  )
oc_release_files=(
  'Driver.efi'
  'Something.efi'
  'MyApp.efi'
  )
oc_release_dirs=(
  'Drivers'
  '' # root directory
  'Applications'
  )
```

#### Bootstrapping

From buildserver standpoint (CI) using ocbuild should look as follows in the simplest case:
```
src=$(/usr/bin/curl -Lfs https://raw.githubusercontent.com/acidanthera/ocbuild/master/Scripts/bootstrap.sh) && eval "$src" && ocbuild || exit 1
```

Bootstrapping algorithm is implemented as follows:
1. Check if the system is one of the supported (via uname, we support Darwin and Linux)
2. Check if ocbuild directory exists in the current directory, if it does, then abort
3. Perform git clone of https://github.com/acidanthera/ocbuild into the current directory
4. Add path to ocbuild utility to PATH

#### Environment variables

* `OC_UDK_PATH` - UDK path used for downloading and locating UDK installation.

      - When this variable is set, UDK is downloaded to this directory (`${OC_UDK_PATH}/MdePkg`). 
      - When this variable is not set, UDK is downloaded to current directory
        (`${oc_package_name}/UDK`).

* `OC_PACKAGES_PATH` - package paths used for downloading and locating dependencies. Similarly to UDK
    [`PACKAGES_PATH`](https://github.com/tianocore/tianocore.github.io/wiki/Multiple_Workspace) has
    semicolon separated format.

      - When this variable is set, all the dependencies are downloaded to the first provided path, unless
        they are found in other paths. Current directory is supposed to be present in `OC_PACKAGES_PATH`
        as well. If it is not, a symlink is created.
      - When this variable is not set, all the dependencies are downloaded to UDK copy. Current
        directory is also symlinked into the UDK copy (`${OC_UDK_PATH}/UDK/${oc_package_name}`).

* `OC_WORKSPACE` - UDK build directory. Reexported as [`WORKSPACE`](https://github.com/tianocore/tianocore.github.io/wiki/Multiple_Workspace)
    and guaranteed to be created if missing.

#### Commands

Commands are passed as a first argument to the tool and may then be followed by options:

```
ocbuild register --path /opt/local/bin
```

* `register` - add symlink to ocbuild to system directory.
    `--path arg` - system directory path (default: `/usr/local/bin`)

* `upgrade` - upgrade to the latest version of ocbuild. Equivalent to bootstrapping the new
    version in the current installation directory.

* `prepare` - prepare system for building packages by checking compiler availability,
    and potentially installing necessary utilities like mtoc and nasm.
    - `--no-install` - do not attempt to install utilities and abort on error.
    - `--path arg` - installation directory path (default: `/usr/local/bin`).

* `configure` - configure UDK installation.
    - `--skip-download` - skip downloading or upgrade checking and work locally.

    The procedure involves the following actions:

    - downloading/upgrading UDK and applying patches (if any).
    - downloading/upgrading all the dependencies (if any).
    - building UDK BaseTools for compilation.
    - preparing Binaries symlinks.

* `build` - compile current package.
    - `--target arg` - build for selected target (e.g. `RELEASE`)

* `package` - create release package. BUILD.nfo file is always put to package root.
    - `--target arg` - create package for selected target (e.g. `RELEASE`)

* By default an equivalent of sequential calls to `configure`, `build`, `package` is assumed.

#### BUILD.nfo

When packaging a BULD.nfo file is created to reflect the version information. This file is also
bash conformant and includes the following information:

- `PACKAGE` - `${oc_package_name}` contents.
- `PACKAGE_URL` - repository URL.
- `TARGET` - build target (e.g. RELEASE).
- `TOOLCHAIN` - build toolchain (e.g. XCODE5).
- `OCBUILD_REV` - ocbuild git branch and commit hash, with `/dirty` suffix if modified.
- `UDK_REV` - UDK git branch and commit hash prior to patching, with `/dirty` suffix if modified.
- `UDK_URL` - UDK repository URL.
- `UDK_PATCHES` - an array of names and SHA-1 hashes of applied patches on UDK.
- `DEPENDENCIES` - an array of dependency names, git branches, and git commit hashes, with `/dirty`
    suffix if modified.
- `DEPENDENCIES_URL` - an array of dependency URLs.

Example:

```bash
PACKAGE='AppleSupportPkg'
PACKAGE_URL='https://github.com/acidanthera/AppleSupportPkg'
TARGET='RELEASE'
TOOLCHAIN='XCODE5'
OCBUILD_REV='master/24f2f6e826de46f40bd1612f92e0b28fb0c4faf9/dirty'
UDK_REV='UDK2018/a83f2a7c19c874b44b8e468dd4573a9887eb75f1'
UDK_URL='https://github.com/tianocore/edk2'
UDK_PATCHES=(
  'my-patch.diff/01026c2d93003ccb2e737e651efc99af1feb35e6'
  'my-patch2.diff/f55c86648d5617ead3a2be11acb2d9b88d6e50b5'
  )
DEPENDENCIES=(
  'EfiPkg/master/7c2efd8681a43f08ae2769c0215a383f168c9e70/dirty'
  'OcSupportPkg/master/a59023b87da1b33835f3aa46bc5e99b9b58c5690'
  )
DEPENDENCIES_URL=(
  'https://github.com/tianocore/EfiPkg'
  'https://github.com/tianocore/OcSupportPkg'
  )
```

