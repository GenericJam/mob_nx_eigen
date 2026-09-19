# Changelog

All notable changes to **mob_nx_eigen** are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0] - 2026-09-19

First Hex release. Eigen-backed CPU [Nx](https://github.com/elixir-nx/nx)
backend, packaged as a mob plugin. The always-available baseline for
on-device numerics — Eigen is a header-only C++ template library
(NEON-vectorised on ARM), so it needs no GPU and runs anywhere mob runs.

### Added

- `MobNxEigen` module — `configure/0` picks NxEigen as the global Nx
  backend at app boot, `nif_loaded?/0` probes for the linked archive.
  Wired into the plugin manifest's `lifecycle.on_start`, so an activated
  plugin just works after `mix mob.deploy --native`.
- Cross-compiled C++ NIF via `MobDev.Plugin.CppArchive` (mob_dev 0.6.10+):
  the plugin's `:cpp_archive` contribution builds `libnx_eigen.a` per
  target ABI and static-links it into the app's single signed binary.
  Android's `RTLD_LOCAL` hides the BEAM's `enif_*` symbols from a
  separately-loaded `.so` and iOS forbids `dlopen`, so static-linked is
  the only shape that works on both platforms.
- Eigen-FFT bridge (`c_src/nx_eigen_fft_eigen.cpp`) — implements the
  upstream nx_eigen FFT contract on top of Eigen's kissfft (header-only,
  embedded in the Eigen tarball). Gives `Nx.fft` / `Nx.ifft` on-device
  without a separate FFTW cross-compile.
- Eigen headers provisioned by the `eigen_headers` Mix compiler (the
  upstream `nx_eigen` Hex package doesn't ship them — MOB-90). Runs
  after Elixir's built-in compilers so the plugin's own tree carries
  what the consuming app's native build needs.
- Fallback to `Nx.BinaryBackend` (pure Elixir) if the archive isn't
  linked (host tests, or a release build where the plugin was stripped).
  MOB-82 story: `Application.ensure_all_started(:nx_eigen)` can't see
  NIF-load failure — nx_eigen's OTP application has no `mod:` entry, so
  `ensure_all_started` returns `{:ok, _}` regardless — so we probe the
  NIF directly instead.
- 16 host tests covering configure/probe/fallback, the Eigen-headers
  compiler, and the plugin manifest.

### Notes

- NIF module name **must** be `:nx_eigen` (not `:nx_eigen_nif`): the
  driver_tab key + `nx_eigen_nif_init` init symbol derive from the
  module name, and NxEigen's own `load_nif` looks up "libnx_eigen".
- mob floor: `~> 0.7` (needs the `:cpp_archive` plugin contribution
  landed in mob_dev 0.6.10).
- Verified end-to-end on iPhone 17 Pro simulator 2026-09-19: `Nx.add`
  and `Nx.dot` round-trip correctly through `NxEigen.Backend`.

### GPU backends (planned, not in 0.1.0)

- `mob_nx_vulkan` — Vulkan compute backend, cross-platform GPU.
- `mob_nx_mlx` — Apple Silicon MLX backend for iOS.
- `mob_nx_tflite` — Google's on-device inference runtime.

All three layer on top of NxEigen as the always-there baseline.
