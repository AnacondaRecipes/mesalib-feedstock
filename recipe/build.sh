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

# ---
# Meson options/choices and rationale:
# -Dgallium-drivers: Comma-separated list of Gallium drivers to build (e.g. softpipe,llvmpipe,zink)
# -Dglx: Valid values are 'auto', 'disabled', 'dri', 'xlib'. Use 'dri' for Linux, 'disabled' for macOS.
# -Degl: Enable or disable EGL support. Disabled on macOS, enabled on Linux.
# -Dplatforms: Comma-separated list of platforms (e.g. x11,macos,wayland,drm). Use 'x11' for Linux, 'macos' for macOS.
# -Dvulkan-drivers: Comma-separated list of Vulkan drivers (e.g. swrast,virtio,all). Use 'swrast' for Linux and macOS.
# -Dlibunwind: Enable or disable libunwind support. Enabled on Linux, disabled on macOS.
# -Dshared-glapi: Enable shared GL API. Enabled for both Linux and macOS.
#
# See https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/meson.options
# ---

# Set platforms option based on target platform
if [[ "$target_platform" == osx* ]]; then
  MESA_OPTS="
    ${MESA_OPTS}
    -Dplatforms=macos
    -Dgbm=disabled
    -Dglx=disabled
    -Degl=disabled
    -Dglvnd=disabled
  "
else
  MESA_OPTS="
    ${MESA_OPTS}
    -Dplatforms=x11
    -Dlegacy-x11=dri2
    -Dgbm=enabled
    -Dglx=dri
    -Degl=enabled
    -Dglvnd=enabled
  "

  # GLVND needs the path to the vendor's OpenGL implementation via config file.
  mkdir -p "${PREFIX}/etc/conda/activate.d"
  cp ${RECIPE_DIR}/activate.sh ${PREFIX}/etc/conda/activate.d/

  mkdir -p "${PREFIX}/etc/conda/deactivate.d"
  cp ${RECIPE_DIR}/deactivate.sh ${PREFIX}/etc/conda/deactivate.d/

  # Silences a warning from libGL when it runs.
  mkdir -p "${PREFIX}/etc/drirc"
  touch "${PREFIX}/etc/drirc/.keep"
fi

# The --prefix=$PREFIX flag ensures proper installation location for conda-build
# We might want to have a static link of llvm (-Dshared-llvm=false). Similar to https://github.com/AnacondaRecipes/llvmlite-feedstock/pull/15
meson setup builddir/ \
  ${MESON_ARGS} \
  --buildtype=release \
  --prefix=$PREFIX \
  -Dlibdir=lib \
  $MESA_OPTS \
  -Dvulkan-drivers=swrast \
  -Dgallium-drivers=softpipe,llvmpipe \
  -Dgallium-va=disabled \
  -Dgallium-vdpau=disabled \
  -Dgles1=disabled \
  -Dgles2=disabled \
  -Degl-native-platform=surfaceless \
  -Dllvm=enabled \
  -Dshared-llvm=enabled \
  -Dopengl=true \
  -Dbuild-tests=true \
  -Dlibunwind=enabled \
  -Dshared-glapi=enabled \
  -Dxmlconfig=enabled \
  -Dglvnd-vendor-name=${glvnd_vendor_name} \
  || { cat builddir/meson-logs/meson-log.txt; exit 1; }

ninja -C builddir/ -j ${CPU_COUNT}

ninja -C builddir/ install

# Only need this on Linux since OSX doesn't make EGL or GLX.
if [[ "$target_platform" == linux* ]]; then
  # To make sure our EGL mesa libs don't get picked up on accident we use an alternate GLVND name and ICD with
  # a higher priority default file in the same location. Just renaming the GLX ones is enough.
  cp ${PREFIX}/share/glvnd/egl_vendor.d/50_${glvnd_vendor_name}.json ${PREFIX}/share/glvnd/egl_vendor.d/99_${glvnd_vendor_name}.json
  mv ${PREFIX}/share/glvnd/egl_vendor.d/50_${glvnd_vendor_name}.json ${PREFIX}/share/glvnd/egl_vendor.d/50_mesa.json
  sed -i "s:libEGL_${glvnd_vendor_name}.so:libEGL_mesa.so:g" ${PREFIX}/share/glvnd/egl_vendor.d/50_mesa.json
fi

echo "Running Mesa tests..."
meson test -C builddir/ -t 4 -v
