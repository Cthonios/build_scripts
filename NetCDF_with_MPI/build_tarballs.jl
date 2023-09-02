# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg
using Base.BinaryPlatforms
const YGGDRASIL_DIR = "../.."
include(joinpath(YGGDRASIL_DIR, "platforms", "mpi.jl"))

# The version of this JLL is decoupled from the upstream version.
# Whenever we package a new upstream release, we initially map its
# version X.Y.Z to X00.Y00.Z00 (i.e., multiply each component by 100).
# So for example version 2.6.3 would become 200.600.300.

name = "NetCDF_with_MPI"
upstream_version = v"4.9.2"

# Offset to add to the version number.  Remember to always bump this.
version_offset = v"0.2.9"

version = VersionNumber(upstream_version.major * 100 + version_offset.major,
                        upstream_version.minor * 100 + version_offset.minor,
                        upstream_version.patch * 100 + version_offset.patch)

# Collection of sources required to build NetCDF
sources = [
    ArchiveSource("https://downloads.unidata.ucar.edu/netcdf-c/$(upstream_version)/netcdf-c-$(upstream_version).tar.gz",
                  "cf11babbbdb9963f09f55079e0b019f6d0371f52f8e1264a5ba8e9fdab1a6c48"),
    DirectorySource("bundled"),
]

# HDF5.h in /workspace/artifacts/805ccba77cd286c1afc127d1e45aae324b507973/include
# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir/netcdf-c*

export CPPFLAGS="-I${includedir}"
export LDFLAGS="-L${libdir}"
export LDFLAGS_MAKE="${LDFLAGS}"
CONFIGURE_OPTIONS=""

# Apply patch https://github.com/Unidata/netcdf-c/pull/2690
atomic_patch -p1 ../patches/0001-curl-cainfo.patch

if [[ ${target} -ne x86_64-linux-gnu ]]; then
    # utilities are necessary to run the tests
    CONFIGURE_OPTIONS="$CONFIGURE_OPTIONS --disable-utilities"
fi

#if grep -q MPICH_NAME $prefix/include/mpi.h; then
#  LDFLAGS_MAKE+=" -lmpi -lpthread"
#elif grep -q MPItrampoline $prefix/include/mpi.h; then
#  LDFLAGS_MAKE+=" -lmpitrampoline -lpthread"
#elif grep -q OMPI_MAJOR_VERSION $prefix/include/mpi.h; then
#  LDFLAGS_MAKE+=" -lmpi -lpthread"
#fi

LDFLAGS_MAKE+=" -lmpi -lpthread"
export CC="mpicc"
export CXX="mpic++"

# https://github.com/JuliaPackaging/Yggdrasil/issues/5031#issuecomment-1155000045
rm /workspace/destdir/lib/*.la

./configure \
    --prefix=${prefix} \
    --build=${MACHTYPE} \
    --host=${target} \
    --enable-shared \
    --disable-static \
    --disable-dap-remote-tests \
    --disable-testsets \
    --disable-plugins \
    --enable-pnetcdf \
    $CONFIGURE_OPTIONS \
    ${mpiopts}

make LDFLAGS="${LDFLAGS_MAKE}" -j${nproc}

if [[ ${target} == x86_64-linux-gnu ]]; then
   make check
fi

make install

nc-config --all
"""

augment_platform_block = """
    using Base.BinaryPlatforms
    $(MPI.augment)
    augment_platform!(platform::Platform) = augment_mpi!(platform)
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
# platforms = supported_platforms()
platforms = [
  Platform("x86_64", "linux"; libc = "glibc")
  Platform("aarch64", "linux"; libc = "glibc")
  Platform("x86_64", "macos")
  Platform("aarch64", "macos")
]
platforms = filter(p -> !(Sys.iswindows(p) && nbits(p) == 32), platforms)
platforms = expand_cxxstring_abis(platforms)
platforms, platform_dependencies = MPI.augment_platforms(platforms; MPItrampoline_compat="5.3.0")
# Avoid platforms where the MPI implementation isn't supported
# OpenMPI
platforms = filter(p -> !(p["mpi"] == "openmpi" && arch(p) == "armv6l" && libc(p) == "glibc"), platforms)
# MPItrampoline
platforms = filter(p -> !(p["mpi"] == "mpitrampoline" && libc(p) == "musl"), platforms)
platforms = filter(p -> !(p["mpi"] == "mpitrampoline" && Sys.isfreebsd(p)), platforms)

# platforms = reverse(platforms)
platforms = filter(p -> !(p["mpi"] == "mpitrampoline"), platforms) # c compiler can't create executables


# The products that we will ensure are always built
products = [
    LibraryProduct("libnetcdf", :libnetcdf_with_mpi),
]

# Dependencies that must be installed before this package can be built
pnetcdf = PackageSpec(; name="PnetCDF_jll", uuid="42036edf-1cf4-552f-a99e-b7155f12a1cd", url="https://github.com/Cthonios/PnetCDF_jll.jl.git")
Pkg.API.handle_package_input!(pnetcdf)

dependencies = [
    Dependency("Bzip2_jll"),
    Dependency(PackageSpec(name="CompilerSupportLibraries_jll", uuid="e66e0078-7015-5450-92f7-15fbd957f2ae")),
    Dependency("HDF5_jll"; compat = "~1.14"),
    Dependency("LibCURL_jll"; compat = "7.73.0"),
    Dependency(pnetcdf),
    Dependency("XML2_jll"),
    Dependency("Zlib_jll"),
    Dependency("Zstd_jll"),
]
append!(dependencies, platform_dependencies)

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
               augment_platform_block,julia_compat="1.6", preferred_gcc_version=v"5")
