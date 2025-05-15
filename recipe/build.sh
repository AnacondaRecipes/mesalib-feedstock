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

# Add OpenCL options (disabled for now)
OPENCL_OPTIONS="-Dgallium-opencl=disabled -Dclc-libdir=$PREFIX/lib"

# Add explicit OSMESA options
OSMESA_OPTIONS="-Dosmesa=true -Dosmesa-bits=8"

if [[ "$target_platform" == linux* ]]; then
  GLVND_OPTION="-Dglvnd=enabled"
  GBM_OPTION="-Dgbm=enabled"
  # "vulkan-drivers" allowed choices: "auto, amd, broadcom, freedreno, intel, intel_hasvk, panfrost, swrast, virtio, imagination-experimental, microsoft-experimental, nouveau, asahi, gfxstream, all"
  VULKAN_DRIVERS="-Dvulkan-drivers=swrast,virtio"
  
  # Enable EGL on Linux
  EGL_OPTION="-Degl=enabled"
  # Valid GLX options are: "auto", "disabled", "dri", "xlib"
  GLX_OPTION="-Dglx=dri"
  GLX_DIRECT="-Dglx-direct=false"

  # Expand Gallium drivers on Linux
  GALLIUM_DRIVERS="-Dgallium-drivers=softpipe,virgl,llvmpipe,zink,crocus,iris"
elif [[ "$target_platform" == osx* ]]; then
  # On osx platfroms: meson.build:458:3: ERROR: Feature gbm cannot be enabled: GBM only supports DRM/KMS platforms
  GBM_OPTION="-Dgbm=disabled"
  
  VULKAN_DRIVERS="-Dvulkan-drivers=swrast"

  GALLIUM_DRIVERS="-Dgallium-drivers=softpipe,llvmpipe"

  # Disable Apple GLX to avoid compatibility issues
  # Valid GLX options are: "auto", "disabled", "dri", "xlib"
  GLX_OPTION="-Dglx=disabled"
  GLX_DIRECT="-Dglx-direct=false"
  
  # Disable EGL on macOS as it requires DRI, Haiku, Windows or Android
  EGL_OPTION="-Degl=disabled"
else
  GLVND_OPTION="-Dglvnd=disabled"
  VULKAN_DRIVERS="-Dvulkan-drivers=all"  # Keep all for other platforms
  GALLIUM_DRIVERS="-Dgallium-drivers=all"
  # Valid GLX options are: "auto", "disabled", "dri", "xlib"
  GLX_OPTION="-Dglx=auto"
  GLX_DIRECT="-Dglx-direct=false"
  EGL_OPTION="-Degl=enabled"
fi

meson setup builddir/ \
  ${MESON_ARGS} \
  --prefix=$PREFIX \
  -Dlibdir=lib \
  -Dplatforms=x11 \
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
  -Dshared-glapi=enabled \
  -Dlibunwind=enabled \
  -Dzstd=enabled \
  $OSMESA_OPTIONS \
  $OPENCL_OPTIONS \
  -Dopengl=true \
  || { cat builddir/meson-logs/meson-log.txt; exit 1; }

ninja -C builddir/ -j ${CPU_COUNT}

ninja -C builddir/ install

meson test -C builddir/ \
  -t 4
