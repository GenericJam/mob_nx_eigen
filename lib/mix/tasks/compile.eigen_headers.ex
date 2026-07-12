defmodule Mix.Tasks.Compile.EigenHeaders do
  @moduledoc false
  # Provisions the Eigen headers the cpp_archive build needs.
  #
  # The plugin manifest compiles NxEigen's NIF + our FFT bridge into a static
  # archive via mob_dev's CppArchive, which needs Eigen's headers at build time.
  # The published `nx_eigen` hex package does NOT ship them (it downloads Eigen
  # in its own Makefile and ships a precompiled .so, so that download is normally
  # skipped) — so on a clean `mix deps.get` the manifest's `eigen-3.4.0` include
  # is empty and the cross-compile fails to find `<Eigen/…>` (MOB-90).
  #
  # This compiler runs when the plugin is compiled (in the consuming app's deps)
  # and drops Eigen into the plugin's own `eigen-3.4.0/` (gitignored, so the
  # manifest's plugin-relative `"eigen-3.4.0"` include resolves). Idempotent, and
  # `EIGEN_DIR` short-circuits the download to a local checkout.
  use Mix.Task.Compiler

  @eigen_version "3.4.0"
  @eigen_url "https://gitlab.com/libeigen/eigen/-/archive/#{@eigen_version}/eigen-#{@eigen_version}.tar.gz"

  @impl true
  def run(_argv) do
    dest = Path.join(File.cwd!(), "eigen-#{@eigen_version}")

    cond do
      # Already provisioned (or a prior download) — nothing to do.
      File.dir?(Path.join(dest, "Eigen")) ->
        {:noop, []}

      # Escape hatch: reuse a local Eigen instead of hitting the network.
      local = local_eigen(System.get_env("EIGEN_DIR")) ->
        _ = File.rm_rf(dest)
        File.ln_s!(local, dest)
        {:ok, []}

      true ->
        provision!(dest)
        {:ok, []}
    end
  end

  defp local_eigen(nil), do: nil

  defp local_eigen(dir) do
    expanded = Path.expand(dir)
    if File.dir?(Path.join(expanded, "Eigen")), do: expanded
  end

  defp provision!(dest) do
    Mix.shell().info("[mob_nx_eigen] fetching Eigen #{@eigen_version} for the cpp_archive build…")

    {out, status} =
      System.cmd(
        "sh",
        ["-c", "curl -fsSL '#{@eigen_url}' | tar xz -C '#{Path.dirname(dest)}'"],
        stderr_to_stdout: true
      )

    if status != 0 or not File.dir?(Path.join(dest, "Eigen")) do
      Mix.raise("""
      [mob_nx_eigen] could not provision Eigen #{@eigen_version} for the cpp_archive build.
      #{out}
      Point EIGEN_DIR at a local Eigen #{@eigen_version} checkout (a dir containing `Eigen/`) and rebuild.
      """)
    end
  end
end
