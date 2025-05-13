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

  # libclc is a required dependency for OpenCL support, which is used by some Gallium drivers like "rusticl" (the Rust OpenCL implementation).
  # Mesa automatically tries to also enable OpenCL support, which needs the libclc library. 
  # But libclc isn't available on the main channel:
  # "Dependency 'libclc' not found, tried pkgconfig".
  GALLIUM_DRIVERS="-Dgallium-drivers=softpipe,virgl,llvmpipe,zink" # no rusticl
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
  $GALLIUM_DRIVERS \
  -Dgallium-va=disabled \
  -Dgallium-vdpau=disabled \
  -Dgles1=disabled \
  -Dgles2=disabled \
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
  -Dosmesa=true \
  -Dopengl=true \
  || { cat builddir/meson-logs/meson-log.txt; exit 1; }

ninja -C builddir/ -j ${CPU_COUNT}

ninja -C builddir/ install

meson test -C builddir/ \
  -t 4
