#!/usr/bin/env bash
# Build a Fuchsia two-stage Clang distribution for one host architecture.
# The script intentionally accepts only --llvm-revision and --arch.

set -euo pipefail
IFS=$'\n\t'

readonly FUCHSIA_URL='https://fuchsia.googlesource.com/fuchsia'
readonly LLVM_URL='https://llvm.googlesource.com/llvm-project'
readonly ROOT_DIR="$PWD"
readonly DIST_DIR="$ROOT_DIR/dist"
readonly JOBS="${JOBS:-$(nproc)}"

usage() {
  cat >&2 <<'EOF'
Usage:
  build-clang.sh --llvm-revision <40-character-commit> \
    --arch <amd64|arm64|loong64|riscv64>
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

[[ $# -eq 4 ]] || { usage; exit 2; }
if [[ "$1" == '--llvm-revision' && "$3" == '--arch' ]]; then
  llvm_revision="$2"
  arch="$4"
elif [[ "$1" == '--arch' && "$3" == '--llvm-revision' ]]; then
  arch="$2"
  llvm_revision="$4"
else
  usage
  die 'only --llvm-revision and --arch are accepted'
fi

[[ "$llvm_revision" =~ ^[[:xdigit:]]{40}$ ]] ||
  die 'LLVM revision must be a 40-character SHA'

case "$arch" in
  amd64)
    target_triple='x86_64-unknown-linux-gnu'
    package_arch='x64'
    target_processor='x86_64'
    llvm_backend='X86'
    elf_machine='Advanced Micro Devices X86-64'
    sysroot_name='debian_bullseye_amd64-sysroot'
    ;;
  arm64)
    target_triple='aarch64-unknown-linux-gnu'
    package_arch='arm64'
    target_processor='aarch64'
    llvm_backend='AArch64'
    elf_machine='AArch64'
    sysroot_name='debian_bullseye_arm64-sysroot'
    ;;
  loong64)
    target_triple='loongarch64-unknown-linux-gnu'
    package_arch='loong64'
    target_processor='loongarch64'
    llvm_backend='LoongArch'
    elf_machine='LoongArch'
    sysroot_name='debian_trixie_loong64-sysroot'
    ;;
  riscv64)
    target_triple='riscv64-unknown-linux-gnu'
    package_arch='riscv64'
    target_processor='riscv64'
    llvm_backend='RISCV'
    elf_machine='RISC-V'
    sysroot_name='debian_trixie_riscv64-sysroot'
    ;;
  *)
    die "unsupported architecture: $arch"
    ;;
esac

sysroot="$ROOT_DIR/sysroots/$sysroot_name"

for command_name in cmake file git grep head mktemp ninja nproc readelf sed strings tar xz; do
  command -v "$command_name" >/dev/null || die "missing command: $command_name"
done
[[ -d "$sysroot" ]] || die "cross sysroot is missing: $sysroot"

mkdir -p "$DIST_DIR"
fuchsia_root="$ROOT_DIR/fuchsia"

build_root="$(mktemp -d "${TMPDIR:-/tmp}/fuchsia-clang-${arch}.XXXXXX")"
cleanup() {
  rm -rf "$build_root"
}
trap cleanup EXIT

llvm_source="$fuchsia_root/third_party/llvm-project"
if [[ -d "$fuchsia_root/.git" ]]; then
  echo "==> Using cached Fuchsia: $fuchsia_root"
else
  [[ ! -e "$fuchsia_root" ]] || die "invalid Fuchsia directory: $fuchsia_root"
  echo "==> Cloning Fuchsia"
  git clone --depth=1 "$FUCHSIA_URL" "$fuchsia_root"
fi

if [[ -d "$llvm_source/.git" ]]; then
  actual_llvm_revision="$(git -C "$llvm_source" rev-parse HEAD)"
  [[ "$actual_llvm_revision" == "$llvm_revision" ]] ||
    die "cached LLVM revision mismatch: expected $llvm_revision, got $actual_llvm_revision"
  echo "==> Using cached LLVM revision $llvm_revision"
else
  echo "==> Cloning LLVM at $llvm_revision"
  mkdir -p "$(dirname "$llvm_source")"
  git clone --filter=blob:none --no-checkout "$LLVM_URL" "$llvm_source"
  git -C "$llvm_source" fetch --depth=1 origin "$llvm_revision"
  git -C "$llvm_source" checkout --detach "$llvm_revision"
fi

stage2_cache="$llvm_source/clang/cmake/caches/Fuchsia-stage2.cmake"
[[ -f "$stage2_cache" ]] || die "missing stage2 cache: $stage2_cache"

all_llvm_targets="$(sed -nE 's/^set\(LLVM_TARGETS_TO_BUILD ([^ ]+) CACHE STRING.*/\1/p' "$stage2_cache")"
grep -q "$llvm_backend" <<< "$all_llvm_targets" ||
  die "${llvm_backend} backend patch was not applied"

build_dir="$fuchsia_root/out/clang-$arch"
install_dir="$build_root/install"
fuchsia_cache="$llvm_source/clang/cmake/caches/Fuchsia.cmake"
stage2_args="-C;${stage2_cache};-DCMAKE_SYSTEM_NAME=Linux;-DCMAKE_SYSTEM_PROCESSOR=${target_processor};-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY;-DBOOTSTRAP_CMAKE_SYSTEM_NAME=Linux;-DBOOTSTRAP_CMAKE_SYSTEM_PROCESSOR=${target_processor};-DBOOTSTRAP_CMAKE_C_COMPILER_TARGET=${target_triple};-DBOOTSTRAP_CMAKE_CXX_COMPILER_TARGET=${target_triple};-DBOOTSTRAP_CMAKE_ASM_COMPILER_TARGET=${target_triple};-DCMAKE_C_COMPILER_TARGET=${target_triple};-DCMAKE_CXX_COMPILER_TARGET=${target_triple};-DCMAKE_ASM_COMPILER_TARGET=${target_triple};-DLLVM_HOST_TRIPLE=${target_triple};-DCLANG_DEFAULT_TARGET_TRIPLE=${target_triple};-DLINUX_${target_triple}_SYSROOT=${sysroot};-DCMAKE_SYSROOT=${sysroot}"

echo '==> Configuring Fuchsia bootstrap/stage2 build'
cmake -S "$llvm_source/llvm" -B "$build_dir" -G Ninja \
  -C "$fuchsia_cache" \
  -DCMAKE_INSTALL_PREFIX= \
  -DSTAGE2_LINUX_${target_triple}_SYSROOT="$sysroot" \
  -DCLANG_BOOTSTRAP_CMAKE_ARGS="$stage2_args" \
  -DLLVM_TARGETS_TO_BUILD="$all_llvm_targets" \
  -DLLVM_DEFAULT_TARGET_TRIPLE="$target_triple" \
  -DCLANG_REPOSITORY_STRING="$LLVM_URL $llvm_revision" \
  -DLLVM_FORCE_VC_REPOSITORY="$LLVM_URL" \
  -DLLVM_FORCE_VC_REVISION="$llvm_revision"

echo '==> Building bootstrap and stage2 distribution'
ninja -C "$build_dir" -j"$JOBS" stage2-toolchain-distribution
DESTDIR="$install_dir" ninja -C "$build_dir" -j"$JOBS" \
  stage2-install-toolchain-distribution-stripped

[[ -x "$install_dir/bin/clang" ]] || die 'stage2 clang was not installed'
clang_dir="$(mktemp -d "/tmp/flutter-clang-$package_arch.XXXXXX")"
archive_stage="$(mktemp -d "/tmp/clang-linux-$package_arch-archive.XXXXXX")"
trap 'rm -rf "$build_root" "$archive_stage"' EXIT
cp -a "$install_dir"/. "$clang_dir"/

if [[ "$arch" == 'amd64' ]]; then
  clang_version="$($clang_dir/bin/clang --version)"
  echo "$clang_version"
  grep -q "Fuchsia clang version .* $llvm_revision" <<< "$clang_version" ||
    die 'clang revision mismatch'
  grep -q "Target: $target_triple" <<< "$clang_version" ||
    die "clang target mismatch: expected $target_triple"
  grep -q "InstalledDir: $clang_dir/bin" <<< "$clang_version" ||
    die 'clang InstalledDir mismatch'
else
  elf_header="$(readelf -h "$clang_dir/bin/clang")"
  grep -q "Machine:.*${elf_machine}" <<< "$elf_header" ||
    die "clang ELF machine mismatch: expected $elf_machine"
  file "$clang_dir/bin/clang"
  strings "$clang_dir/bin/clang" | grep -q "$llvm_revision" ||
    die 'clang revision is missing from the cross-built binary'
fi

archive_root='llvm'
mkdir "$archive_stage/$archive_root"
cp -a "$clang_dir"/. "$archive_stage/$archive_root"/
gzip_archive="$DIST_DIR/clang-linux-$package_arch.tar.gz"
xz_archive="$DIST_DIR/clang-linux-$package_arch.tar.xz"

echo "==> Creating $gzip_archive"
tar -C "$archive_stage" --numeric-owner -czf "$gzip_archive" "$archive_root"
echo "==> Creating $xz_archive"
tar -C "$archive_stage" --numeric-owner -I 'xz -T0 -6' \
  -cf "$xz_archive" "$archive_root"

[[ "$(tar -tzf "$gzip_archive" | head -1)" == "$archive_root/" ]] ||
  die 'bad gzip archive root'
[[ "$(tar -tJf "$xz_archive" | head -1)" == "$archive_root/" ]] ||
  die 'bad xz archive root'

echo '==> Complete'
ls -lh "$gzip_archive" "$xz_archive"
