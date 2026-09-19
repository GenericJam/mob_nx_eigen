defmodule MobNxEigen do
  @moduledoc """
  Eigen-backed CPU Nx backend, packaged as a mob plugin.

  This is the **always-available baseline** for on-device numerics: Eigen is a
  header-only C++ template library (vectorised via NEON on ARM), so it needs no
  GPU and runs anywhere mob runs — iOS and Android, any chip. GPU-accelerated
  backends (Vulkan, MLX, TFLite) layer on top where a device supports them;
  NxEigen is the fallback that always works.

  The NIF is cross-compiled to `libnx_eigen_nif.a` and static-linked into the
  app via the `:cpp_archive` plugin contribution (see `priv/mob_plugin.exs` and
  `MobDev.Plugin.CppArchive`). The plugin's `lifecycle.on_start` calls
  `configure/0` once the app and its deps have started.
  """

  require Logger

  @doc """
  Make NxEigen the global Nx backend. Returns the chosen backend module.

  Falls back to `Nx.BinaryBackend` (pure Elixir) if the NxEigen NIF didn't
  load — so an app on a build that hasn't cross-compiled the NIF yet still
  runs, just slower.
  """
  @spec configure() :: module()
  def configure do
    # `ensure_all_started(:nx_eigen)` always succeeds — the app has no
    # `mod:` entry, so starting it is a no-op that never touches the NIF.
    # Kept for symmetry with a hypothetical future application module, but
    # it can NOT observe NIF-load failure. That's why we probe directly.
    # See MOB-82.
    _ = Application.ensure_all_started(:nx_eigen)

    if nif_loaded?() do
      Nx.global_default_backend(NxEigen.Backend)
      Logger.info("Nx backend: NxEigen (Eigen CPU)")
      NxEigen.Backend
    else
      Logger.warning("NxEigen NIF failed to load; using Nx.BinaryBackend")
      Nx.global_default_backend(Nx.BinaryBackend)
      Nx.BinaryBackend
    end
  end

  @doc """
  True when the NxEigen NIF is actually loaded and callable in this
  runtime.

  Probes by constructing a 1-element `{:s, 32}` tensor via
  `NxEigen.NIF.from_binary/3` — the smallest self-contained NIF path
  that doesn't need an existing resource to hand in. If the archive
  isn't linked (host builds without the cross-compiled `.a`, or release
  builds where the plugin was stripped), the probe raises and we return
  `false`. Public so callers can gate optional Eigen-specific fast paths
  without a `try/rescue` boilerplate at each site.

  This exists because `Application.ensure_all_started(:nx_eigen)` can't
  see NIF-load failure — nx_eigen's OTP application has no `mod:` entry,
  so `ensure_all_started` returns `{:ok, _}` regardless. See MOB-82.

  Historical note: the probe originally called `NxEigen.NIF.constant/3`
  with an integer `0` as the value arg. nx_eigen 0.1.1's `constant/3`
  changed its third arg to a NIF-resource scalar tensor state (built via
  `from_binary`); passing an integer now raises `ArgumentError` from
  Fine's decoder, which the old rescue didn't catch. from_binary is the
  base primitive constant/eye/iota all build on top of, so it's the
  right probe.
  """
  @spec nif_loaded?() :: boolean()
  def nif_loaded? do
    _ = NxEigen.NIF.from_binary(<<0, 0, 0, 0>>, {:s, 32}, {1})
    true
  rescue
    # `@on_load` failure discards the module — calls come back as
    # UndefinedFunctionError on this VM. On the older stub-based path
    # the same call raises ErlangError with `original: :nif_not_loaded`.
    # ArgumentError catches Fine's decode/encode failures if the NIF
    # signature drifts out from under this probe again.
    UndefinedFunctionError -> false
    ErlangError -> false
    ArgumentError -> false
  end
end
