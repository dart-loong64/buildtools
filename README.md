# buildtools

The GitHub Actions workflow builds Fuchsia's two-stage Flutter Clang toolchain
for amd64, arm64, loong64, and riscv64 on an x64 Ubuntu 26.04 runner. It installs the
corresponding Linux cross compiler/sysroot, so the non-amd64 jobs produce
target-architecture Clang binaries. Start it with **Actions → Build Flutter
Clang → Run workflow** and provide the LLVM commit SHA.

The local entry point accepts only the two build parameters:

```bash
./build-clang.sh --llvm-revision 80743bd43fd5b38fedc503308e7a652e23d3ec93 \
  --arch loong64
```

It clones Fuchsia, checks out the requested LLVM commit, patches the selected
backend and Linux target into `Fuchsia-stage2.cmake`, then runs Fuchsia's
`Fuchsia.cmake` bootstrap/stage2 targets. `FLUTTER_ROOT` is not required.

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
