using BinaryBuilder, Pkg
using Base.BinaryPlatforms
const YGGDRASIL_DIR = "../.."
include(joinpath(YGGDRASIL_DIR, "platforms", "mpi.jl"))

name = "PnetCDF"
version = v"0.1.6"

sources = [
  GitSource("https://github.com/Parallel-NetCDF/PnetCDF.git", "c7e22c81ac4c2922f84281a4a19f7000079e6c3f")
]

script = raw"""
cd $WORKSPACE/srcdir/PnetCDF

autoreconf -i

# Set default preprocessor and linker flags
export CPPFLAGS="-I${includedir}"
export LDFLAGS="-L${libdir}"
export CC="mpicc"
export CXX="mpic++"
FLAGS="-lmpi"

./configure \
  --prefix=$prefix \
  --build=${MACHTYPE} \
  --host=${target} \
  --enable-shared=yes \
  --enable-static=no \
  --disable-fortran \
  --with-mpi=${prefix}/bin
  # --disable-cxx \
make -j${nproc} "${FLAGS[@]}"
make install
"""

augment_platform_block = """
  using Base.BinaryPlatforms
  $(MPI.augment)
  augment_platform!(platform::Platform) = augment_mpi!(platform)
"""

platforms = [
  Platform("x86_64", "linux"; libc = "glibc") # all compile but mpitrampoline of course
  Platform("aarch64", "linux"; libc = "glibc")
  Platform("x86_64", "macos")
  Platform("aarch64", "macos")
]
platforms = expand_cxxstring_abis(platforms)

platforms, platform_dependencies = MPI.augment_platforms(platforms; MPItrampoline_compat="5.3.0")
platforms = filter(p -> !(p["mpi"] == "openmpi" && arch(p) == "armv6l" && libc(p) == "glibc"), platforms)

# can't seem to get this to work with mpitrampoline
platforms = filter(p -> !(p["mpi"] == "mpitrampoline"), platforms)

products = [
  ExecutableProduct("cdfdiff", :cdfdiff_exe)
  ExecutableProduct("ncmpidiff", :ncmpidiff_exe)
  ExecutableProduct("ncmpidump", :ncmpidump_exe)
  ExecutableProduct("ncmpigen", :ncmpigen_exe)
  ExecutableProduct("ncoffsets", :ncoffsets_exe)
  ExecutableProduct("ncvalidator", :ncvalidator_exe)
  ExecutableProduct("pnetcdf-config", :pnetcdf_config_exe)
  ExecutableProduct("pnetcdf_version", :pnetcdf_version_exe)
  LibraryProduct("libpnetcdf", :libpnetcdf)
]

dependencies = [
  Dependency(PackageSpec(name="CompilerSupportLibraries_jll", uuid="e66e0078-7015-5450-92f7-15fbd957f2ae"))
  Dependency(PackageSpec(name="Zlib_jll", uuid="83775a58-1f1d-513f-b197-d71354ab007a"))
]
append!(dependencies, platform_dependencies)

build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies; 
               augment_platform_block, julia_compat="1.6", preferred_gcc_version=v"7")
