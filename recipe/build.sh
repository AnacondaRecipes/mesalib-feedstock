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

# Set platforms option based on target platform
if [[ "$target_platform" == osx* ]]; then
  PLATFORMS="-Dplatforms=macos"
else
  PLATFORMS="-Dplatforms=x11"
fi

# ---
# Meson options/choices and rationale:
# -Dgallium-drivers: Comma-separated list of Gallium drivers to build (e.g. softpipe,llvmpipe,zink)
# -Dglx: Valid values are 'auto', 'disabled', 'dri', 'xlib'. Use 'dri' for Linux, 'disabled' for macOS.
# -Degl: Enable or disable EGL support. Disabled on macOS, enabled on Linux.
# -Dplatforms: Comma-separated list of platforms (e.g. x11,macos,wayland,drm). Use 'x11' for Linux, 'macos' for macOS.
# -Dvulkan-drivers: Comma-separated list of Vulkan drivers (e.g. swrast,virtio,all). Use 'swrast,virtio' for Linux, 'swrast' for macOS.
# -Dlibunwind: Enable or disable libunwind support. Enabled on Linux, disabled on macOS.
# -Dshared-glapi: Enable shared GL API. Enabled for both Linux and macOS.
#
# See https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/meson.options
# ---

# The --prefix=$PREFIX flag ensures proper installation location for conda-build
# We might want to have a static link of llvm (-Dshared-llvm=false). Similar to https://github.com/AnacondaRecipes/llvmlite-feedstock/pull/15
meson setup builddir/ \
  ${MESON_ARGS} \
  --prefix=$PREFIX \
  -Dlibdir=lib \
  $PLATFORMS \
  -Dvulkan-drivers=swrast \
  -Dgallium-drivers=softpipe,llvmpipe \
  -Dgallium-va=disabled \
  -Dgallium-vdpau=disabled \
  -Dgles1=disabled \
  -Dgles2=disabled \
  -Dgbm=disabled \
  -Dglvnd=disabled \
  -Dglx=disabled \
  -Degl=disabled \
  -Dllvm=enabled \
  -Dshared-llvm=true \
  -Dzstd=enabled \
  -Dopengl=true \
  -Dtools=[] \
  -Dbuild-tests=true \
  -Dlibunwind=enabled \
  -Dshared-glapi=enabled \
  -Dosmesa=false \
  -Dgallium-opencl=disabled \
  || { cat builddir/meson-logs/meson-log.txt; exit 1; }

ninja -C builddir/ -j ${CPU_COUNT}

ninja -C builddir/ install

echo "Running Mesa tests..."
meson test -C builddir/ -t 4 -v
