# Darling on KwickOS (`kwick-darling`)

[Darling](https://github.com/darlinghq/darling) runs macOS command-line programs on Linux. It is a userspace translation layer: a Mach-O loader, a reimplementation of the macOS userland and a user-space "kernel" daemon (`darlingserver`). Since the 2023 rewrite it needs no kernel module.

KwickOS ships it as the optional package `kwick-darling`, built from a pinned upstream tag.

![A Cocoa window under Darling on Xvfb](img/darling.png)

## Install

```
apt update
apt install kwick-darling
```

The package is x86_64 (amd64) only. It installs `/usr/bin/darling` (setuid root, used to enter namespaces and mount the prefix overlay), `/usr/bin/darlingserver` and the macOS tree under `/usr/libexec/darling` (about 585 MB installed, 79 MB download).

## Use

```
darling shell
darling shell sw_vers
darling shell /bin/bash -c 'uname -srm; echo hello | tr a-z A-Z'
darling /path/to/CLI-binary args
```

Note: `darling shell <cmd>` takes a program and its arguments, not a shell string. Use `/bin/bash -c '...'` for pipelines.

The per-user prefix lives in `~/.darling`. Your Linux files are visible inside at `/Volumes/SystemRoot` (for example `/Volumes/SystemRoot/home/<you>`). Use another prefix location with `DPREFIX=/path darling shell`. Remove a prefix with `rm -rf ~/.darling`.

### Prefix must not sit on overlayfs

The prefix is itself an overlayfs upper directory, and the kernel refuses an overlay upper dir on another overlayfs (`Cannot mount overlay: Invalid argument`). On an installed disk (ext4/btrfs/xfs) or a tmpfs this is fine. Inside Docker, or when `/home` is on the live-ISO overlay, put the prefix on a volume or tmpfs:

```
sudo mount -t tmpfs -o size=4g,uid=$(id -u),gid=$(id -g) tmpfs /var/tmp/dp
DPREFIX=/var/tmp/dp/prefix darling shell
```

Do not place the prefix under `/dev/shm`: darlingserver mounts a fresh `/dev/shm` before the overlay and the prefix vanishes.

The first `darling shell` creates the prefix and can take a while.

### GUI

Cocoa/AppKit windows render through Darling's AppKit (Cocotron based) with a Vulkan/Mesa backend. Under X11 or XWayland:

```
sudo apt install xvfb libxrandr2 libxcursor1 libgl1 libegl1 libglu1-mesa libcairo2 libfontconfig1 libpulse0 libxkbfile1
Xvfb :99 -screen 0 1024x640x24 -extension MIT-SHM &
DISPLAY=:99 darling shell /path/to/App
```

The `-extension MIT-SHM` flag disables the MIT-SHM extension; without it Mesa failed with "Failed to attach to x11 shm" in a container and the window stayed blank. On a real desktop session this is not needed in the same way, but if windows are blank try disabling MIT-SHM.

The GUI libraries above are loaded at run time and are deliberately not hard dependencies of the package.

## What was verified

Built from `v0.1.20260608` (commit `e947f0d5a3c6`), run in a throwaway privileged container from `kwickos-desktop:040` (host kernel: Docker Desktop WSL2 6.6, not the KwickOS kernel).

Working:

- `darling shell` starts; `uname` reports `Darwin 20.6.0 x86_64`; `sw_vers` reports macOS 11.7.4.
- Stock tools: `ls`, `tr`, `file`, `otool`, `bash`, `zsh`, `vim`, `git`, `curl` (HTTPS to the internet works), `sysctl`.
- Interpreters: Perl, Ruby, `/usr/bin/python` (Python 2.7.16).
- A Mach-O x86_64 hello world (built on Linux with clang plus Darling's ld64, then executed with `darling shell /Volumes/SystemRoot/tmp/hello`).
- An Objective-C Cocoa program creating an `NSWindow` with a text field, shown on Xvfb (screenshot above; the window has no title bar because no window manager was running).

Does not work or is missing in this package:

- No `/usr/bin/python3`: macOS 11 shipped none and Darling provides Python 2.7 only.
- No usable compiler: `clang`, `cc` and `swift` are `xcrun` stubs that fail ("Failed to execute program .../DarlingCLT/usr/bin/clang") because the developer components are not part of the stock build. Cross-compile on Linux instead (see below) or install Xcode command-line tools into the prefix.
- `sqlite3`, `system_profiler` and `defaults` (host UUID lookup error) are absent or incomplete.
- `defaults` prints `_CFGetHostUUIDString: unable to determine UUID for host` warnings.
- Shader cache warning on GUI start (`Failed to create /Users for shader cache`), harmless.
- 32-bit Mach-O (i386) is not supported; the package is built with `-DTARGET_i386=OFF`.
- ARM64 (Apple Silicon) binaries are not supported, and Darling does not run on arm64 or riscv64 Linux in this package.
- Large GUI apps (Xcode and similar), DRM or system-extension based software, and anything needing a real kernel module generally do not work. Upstream describes the GUI stack as in development.

### Cross-compiling a Mach-O binary on Linux

The build tree contains Apple-flavoured ld64 (`x86_64-apple-darwin20-ld`). Extract the .deb and link against its libraries:

```
dpkg-deb -x kwick-darling_*_amd64.deb /x
clang -target x86_64-apple-darwin20 -isysroot "$SDK" -c hello.c -o hello.o
x86_64-apple-darwin20-ld -arch x86_64 -platform_version macos 11.0 11.0 -syslibroot /x/usr/libexec/darling -o hello hello.o -lSystem
```

`$SDK` is the `MacOSX.sdk` directory inside a Darling source checkout.

## Kernel requirements

Checked against `config/kernel/common.config` and the other fragments (generic-x86_64.config was not touched).

Already enabled: `NAMESPACES`, `USER_NS`, `PID_NS`, `UTS_NS`, `IPC_NS`, `NET_NS`, `OVERLAY_FS`, `FUSE_FS`, `SYSVIPC`, `EPOLL`, `EVENTFD`, `SIGNALFD`, `TIMERFD`, `FHANDLE`, `INOTIFY_USER`, `UNIX`, `PROC_FS`, `TMPFS`, `SECCOMP`.

Darling itself needs a kernel of 5.0 or newer. `darling` is setuid root, so unprivileged user namespaces are not strictly required, but the mount namespace plus overlayfs with a non-overlay upper directory are. darlingserver calls `pidfd_open` and `process_vm_readv/writev` and uses `ptrace`.

Suggested for the kernel owner (not edited here):

- `CONFIG_CROSS_MEMORY_ATTACH=y` for `process_vm_readv/writev`. It is on by default in x86 defconfig but make it explicit so it cannot be dropped.
- `CONFIG_PROC_SYSCTL` and `CONFIG_MEMFD_CREATE` are implied by existing options; no action.
- Yama is enabled (`CONFIG_SECURITY_YAMA=y`): darlingserver attaches with `ptrace` to its own descendants, which works with `kernel.yama.ptrace_scope` 0 or 1 but would break at 2 or higher.
- Root filesystem layout: the live ISO and containers whose `$HOME` lives on overlayfs need the prefix on tmpfs or a disk filesystem (see above).

## Build and release

The pin is in `config/darling.env` (`DARLING_TAG`, `DARLING_COMMIT`, `DARLING_PKG_REVISION`). `scripts/mkdarlingpkg.sh` builds it in a `debian:trixie` container (ninja, ccache) and writes `kwick-darling_<ver>_amd64.deb` to `$OUT/repo/pool/main`.

Local build:

```
docker run --rm --cpus=8 --memory=24g -e JOBS=8 \
  -v "$PWD:/src:ro" -v "$PWD/out:/out" -v kw-darling-work:/work \
  debian:trixie bash /src/scripts/mkdarlingpkg.sh
```

Reference numbers from the verification run: 26419 build steps, about 3 hours of cumulative wall time over several restarts on 8 niced cores with a warm ccache for part of it, 79 MB package, 585 MB installed. The upstream clone with submodules is several GB.

CI: `.github/workflows/darling.yml` runs on `workflow_dispatch` or when `config/darling.env` or `scripts/mkdarlingpkg.sh` change on main. It skips the build when the release `darling-<version>-<rev>` already holds the .deb, keeps a ccache across runs (saved even if the run is cut off) and uploads the package to that release. The main release workflow downloads it from there, if present, before signing the apt repository. A cold build on a 4-core GitHub runner is close to the 6 hour job limit; if a run is cut off, re-run it and ccache resumes. As a fallback, build locally as above and upload with:

```
. config/darling.env
gh release create "darling-${DARLING_TAG#v}-${DARLING_PKG_REVISION}" --title "darling-${DARLING_TAG#v}-${DARLING_PKG_REVISION}" --notes "Darling for KwickOS"
gh release upload "darling-${DARLING_TAG#v}-${DARLING_PKG_REVISION}" out/repo/pool/main/kwick-darling_*_amd64.deb --clobber
```

To update Darling: change `DARLING_TAG`/`DARLING_COMMIT` in `config/darling.env`, and bump `DARLING_PKG_REVISION` when only the packaging changes.
