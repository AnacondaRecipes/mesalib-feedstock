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
else
  GLVND_OPTION="-Dglvnd=disabled"
fi

# Add this before meson setup
echo "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
echo "Checking for libglvnd.pc..."
if [[ "$target_platform" == linux* ]]; then
  ls -la $PREFIX/lib/pkgconfig/ | grep glvnd || echo "No libglvnd.pc in $PREFIX/lib/pkgconfig/"
fi

meson setup builddir/ \
  ${MESON_ARGS} \
  --prefix=$PREFIX \
  -Dlibdir=lib \
  -Dplatforms=x11 \
  -Dvulkan-drivers=all \
  -Dgallium-drivers=all \
  -Dgallium-va=disabled \
  -Dgallium-vdpau=disabled \
  -Dgles1=disabled \
  -Dgles2=disabled \
  -Dgbm=enabled \
  $GLVND_OPTION \
  -Degl=enabled \
  -Dglvnd=enabled \
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
