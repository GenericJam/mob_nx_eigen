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
      assert nif.module == :nx_eigen_nif
      assert nif.lang == :cpp_archive
      assert nif.nm_symbol == "nx_eigen_nif_init"
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
end
