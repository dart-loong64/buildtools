# buildtools

The GitHub Actions workflow first checks out the requested Flutter tag, reads
its LLVM revision from `DEPS`, and prepares Fuchsia and its LLVM checkout once.
It then builds Fuchsia's two-stage Flutter Clang toolchain for amd64, arm64,
loong64, and riscv64 on x64 Ubuntu 26.04 runners. Start it with **Actions →
Build Flutter Clang → Run workflow** and provide the Flutter tag or commit.

The local entry point accepts only the two build parameters:

```bash
./build-clang.sh --llvm-revision 80743bd43fd5b38fedc503308e7a652e23d3ec93 \
  --arch loong64
```

It clones Fuchsia into `./fuchsia`, checks out the LLVM revision read from the
Flutter `DEPS`, applies `patch_loong64.patch`, then runs Fuchsia's
`Fuchsia.cmake` bootstrap/stage2 targets. The workflow invokes Flutter's
`engine/src/build/linux/sysroot_scripts/install-sysroot.py` for the four target
architectures and caches the resulting sysroots. `FLUTTER_ROOT` is not
required.

Each archive has an `llvm/` root, matching the downloaded Flutter toolchain
layout. The temporary validation directory uses the same form as Flutter,
such as `/tmp/flutter-clang-x64.XXXXXX/bin`.

The workflow uploads these archives for each matrix entry:

```text
clang-linux-x64.tar.gz       clang-linux-x64.tar.xz
clang-linux-arm64.tar.gz     clang-linux-arm64.tar.xz
clang-linux-loong64.tar.gz   clang-linux-loong64.tar.xz
clang-linux-riscv64.tar.gz   clang-linux-riscv64.tar.xz
```
