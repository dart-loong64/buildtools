#!/usr/bin/env bash
# Builds an x86_64-hosted Fuchsia clang with Linux cross-compilation targets.
set -euo pipefail

arch=$(uname -m)
case "${arch}" in
  x86_64) build_arch=x64 ;;
  aarch64) build_arch=arm64 ;;
  loongarch64) build_arch=loong64 ;;
  *) build_arch="${arch}" ;;
esac

jobs="${JOBS:-$(nproc)}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
flutter_root="$(cd "${script_dir}/../../../.." && pwd)"
depot_tools="${flutter_root}/tmp/depot_tools"
fuchsia_dir="${flutter_root}/tmp/fuchsia"
llvm_src="${fuchsia_dir}/third_party/llvm-project"
build_dir="${flutter_root}/tmp/flutter-clang-build"
package_dir="${flutter_root}/dist"
install_dir="$(mktemp -d /tmp/flutter-clang-${build_arch}.XXXXXX)"

depot_tools_repo="https://chromium.googlesource.com/chromium/tools/depot_tools.git"
fuchsia_repo="https://fuchsia.googlesource.com/fuchsia"

mkdir -p "${build_dir}"

if [[ ! -e "${depot_tools}" ]]; then
  mkdir -p "$(dirname "${depot_tools}")"
  git clone --depth 1 "${depot_tools_repo}" "${depot_tools}"
elif [[ ! -d "${depot_tools}/.git" ]]; then
  echo "${depot_tools} exists but is not a depot_tools git checkout" >&2
  exit 1
fi
export PATH="${depot_tools}:${PATH}"

if [[ ! -e "${fuchsia_dir}" ]]; then
  git clone --depth 1 "${fuchsia_repo}" "${fuchsia_dir}"
elif [[ ! -d "${fuchsia_dir}/.git" ]]; then
  echo "${fuchsia_dir} exists but is not a Fuchsia git checkout" >&2
  exit 1
fi

engine_src="${flutter_root}/engine/src"
x64_sysroot="${engine_src}/build/linux/debian_bullseye_amd64-sysroot"
x86_sysroot="${engine_src}/build/linux/debian_bullseye_i386-sysroot"
arm_sysroot="${engine_src}/build/linux/debian_bullseye_armhf-sysroot"
arm64_sysroot="${engine_src}/build/linux/debian_bullseye_arm64-sysroot"
loong64_sysroot="${engine_src}/build/linux/debian_trixie_loong64-sysroot"
riscv64_sysroot="${engine_src}/build/linux/debian_trixie_riscv64-sysroot"

command -v cmake >/dev/null
command -v ninja >/dev/null
command -v pkg-config >/dev/null
if ! pkg-config --exists libxml-2.0; then
  echo "libxml2 development files are required (install libxml2-dev)" >&2
  exit 1
fi

clang_revision="$(sed -n "s/.*'clang_version': 'git_revision:\([0-9a-f]\{40\}\)'.*/\1/p" "${flutter_root}/DEPS")"
if [[ ! "${clang_revision}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "unable to read clang_version from ${flutter_root}/DEPS" >&2
  exit 1
fi

if [[ ! -e "${llvm_src}" ]]; then
  mkdir -p "$(dirname "${llvm_src}")"
  git clone --depth 1 https://llvm.googlesource.com/llvm-project "${llvm_src}"
elif [[ ! -d "${llvm_src}/.git" ]]; then
  echo "${llvm_src} exists but is not an LLVM git checkout" >&2
  exit 1
fi

if [[ "$(git -C "${llvm_src}" rev-parse HEAD)" != "${clang_revision}" ]]; then
  if [[ -n "$(git -C "${llvm_src}" status --porcelain)" ]]; then
    echo "${llvm_src} has uncommitted changes; refusing to switch revisions" >&2
    exit 1
  fi
  git -C "${llvm_src}" fetch --depth 1 origin "${clang_revision}"
  git -C "${llvm_src}" checkout --detach "${clang_revision}"
fi

stage1_cmake="${llvm_src}/clang/cmake/caches/Fuchsia.cmake"
stage2_cmake="${llvm_src}/clang/cmake/caches/Fuchsia-stage2.cmake"
test -f "${stage1_cmake}"
test -f "${stage2_cmake}"
if ! grep -Eq 'LLVM_TARGETS_TO_BUILD.*LoongArch' "${stage1_cmake}"; then
  git -C "${llvm_src}" apply - <<'PATCH'
diff --git a/clang/cmake/caches/Fuchsia.cmake b/clang/cmake/caches/Fuchsia.cmake
--- a/clang/cmake/caches/Fuchsia.cmake
+++ b/clang/cmake/caches/Fuchsia.cmake
@@ -2,6 +2,6 @@
 
 option(FUCHSIA_ENABLE_LLDB "Enable LLDB")
 
-set(LLVM_TARGETS_TO_BUILD X86;ARM;AArch64;RISCV CACHE STRING "")
+set(LLVM_TARGETS_TO_BUILD X86;ARM;AArch64;RISCV;LoongArch CACHE STRING "")
 
 set(PACKAGE_VENDOR Fuchsia CACHE STRING "")
PATCH
fi

if ! grep -Eq 'LLVM_TARGETS_TO_BUILD.*LoongArch' "${stage2_cmake}" || \
  ! grep -q 'loongarch64-unknown-linux-gnu' "${stage2_cmake}"; then
  git -C "${llvm_src}" apply - <<'PATCH'
diff --git a/clang/cmake/caches/Fuchsia-stage2.cmake b/clang/cmake/caches/Fuchsia-stage2.cmake
--- a/clang/cmake/caches/Fuchsia-stage2.cmake
+++ b/clang/cmake/caches/Fuchsia-stage2.cmake
@@ -2,6 +2,6 @@
 
 option(FUCHSIA_ENABLE_LLDB "Enable LLDB")
 
-set(LLVM_TARGETS_TO_BUILD X86;ARM;AArch64;RISCV CACHE STRING "")
+set(LLVM_TARGETS_TO_BUILD X86;ARM;AArch64;RISCV;LoongArch CACHE STRING "")
 
 set(PACKAGE_VENDOR Fuchsia CACHE STRING "")
@@ -138,6 +138,6 @@
   set(RUNTIMES_${target}_CMAKE_MODULE_LINKER_FLAGS ${WINDOWS_LINK_FLAGS} CACHE STRING "")
 endif()
 
-foreach(target aarch64-unknown-linux-gnu;armv7-unknown-linux-gnueabihf;i386-unknown-linux-gnu;riscv64-unknown-linux-gnu;x86_64-unknown-linux-gnu)
+foreach(target aarch64-unknown-linux-gnu;armv7-unknown-linux-gnueabihf;i386-unknown-linux-gnu;loongarch64-unknown-linux-gnu;riscv64-unknown-linux-gnu;x86_64-unknown-linux-gnu)
   if(LINUX_${target}_SYSROOT)
     # Set the per-target builtins options.
PATCH
fi

sysroot_installer="${engine_src}/build/linux/sysroot_scripts/install-sysroot.py"
for arch in x64 x86 arm arm64 loong64 riscv64; do
  echo "fetching ${arch} Linux sysroot"
  python3 "${sysroot_installer}" --arch="${arch}"
done
for sysroot in "${x64_sysroot}" "${x86_sysroot}" "${arm_sysroot}" \
  "${arm64_sysroot}" "${loong64_sysroot}" "${riscv64_sysroot}"; do
  test -f "${sysroot}/.stamp"
done

cmake -S "${llvm_src}/llvm" -B "${build_dir}" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_LIBXML2=ON \
  -DLLVM_PARALLEL_LINK_JOBS=1 \
  -DSTAGE2_LLVM_PARALLEL_LINK_JOBS=1 \
  -DSTAGE2_LINUX_x86_64-unknown-linux-gnu_SYSROOT="${x64_sysroot}" \
  -DSTAGE2_LINUX_i386-unknown-linux-gnu_SYSROOT="${x86_sysroot}" \
  -DSTAGE2_LINUX_armv7-unknown-linux-gnueabihf_SYSROOT="${arm_sysroot}" \
  -DSTAGE2_LINUX_aarch64-unknown-linux-gnu_SYSROOT="${arm64_sysroot}" \
  -DSTAGE2_LINUX_loongarch64-unknown-linux-gnu_SYSROOT="${loong64_sysroot}" \
  -DSTAGE2_LINUX_riscv64-unknown-linux-gnu_SYSROOT="${riscv64_sysroot}" \
  -DCMAKE_INSTALL_PREFIX= \
  -C "${stage1_cmake}"

ninja -C "${build_dir}" stage2-toolchain-distribution -j"${jobs}"
DESTDIR="${install_dir}" ninja -C "${build_dir}" \
  stage2-install-toolchain-distribution-stripped -j"${jobs}"

"${install_dir}/bin/clang" --version
printf 'int main(void) { return 0; }\n' | "${install_dir}/bin/clang" \
  --target=loongarch64-unknown-linux-gnu -x c -c - -o "${build_dir}/loongarch-test.o"
readelf -h "${build_dir}/loongarch-test.o" | grep -F 'Machine:                           LoongArch'

mkdir -p "${package_dir}"
tar -C "${install_dir}" -czf "${package_dir}/clang-linux-${build_arch}.tar.gz" .
tar -C "${install_dir}" -cJf "${package_dir}/clang-linux-${build_arch}.tar.xz" .

printf 'install: %s\narchive: %s/clang-linux-${build_arch}.{tar.gz,tar.xz}\n' \
  "${install_dir}" "${package_dir}"
