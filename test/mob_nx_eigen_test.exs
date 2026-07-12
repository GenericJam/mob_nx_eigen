defmodule MobNxEigenTest do
  use ExUnit.Case, async: true

  @manifest_path Path.join([__DIR__, "..", "priv", "mob_plugin.exs"])

  defp manifest do
    {m, _binding} = Code.eval_file(@manifest_path)
    m
  end

  describe "plugin manifest" do
    test "declares the cpp_archive NIF with the nx_eigen_nif_init symbol" do
      [nif] = manifest().nifs
      # module :nx_eigen (not :nx_eigen_nif) so the driver-tab key + derived
      # init symbol (<module>_nif_init) match NxEigen's load_nif + the archive.
      assert nif.module == :nx_eigen
      assert nif.lang == :cpp_archive
      assert nif.nm_symbol == "nx_eigen_nif_init"
      assert nif.nm_symbol == "#{nif.module}_nif_init"
    end

    test "references NxEigen's NIF from the dep and ships the FFT bridge itself" do
      [nif] = manifest().nifs
      assert {:dep, :nx_eigen, "c_src/nx_eigen_nif.cpp"} in nif.sources
      assert "c_src/nx_eigen_fft_eigen.cpp" in nif.sources
    end

    test "includes the Eigen + Fine headers via dep tokens" do
      [nif] = manifest().nifs
      assert {:dep, :nx_eigen, "eigen-3.4.0"} in nif.includes
      assert {:dep, :fine, "c_include"} in nif.includes
    end

    test "forces the LIBNAME so FINE_INIT emits nx_eigen_nif_init" do
      [nif] = manifest().nifs
      assert "-DSTATIC_ERLANG_NIF_LIBNAME=nx_eigen" in nif.cxxflags
    end

    test "does not carry -fPIC or the armv7 ABI flags (the builder owns those)" do
      [nif] = manifest().nifs
      all = nif.cxxflags ++ nif.cxxflags_android ++ nif.cxxflags_ios
      refute "-fPIC" in all
      refute "-march=armv7-a" in all
    end

    test "wires the Nx-backend configure into lifecycle.on_start" do
      assert manifest().lifecycle.on_start == {MobNxEigen, :configure, []}
    end
  end

  test "the vendored FFT bridge source exists" do
    assert File.exists?(Path.join([__DIR__, "..", "c_src", "nx_eigen_fft_eigen.cpp"]))
  end

  # The tests above only eval our own manifest data — they pass against ANY
  # mob_dev, even one that has no cpp_archive build path. These pin the thing
  # MOB-42 exposed: the *resolved* mob_dev must actually ship the mechanism the
  # manifest declares AND accept this manifest. cpp_archive landed in mob_dev
  # 0.6.10, so this fails on the pre-0.6.10 dep the plugin used to lock.
  describe "resolved mob_dev provides the cpp_archive build path (MOB-42)" do
    @plugin_dir Path.expand(Path.join(__DIR__, ".."))

    test "the pinned mob_dev ships MobDev.Plugin.CppArchive" do
      assert Code.ensure_loaded?(MobDev.Plugin.CppArchive),
             "the resolved mob_dev has no CppArchive — the mob_dev floor is too low (needs >= 0.6.10)"
    end

    test "the pinned mob_dev's validator accepts our cpp_archive NIF" do
      # Runs the current mob_dev's cpp_archive checks (module/sources/nm_symbol,
      # nm_symbol == <module>_nif_init) against our actual manifest.
      assert {:ok, _} = MobDev.Plugin.Manifest.validate(manifest())
    end

    test "mob_dev's static_archives gatherer resolves our manifest into a build spec" do
      [spec] = MobDev.Plugin.Merge.static_archives([{@plugin_dir, manifest()}])
      assert spec.module == :nx_eigen
      assert spec.nm_symbol == "nx_eigen_nif_init"
      assert spec.plugin == :mob_nx_eigen
      # a plugin-relative source is resolved to absolute; a {:dep, …} token passes through
      assert Path.join(@plugin_dir, "c_src/nx_eigen_fft_eigen.cpp") in spec.sources
      assert {:dep, :nx_eigen, "c_src/nx_eigen_nif.cpp"} in spec.sources
    end
  end
end
