montre_root = get(ENV, "MONTRE_ROOT", nothing)

if montre_root === nothing
	error(
		"MONTRE_ROOT environment variable not set.\n" *
		"Set it to the root of the montre Rust workspace, e.g.:\n" *
		"  ENV[\"MONTRE_ROOT\"] = expanduser(\"~/code/montre\")\n" *
		"  using Pkg; Pkg.build(\"Montre\")"
	)
end

montre_root = expanduser(montre_root)

if !isfile(joinpath(montre_root, "Cargo.toml"))
	error("MONTRE_ROOT=$montre_root does not contain a Cargo.toml")
end

@info "Building montre-ffi..." montre_root
run(Cmd(`cargo build --release -p montre-ffi`; dir = montre_root))

if Sys.isapple()
	libname = "libmontre_ffi.dylib"
elseif Sys.iswindows()
	libname = "montre_ffi.dll"
else
	libname = "libmontre_ffi.so"
end

libpath = joinpath(montre_root, "target", "release", libname)

if !isfile(libpath)
	error("Build succeeded but library not found at $libpath")
end

deps_dir = joinpath(@__DIR__)
mkpath(deps_dir)
open(joinpath(deps_dir, "deps.jl"), "w") do io
	println(io, "const libmontre = \"$(escape_string(libpath))\"")
end

@info "Montre.jl build complete" libpath
