# buildtools

The GitHub Actions workflow first checks out the requested Flutter tag, reads
its LLVM revision from `DEPS`, and prepares Fuchsia and its LLVM checkout once.
It then builds Fuchsia's two-stage Flutter Clang toolchain on amd64 and arm64
Ubuntu 24.04 runners. Start it with **Actions → Build Flutter Clang → Run
workflow** and provide the Flutter tag or commit.

The local entry point reads the LLVM revision from `DEPS` and uses the host
architecture automatically. From the Flutter root, run:

```bash
./engine/src/flutter/buildtools/build-clang.sh
```

It clones Fuchsia into `./tmp/fuchsia`, checks out the LLVM revision read from
the Flutter `DEPS`, applies the LoongArch CMake changes directly to LLVM's
Fuchsia stage1/stage2 cache files, then runs Fuchsia's `Fuchsia.cmake` bootstrap/stage2
targets. The script invokes Flutter's
`engine/src/build/linux/sysroot_scripts/install-sysroot.py` for x64, x86, arm,
arm64, loong64, and riscv64.

Each archive has the toolchain contents at its root, including `bin/clang`.
Archives are written to `dist/` using the host architecture, for example:

```text
clang-linux-x64.tar.gz       clang-linux-x64.tar.xz
clang-linux-arm64.tar.gz     clang-linux-arm64.tar.xz
```
