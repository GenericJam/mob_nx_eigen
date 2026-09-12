# MOB-82: `configure/0` used to trust `ensure_all_started(:nx_eigen)` to
# detect NIF-load failure, but nx_eigen's OTP application has no `mod:`
# entry — so `ensure_all_started` returns `{:ok, _}` whether or not the
# NIF loaded, and the "falls back to `Nx.BinaryBackend`" clause the
# moduledoc/README promised was unreachable. On a build where the archive
# isn't linked, `configure/0` set NxEigen.Backend as the global default
# and the first tensor op then crashed instead of degrading.
#
# The suite runs `async: false` because `Nx.global_default_backend/1`
# mutates a persistent term shared across the VM.
defmodule MobNxEigenConfigureTest do
  use ExUnit.Case, async: false

  setup do
    original = Nx.default_backend()

    on_exit(fn ->
      Nx.global_default_backend(original)
    end)

    # Probe the NIF DIRECTLY (not via `MobNxEigen.nif_loaded?/0`) so the
    # test's expected outcome is anchored to ground truth. If the
    # `configure/0` fix were reverted so `nif_loaded?/0` was hardwired to
    # `true` (or removed and the code just set NxEigen.Backend
    # unconditionally), this direct probe still reports `:not_loaded` on a
    # host without the archive, and the test would catch the regression.
    probe_state =
      try do
        _ = NxEigen.NIF.constant({:s, 32}, {1}, 0)
        :loaded
      rescue
        _ -> :not_loaded
      catch
        _, _ -> :not_loaded
      end

    {:ok, %{probe: probe_state}}
  end

  test "MOB-82: configure/0 falls back to BinaryBackend when the NIF isn't loaded",
       %{probe: probe} do
    chosen = MobNxEigen.configure()

    case probe do
      :not_loaded ->
        assert chosen == Nx.BinaryBackend,
               "NIF didn't load (probe: :not_loaded) — configure/0 must degrade to " <>
                 "Nx.BinaryBackend, not silently set NxEigen.Backend and let the " <>
                 "first tensor op crash. Got #{inspect(chosen)}."

        assert Nx.default_backend() == {Nx.BinaryBackend, []}

      :loaded ->
        assert chosen == NxEigen.Backend
        assert Nx.default_backend() == {NxEigen.Backend, []}
    end
  end

  test "nif_loaded?/0 returns a boolean without raising" do
    # The probe MUST catch its own failure modes — a raise here would
    # take out the calling `configure/0` and leave the app with no
    # default backend set at all.
    result = MobNxEigen.nif_loaded?()
    assert is_boolean(result)
  end

  test "MOB-82: nif_loaded?/0 agrees with a direct NIF probe" do
    # Ties `nif_loaded?/0` to ground truth so a revert that replaces the
    # body with `true` (or `false`) is caught here even before we exercise
    # configure/0. If the module's own probe disagrees with an independent
    # probe of the same NIF call, the module's probe is lying.
    ground_truth =
      try do
        _ = NxEigen.NIF.constant({:s, 32}, {1}, 0)
        true
      rescue
        _ -> false
      catch
        _, _ -> false
      end

    assert MobNxEigen.nif_loaded?() == ground_truth
  end
end
