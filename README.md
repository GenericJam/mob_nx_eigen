# mob_nx_eigen

Eigen-backed CPU [Nx](https://github.com/elixir-nx/nx) backend, packaged as a
[mob](https://github.com/GenericJam/mob) plugin.

This is the **always-available baseline** for on-device numerics. Eigen is a
header-only C++ template library (NEON-vectorised on ARM), so it needs no GPU
and runs anywhere mob runs — iOS and Android, any chip. GPU-accelerated
backends (Vulkan, MLX, TFLite) layer on top where a device supports them;
NxEigen is the fallback that always works.

## How it's built

The NIF is a C++ `:cpp_archive` plugin contribution: mob_dev's
`MobDev.Plugin.CppArchive` cross-compiles it to `libnx_eigen_nif.a` per target
ABI and static-links it into the app's single signed native binary (required —
Android `RTLD_LOCAL` hides the BEAM's `enif_*` symbols from a separately-loaded
`.so`, and iOS forbids `dlopen`). The plugin references NxEigen's own NIF source
+ Eigen/Fine headers straight from its deps (`{:dep, …}` tokens) rather than
vendoring copies; it ships only the Eigen-FFT bridge (`c_src/`).

## Use

```elixir
# mix.exs
{:mob_nx_eigen, "~> 0.1"}

# mob.exs
config :mob, :plugins, [:mob_nx_eigen]
```

The plugin's `lifecycle.on_start` calls `MobNxEigen.configure/0` at app boot,
which makes `NxEigen.Backend` the global Nx backend (falling back to
`Nx.BinaryBackend` if the NIF can't load).

## Status

Replaces the bespoke `nxeigen` hooks that used to live in mob_dev core
(`mix mob.enable nxeigen`). Device verification on Android/iOS pending.
