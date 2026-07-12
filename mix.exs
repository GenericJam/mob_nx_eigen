defmodule MobNxEigen.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/GenericJam/mob_nx_eigen"

  def project do
    [
      app: :mob_nx_eigen,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      # Provision Eigen headers for the cpp_archive build (the published nx_eigen
      # package doesn't ship them — MOB-90). Runs AFTER the built-in compilers so
      # Elixir has compiled the compiler task itself first; Eigen is only needed
      # later, at the consuming app's native build, so ordering is fine.
      compilers: Mix.compilers() ++ [:eigen_headers],
      deps: deps(),
      description: description(),
      package: package(),
      source_url: @source_url,
      aliases: aliases()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ex_ast, "~> 0.12", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.7", only: [:dev, :test], runtime: false},
      {:recon, "~> 2.5", only: [:dev, :test]},
      # The Nx backend this plugin bundles for on-device CPU inference.
      {:nx, "~> 0.10"},
      {:nx_eigen, "~> 0.1"},
      # mob (host) — the plugin manifest targets this version. Dev/test only:
      # the host app supplies mob at build time; the plugin doesn't ship it.
      {:mob, "~> 0.7", only: [:dev, :test], runtime: false},
      # cpp_archive plugin build (MobDev.Plugin.CppArchive / lang: :cpp_archive)
      # this plugin relies on landed in mob_dev 0.6.10 — floor it there so it can
      # never resolve to a version without the mechanism (MOB-42).
      {:mob_dev, "~> 0.6.10", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Eigen-backed CPU Nx backend, packaged as a mob plugin. The always-available " <>
      "baseline for on-device ML (no GPU required); cross-compiled to a static " <>
      "lib<>.a and linked into the app via the cpp_archive plugin contribution."
  end

  defp package do
    [
      maintainers: ["Kevin Edey"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib c_src priv mix.exs README.md .formatter.exs)
    ]
  end

  defp aliases do
    [setup: ["deps.get", "cmd git config core.hooksPath .githooks"]]
  end
end
