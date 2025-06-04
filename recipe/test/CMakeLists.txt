cmake_minimum_required(VERSION 3.10)
project(test_egl)

include_directories(/opt/conda/envs/mesa/include)
link_directories(/opt/conda/envs/mesa/lib)

find_package(OpenGL REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(EGL REQUIRED egl)
include_directories(${EGL_INCLUDE_DIRS})

add_executable(test_egl test_egl.cpp)
target_link_libraries(test_egl PRIVATE ${EGL_LIBRARIES} OpenGL::GL)
