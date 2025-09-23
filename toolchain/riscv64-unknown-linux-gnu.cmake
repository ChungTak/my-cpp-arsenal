include(CMakeForceCompiler)

# usage
# cmake -DCMAKE_TOOLCHAIN_FILE=../toolchain-arm-linux.cmake ../
# The Generic system name is used for embedded targets (targets without OS) in
# CMake
set( CMAKE_SYSTEM_NAME          Linux )
set( CMAKE_SYSTEM_PROCESSOR     riscv64 )

# Set a toolchain path. You only need to set this if the toolchain isn't in
# your system path. Don't forget a trailing path separator!
if(DEFINED ENV{TOOLCHAIN_ROOT_DIR})
    set(TOOLCHAIN_TOPDIR "$ENV{TOOLCHAIN_ROOT_DIR}")
    set( TC_PATH "$ENV{TOOLCHAIN_ROOT_DIR}/bin/" )
else()
    # Use system toolchain
    set(TOOLCHAIN_TOPDIR "")
    set( TC_PATH "" )
endif()

# The toolchain prefix for all toolchain executables
if(DEFINED ENV{TOOLCHAIN_NAME})
    set(CROSS_COMPILE "$ENV{TOOLCHAIN_NAME}")
else()
    # Use default toolchain name
    set( CROSS_COMPILE riscv64-linux-gnu- )
endif()
set( ARCH riscv )

# specify the cross compiler. We force the compiler so that CMake doesn't
# attempt to build a simple test program as this will fail without us using
# the -nostartfiles option on the command line
set(CMAKE_C_COMPILER ${TC_PATH}${CROSS_COMPILE}gcc)
set(CMAKE_CXX_COMPILER ${TC_PATH}${CROSS_COMPILE}g++)

# To build the tests, we need to set where the target environment containing
# the required library is. On Debian-like systems, this is
# /usr/riscv64-linux-gnu.
if(DEFINED ENV{TOOLCHAIN_ROOT_DIR})
    SET(CMAKE_FIND_ROOT_PATH $ENV{TOOLCHAIN_TOPDIR})
else()
    SET(CMAKE_FIND_ROOT_PATH /usr/riscv64-linux-gnu)
endif()
# search for programs in the build host directories
SET(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
# for libraries and headers in the target directories
SET(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
SET(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

# We must set the OBJCOPY setting into cache so that it's available to the
# whole project. Otherwise, this does not get set into the CACHE and therefore
# the build doesn't know what the OBJCOPY filepath is
set( CMAKE_OBJCOPY      ${TC_PATH}${CROSS_COMPILE}objcopy
	    CACHE FILEPATH "The toolchain objcopy command " FORCE )

# Set the CMAKE C flags (which should also be used by the assembler!
set( CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Os -std=gnu11" )
# Use standard RISC-V parameters compatible with standard GCC toolchain
set( CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -march=rv64imafdc" )
set( CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mabi=lp64d" )
set( CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -ffunction-sections" )
set( CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fdata-sections" )
set( CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-pointer-to-int-cast" )
set( CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fsigned-char -Wl,-gc-sections -lstdc++ -lm -lpthread" )

set( CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Os" )
# Use standard RISC-V parameters compatible with standard GCC toolchain
set( CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=rv64imafdc" )
set( CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mabi=lp64d" )
set( CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fsigned-char" )
set( CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -ffunction-sections" )
set( CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fdata-sections" )
set( CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wl,-gc-sections -lm -lpthread" )
set( CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-attributes" )
# Fix for 64-bit pointer to 32-bit int conversion warnings
set( CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fpermissive -Wno-error=format-truncation" )

set( CMAKE_C_FLAGS "${CMAKE_C_FLAGS}" CACHE STRING "" )
set( CMAKE_ASM_FLAGS "${CMAKE_C_FLAGS}" CACHE STRING "" )
