# x86_64-macos.cmake
# CMake toolchain file for cross-compiling to macOS x86_64 platform

# Set system name and processor
set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# Set a toolchain path. You only need to set this if the toolchain isn't in
# your system path. Don't forget a trailing path separator!
if(DEFINED ENV{TOOLCHAIN_ROOT_DIR})
    set(TOOLCHAIN_TOPDIR "$ENV{TOOLCHAIN_ROOT_DIR}")
    set( TC_PATH "$ENV{TOOLCHAIN_ROOT_DIR}/bin/" )
else()
    # Use system toolchain
    set(TOOLCHAIN_TOPDIR "")
    set( TC_PATH "/usr/bin/" )
endif()

# The toolchain prefix for all toolchain executables
if(DEFINED ENV{TOOLCHAIN_NAME})
    set(CROSS_COMPILE "$ENV{TOOLCHAIN_NAME}")
else()
    # Use default toolchain name
    set( CROSS_COMPILE x86_64-apple-darwin- )
endif()
set( ARCH x86_64 )

# Use system default compilers or specified toolchain
if(DEFINED ENV{TOOLCHAIN_ROOT_DIR})
    set(CMAKE_C_COMPILER ${TC_PATH}${CROSS_COMPILE}gcc)
    set(CMAKE_CXX_COMPILER ${TC_PATH}${CROSS_COMPILE}g++)
else()
    set(CMAKE_C_COMPILER /usr/bin/x86_64-apple-darwin-gcc)
    set(CMAKE_CXX_COMPILER /usr/bin/x86_64-apple-darwin-g++)
endif()

# Set compilation flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Os -std=gnu11")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -ffunction-sections")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fdata-sections")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-pointer-to-int-cast")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fsigned-char -Wl,-gc-sections -lstdc++ -lm -lpthread")

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Os -fsigned-char")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -ffunction-sections")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fdata-sections")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wl,-gc-sections -lm -lpthread")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-attributes")

# Cache flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS}" CACHE STRING "")
set(CMAKE_ASM_FLAGS "${CMAKE_C_FLAGS}" CACHE STRING "")

message(STATUS "Using x86_64-macos toolchain configuration")