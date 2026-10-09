defmodule MobNxEigenSelfTestTest do
  use ExUnit.Case, async: true

  alias Mob.Plugin.SelfTest, as: Contract
  alias MobDev.Plugin.{Manifest, Validator}
  alias MobNxEigen.SelfTest

  @plugin_dir Path.expand("..", __DIR__)

  @good %{
    dot: {NxEigen.Backend, [7.0, 10.0, 15.0, 22.0]},
    fft: Enum.map(1..4, fn _ -> Complex.new(1.0, 0.0) end)
  }

  defp computes(result), do: fn -> result end

  defp refute_called, do: fn -> flunk("computed without a loaded NIF") end

  test "the manifest declares the self-test, and the validator accepts it" do
    {:ok, m} = Manifest.load(@plugin_dir)
    assert m.selftest == MobNxEigen.SelfTest
    assert %{warnings: warnings} = Validator.validate_plugin(m, @plugin_dir)
    refute Enum.any?(warnings, &(&1 =~ "selftest"))
  end

  test "a loaded NIF whose dot and fft come back right passes" do
    for platform <- [:ios, :android] do
      assert SelfTest.check(true, platform, "aarch64-unknown-linux-android", computes(@good)) ==
               :pass
    end
  end

  test "x86 Android without the NIF is a skip naming the abi" do
    for arch <- ["x86_64-pc-linux-android", "i686-pc-linux-android"] do
      result = SelfTest.check(false, :android, arch, refute_called())
      assert {:skip, "nif not built for this abi (" <> rest} = result
      assert rest =~ arch
      assert Contract.result?(result)
    end
  end

  test "arm Android or iOS without the NIF fails: the backend silently fell back" do
    for {platform, arch} <- [
          {:android, "aarch64-unknown-linux-android"},
          {:android, "arm-unknown-linux-androideabi"},
          {:ios, "aarch64-apple-ios-simulator"},
          {:ios, "x86_64-apple-ios-simulator"}
        ] do
      result = SelfTest.check(false, platform, arch, refute_called())
      assert {:fail, reason} = result
      assert reason =~ "not loaded on #{arch}"
      assert Contract.result?(result)
    end
  end

  test "a wrong product, a tensor that left the backend, or a wrong fft fails" do
    for {computed, expected} <- [
          {%{@good | dot: {NxEigen.Backend, [1.0, 2.0, 3.0, 4.0]}}, "expected [7, 10, 15, 22]"},
          {%{@good | dot: {Nx.BinaryBackend, [7.0, 10.0, 15.0, 22.0]}},
           "Nx.BinaryBackend tensor"},
          {%{@good | fft: [Complex.new(4.0, 0.0), 0, 0, 0]}, "expected all 1"},
          {%{@good | fft: [Complex.new(1.0, 1.0), 1, 1, 1]}, "expected all 1"},
          {%{@good | fft: [1, 1, 1]}, "expected all 1"}
        ] do
      result = SelfTest.check(true, :android, "aarch64", computes(computed))
      assert {:fail, reason} = result
      assert reason =~ expected
      assert Contract.result?(result)
    end
  end

  test "run/1 on this host answers from the real NIF probe instead of raising" do
    # The host test BEAM normally has no archive (see MobNxEigenConfigureTest);
    # if it ever does, the real computation must pass.
    result = SelfTest.run(%{platform: :ios, device: :simulator})

    if MobNxEigen.nif_loaded?() do
      assert result == :pass
    else
      assert {:fail, "the nx_eigen NIF is not loaded on " <> _} = result
    end
  end
end
