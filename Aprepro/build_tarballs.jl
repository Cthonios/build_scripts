# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg

name = "Aprepro"
version = v"6.11.0"

# Collection of sources required to complete build
sources = [
    GitSource("https://github.com/gsjaardema/seacas.git", "cfc1edd1e1602fd1edc8da90053b66e92499c8e9"),
    DirectorySource("bundled")
]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir/seacas

for p in ../patches/*.patch; do
    atomic_patch -p1 "${p}"
done

mkdir build
cd build

cmake \
    -DCMAKE_INSTALL_PREFIX=${prefix} \
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TARGET_TOOLCHAIN} \
    -DCMAKE_BUILD_TYPE=Release \
    \
    -D CMAKE_CXX_FLAGS="-Wall -Wunused -pedantic" \
    -D CMAKE_C_FLAGS="-Wall -Wunused -pedantic -std=c11" \
    -D CMAKE_Fortran_FLAGS="" \
    -D Seacas_ENABLE_STRONG_C_COMPILE_WARNINGS="" \
    -D Seacas_ENABLE_STRONG_CXX_COMPILE_WARNINGS="" \
    -D CMAKE_INSTALL_RPATH:PATH="${libdir}" \
    -D BUILD_SHARED_LIBS:BOOL=YES \
    -D Seacas_ENABLE_TESTS=NO \
    -D Seacas_HIDE_DEPRECATED_CODE:BOOL=NO \
    -D Seacas_ENABLE_Fortran=NO \
    -DSeacas_ENABLE_SEACASAprepro_lib:BOOL=ON \
    -DSeacas_ENABLE_SEACASAprepro:BOOL=ON \
    -D TPL_ENABLE_Netcdf:BOOL=NO \
    -D TPL_ENABLE_MPI:BOOL=NO \
    -D TPL_ENABLE_Pthread:BOOL=NO \
    -D SEACASExodus_ENABLE_THREADSAFE:BOOL=NO \
    \
    ..

make -j${nproc}
make install

# below is an absolute hack to fix a tree hash mismatch on macos
# this is due to a case insensitivity issue. 
#
# The issue is caused by a duplicate folder in destdir/lib/cmake
# called "Seacas" which is a duplibcate of "SEACAS".
#
# The build process has far too many CMake files to track this down.
#
rm -r "${prefix}/lib/cmake/Seacas"

install_license $WORKSPACE/srcdir/seacas/LICENSE
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = [
    Platform("x86_64", "linux"; libc = "glibc"),
    Platform("aarch64", "linux"; libc = "glibc"),
    Platform("x86_64", "macos"),
    Platform("aarch64","macos"),
    Platform("x86_64", "windows"),
    Platform("i686", "windows"),
]

platforms = expand_cxxstring_abis(platforms)

# The products that we will ensure are always built
products = [
    ExecutableProduct("aprepro", :aprepro_exe)
    LibraryProduct("libaprepro_lib", :libaprepro_lib)
]

# Dependencies that must be installed before this package can be built
dependencies = [
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies; julia_compat="1.6", preferred_gcc_version=v"5")
