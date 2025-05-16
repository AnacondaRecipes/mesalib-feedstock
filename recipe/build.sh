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
  GALLIUM_DRIVERS="-Dgallium-drivers=softpipe,virgl,llvmpipe,zink"
  
  # Set platforms for Linux
  PLATFORMS="-Dplatforms=x11"
  
  # Linux-specific options
  LINUX_OPTIONS="-Dlibunwind=enabled -Dshared-glapi=enabled"
  
  PLATFORM_OPTIONS="$LINUX_OPTIONS"
elif [[ "$target_platform" == osx* ]]; then
  # On macOS, completely disable features that depend on X11/xcb/DRI
  GBM_OPTION="-Dgbm=disabled"
  
  VULKAN_DRIVERS="-Dvulkan-drivers=swrast"

  # Use only software rasterizers that work on macOS
  GALLIUM_DRIVERS="-Dgallium-drivers=softpipe,llvmpipe"

  # Disable GLX completely on macOS (macOS uses CGL instead)
  GLX_OPTION="-Dglx=disabled"
  GLX_DIRECT=""
  
  # Disable EGL on macOS as it's not well supported
  EGL_OPTION="-Degl=disabled"
  
  # Set platforms explicitly to macos for Mesa on macOS
  PLATFORMS="-Dplatforms=macos"
  
  # MacOS-specific options - disable libunwind as it's not needed
  MACOS_OPTIONS="-Dlibunwind=disabled -Dshared-glapi=enabled"
  
  PLATFORM_OPTIONS="$MACOS_OPTIONS"
else
  GLVND_OPTION="-Dglvnd=disabled"
  VULKAN_DRIVERS="-Dvulkan-drivers=all"  # Keep all for other platforms
  GALLIUM_DRIVERS="-Dgallium-drivers=all"
  # Valid GLX options are: "auto", "disabled", "dri", "xlib"
  GLX_OPTION="-Dglx=auto"
  GLX_DIRECT="-Dglx-direct=false"
  EGL_OPTION="-Degl=enabled"
  PLATFORMS="-Dplatforms=auto"
  
  PLATFORM_OPTIONS=""
fi

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

# Print the full test log for debugging if it exists
if [ -f builddir/meson-logs/testlog.txt ]; then
  echo "\n===== BEGIN FULL MESON TEST LOG (builddir) ====="
  cat builddir/meson-logs/testlog.txt
  echo "===== END FULL MESON TEST LOG (builddir) =====\n"
elif [ -f $SRC_DIR/builddir/meson-logs/testlog.txt ]; then
  echo "\n===== BEGIN FULL MESON TEST LOG (SRC_DIR) ====="
  cat $SRC_DIR/builddir/meson-logs/testlog.txt
  echo "===== END FULL MESON TEST LOG (SRC_DIR) =====\n"
fi

