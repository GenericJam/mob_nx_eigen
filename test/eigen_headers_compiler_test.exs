defmodule Mix.Tasks.Compile.EigenHeadersTest do
  # async: false — mutates cwd + EIGEN_DIR.
  use ExUnit.Case, async: false

  @eigen_dir "eigen-3.4.0"

  setup do
    tmp =
      Path.join(System.tmp_dir!(), "eigen_headers_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    prev = System.get_env("EIGEN_DIR")

    on_exit(fn ->
      if prev, do: System.put_env("EIGEN_DIR", prev), else: System.delete_env("EIGEN_DIR")
      File.rm_rf!(tmp)
    end)

    {:ok, tmp: tmp}
  end

  test "EIGEN_DIR short-circuits the download to a local Eigen, idempotently", %{tmp: tmp} do
    # A stand-in local Eigen checkout (a dir with an Eigen/ subdir).
    local = Path.join(tmp, "local_eigen")
    File.mkdir_p!(Path.join(local, "Eigen"))
    System.put_env("EIGEN_DIR", local)

    File.cd!(tmp, fn ->
      # First run wires eigen-3.4.0/ to the local copy (no network).
      assert {:ok, _} = Mix.Tasks.Compile.EigenHeaders.run([])
      assert File.dir?(Path.join([tmp, @eigen_dir, "Eigen"]))

      # Second run is a no-op (already provisioned).
      assert {:noop, _} = Mix.Tasks.Compile.EigenHeaders.run([])
    end)
  end

  test "an already-provisioned eigen dir is left untouched (no EIGEN_DIR, no network)", %{
    tmp: tmp
  } do
    System.delete_env("EIGEN_DIR")
    File.mkdir_p!(Path.join([tmp, @eigen_dir, "Eigen"]))

    File.cd!(tmp, fn ->
      assert {:noop, _} = Mix.Tasks.Compile.EigenHeaders.run([])
    end)
  end
end
