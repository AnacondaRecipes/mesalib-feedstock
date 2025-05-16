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

# OpenCL is disabled - removed deprecated options
OPENCL_OPTIONS="-Dgallium-opencl=disabled"

# OSMesa options - Mesa 25.1.0 still supports OSMesa but the interface has changed
OSMESA_OPTIONS="-Dosmesa=true"

# Common options across platforms
COMMON_OPTIONS="-Dzstd=enabled -Dopengl=true -Dtools=[] -Dbuild-tests=true"

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

if [[ "$target_platform" == linux* ]]; then
  GLVND_OPTION="-Dglvnd=enabled"
  GBM_OPTION="-Dgbm=enabled"
  VULKAN_DRIVERS="-Dvulkan-drivers=swrast,virtio"
  EGL_OPTION="-Degl=enabled"
  GLX_OPTION="-Dglx=dri"
  GLX_DIRECT="-Dglx-direct=false"
  GALLIUM_DRIVERS="-Dgallium-drivers=softpipe,virgl,llvmpipe,zink"
  PLATFORMS="-Dplatforms=x11"
  LINUX_OPTIONS="-Dlibunwind=enabled -Dshared-glapi=enabled"
  PLATFORM_OPTIONS="$LINUX_OPTIONS"
elif [[ "$target_platform" == osx* ]]; then
  GBM_OPTION="-Dgbm=disabled"
  VULKAN_DRIVERS="-Dvulkan-drivers=swrast"
  GALLIUM_DRIVERS="-Dgallium-drivers=softpipe,llvmpipe"
  GLX_OPTION="-Dglx=disabled"
  GLX_DIRECT=""
  EGL_OPTION="-Degl=disabled"
  PLATFORMS="-Dplatforms=macos"
  MACOS_OPTIONS="-Dlibunwind=disabled -Dshared-glapi=enabled"
  PLATFORM_OPTIONS="$MACOS_OPTIONS"
else
  GLVND_OPTION="-Dglvnd=disabled"
  VULKAN_DRIVERS="-Dvulkan-drivers=all"
  GALLIUM_DRIVERS="-Dgallium-drivers=all"
  GLX_OPTION="-Dglx=auto"
  GLX_DIRECT="-Dglx-direct=false"
  EGL_OPTION="-Degl=enabled"
  PLATFORMS="-Dplatforms=auto"
  PLATFORM_OPTIONS=""
fi

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
  -Dgles2=enabled \
  $GBM_OPTION \
  $GLVND_OPTION \
  $GLX_OPTION \
  $GLX_DIRECT \
  $EGL_OPTION \
  -Dllvm=enabled \
  -Dshared-llvm=enabled \
  $COMMON_OPTIONS \
  $PLATFORM_OPTIONS \
  $OSMESA_OPTIONS \
  $OPENCL_OPTIONS \
  || { cat builddir/meson-logs/meson-log.txt; exit 1; }

ninja -C builddir/ -j ${CPU_COUNT}

ninja -C builddir/ install

echo "Running Mesa tests..."
meson test -C builddir/ -t 4 -v
