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

  Falls back to `Nx.BinaryBackend` (pure Elixir) if `:nx_eigen` can't start —
  so an app on a build that hasn't cross-compiled the NIF yet still runs, just
  slower.
  """
  @spec configure() :: module()
  def configure do
    case Application.ensure_all_started(:nx_eigen) do
      {:ok, _} ->
        Nx.global_default_backend(NxEigen.Backend)
        Logger.info("Nx backend: NxEigen (Eigen CPU)")
        NxEigen.Backend

      {:error, reason} ->
        Logger.warning("NxEigen failed to start: #{inspect(reason)}; using Nx.BinaryBackend")
        Nx.global_default_backend(Nx.BinaryBackend)
        Nx.BinaryBackend
    end
  end
end
