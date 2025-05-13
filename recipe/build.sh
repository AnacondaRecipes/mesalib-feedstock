#!/bin/bash

set -ex

export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:$BUILD_PREFIX/lib/pkgconfig
export PKG_CONFIG=$BUILD_PREFIX/bin/pkg-config

if [[ $CONDA_BUILD_CROSS_COMPILATION == "1" ]]; then
  if [[ "${CMAKE_CROSSCOMPILING_EMULATOR:-}" == "" ]]; then
    # Mostly taken from https://github.com/conda-forge/pocl-feedstock/blob/b88046a851a95ab3c676c0b7815da8224bd66a09/recipe/build.sh#L52
    rm $PREFIX/bin/llvm-config
    cp $BUILD_PREFIX/bin/llvm-config $PREFIX/bin/llvm-config
    export LLVM_CONFIG=${PREFIX}/bin/llvm-config
  else
    # https://github.com/mesonbuild/meson/issues/4254
    export LLVM_CONFIG=${BUILD_PREFIX}/bin/llvm-config
  fi
fi

# Add this before meson setup
if [[ "$target_platform" == linux* ]]; then
  GLVND_OPTION="-Dglvnd=enabled"
  GBM_OPTION="-Dgbm=enabled"
  VULKAN_DRIVERS="-Dvulkan-drivers=swrast,virtio"  # Linux compatible drivers only
elif [[ "$target_platform" == osx* ]]; then
  # macOS has limited Vulkan support
  VULKAN_DRIVERS="-Dvulkan-drivers=swrast"
  # On osx platfroms: meson.build:458:3: ERROR: Feature gbm cannot be enabled: GBM only supports DRM/KMS platforms
  GBM_OPTION="-Dgbm=disabled"
else
  GLVND_OPTION="-Dglvnd=disabled"
  VULKAN_DRIVERS="-Dvulkan-drivers=all"  # Keep all for other platforms
fi


echo "=== BEGIN DIAGNOSTICS ==="
echo "TARGET_PLATFORM: $target_platform"
echo "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
echo "PREFIX: $PREFIX"
echo "Checking for libglvnd.pc..."
if [[ -d "$PREFIX/lib/pkgconfig/" ]]; then
  ls -la $PREFIX/lib/pkgconfig/ | grep glvnd || echo "No libglvnd.pc in $PREFIX/lib/pkgconfig/"
else
  echo "$PREFIX/lib/pkgconfig/ directory does not exist"
fi
echo "=== END DIAGNOSTICS ==="

meson setup builddir/ \
  ${MESON_ARGS} \
  --prefix=$PREFIX \
  -Dlibdir=lib \
  -Dplatforms=x11 \
  $VULKAN_DRIVERS \
  -Dgallium-drivers=all \
  -Dgallium-va=disabled \
  -Dgallium-vdpau=disabled \
  -Dgles1=disabled \
  -Dgles2=disabled \
  $GBM_OPTION \
  $GLVND_OPTION \
  -Degl=enabled \
  -Dllvm=enabled \
  -Dshared-llvm=enabled \
  -Dlibunwind=enabled \
  -Dzstd=enabled \
  -Dglx-direct=false \
  || { cat builddir/meson-logs/meson-log.txt; exit 1; }

ninja -C builddir/ -j ${CPU_COUNT}

ninja -C builddir/ install

# Tests are skipped because they primarily test libraries omitted from this build.
meson test -C builddir/ \
  -t 4
