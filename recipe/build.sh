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

# Always disable GLX, EGL, and GBM to match conda-forge and modern glvnd-based OpenGL usage
GLX_OPTION="-Dglx=disabled"
EGL_OPTION="-Degl=disabled"
GBM_OPTION="-Dgbm=disabled"
GALLIUM_DRIVERS="-Dgallium-drivers=softpipe,llvmpipe"
VULKAN_DRIVERS="-Dvulkan-drivers=swrast"
GLVND_OPTION="-Dglvnd=enabled"
PLATFORMS="-Dplatforms=x11"
COMMON_OPTIONS="-Dzstd=enabled -Dopengl=true -Dtools=[] -Dbuild-tests=true"
LINUX_OPTIONS="-Dlibunwind=enabled -Dshared-glapi=enabled"
OSMESA_OPTIONS="-Dosmesa=true"
OPENCL_OPTIONS="-Dgallium-opencl=disabled"

# OSMesa options - Mesa 25.1.0 still supports OSMesa but the interface has changed
OSMESA_OPTIONS="-Dosmesa=true"

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
# These options were chosen to match upstream, conda-forge, and downstream needs, and to avoid building unsupported or unnecessary features on each platform.
# ---

# The --prefix=$PREFIX flag ensures proper installation location for conda-build
meson setup builddir/ \
  ${MESON_ARGS} \
  --prefix=$PREFIX \
  -Dlibdir=lib \
  $PLATFORMS \
  $VULKAN_DRIVERS \
  $GALLIUM_DRIVERS \
  -Dgallium-va=disabled \
  -Dgallium-vdpau=disabled \
  -Dgles1=disabled \
  -Dgles2=disabled \
  $GBM_OPTION \
  $GLVND_OPTION \
  $GLX_OPTION \
  $EGL_OPTION \
  -Dllvm=enabled \
  -Dshared-llvm=enabled \
  $COMMON_OPTIONS \
  $LINUX_OPTIONS \
  $OSMESA_OPTIONS \
  $OPENCL_OPTIONS \
  || { cat builddir/meson-logs/meson-log.txt; exit 1; }

ninja -C builddir/ -j ${CPU_COUNT}

ninja -C builddir/ install

echo "Running Mesa tests..."
meson test -C builddir/ -t 4 -v
