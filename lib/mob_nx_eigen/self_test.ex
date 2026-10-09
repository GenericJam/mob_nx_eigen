defmodule MobNxEigen.SelfTest do
  @moduledoc """
  The plugin's on-device proof (`Mob.Plugin.SelfTest`), run by
  `mix mob.selftest` and mob_ci for every activated plugin.

  Real Nx work through `NxEigen.Backend`, i.e. through the statically linked
  `nx_eigen` NIF:

    * `Nx.dot/2` of `[[1, 2], [3, 4]]` with itself must give
      `[[7, 10], [15, 22]]`, with the result still on `NxEigen.Backend`
      (the matrix product runs in Eigen, not in `Nx.BinaryBackend`).
    * `Nx.fft/1` of `[1, 0, 0, 0]` must give `[1, 1, 1, 1]`: that runs the
      Eigen/kissfft bridge this plugin ships (`c_src/nx_eigen_fft_eigen.cpp`),
      which upstream nx_eigen does not.

  When the NIF is not loaded (`MobNxEigen.nif_loaded?/0` is false) the test
  looks at the architecture the BEAM was built for: mob_dev builds the
  `nx_eigen` archive for the Android arm ABIs (`arm64-v8a`,
  `armeabi-v7a`) only, so on an x86 Android emulator that is
  `{:skip, "nif not built for this abi (...)"}`. Anywhere else (an arm
  Android device, iOS) a missing NIF is a failure: the plugin is activated
  and `MobNxEigen.configure/0` silently fell back to `Nx.BinaryBackend`.
  """
  @behaviour Mob.Plugin.SelfTest

  @impl true
  def run(%{platform: platform}) do
    arch = :erlang.system_info(:system_architecture) |> to_string()
    check(MobNxEigen.nif_loaded?(), platform, arch, &compute/0)
  end

  @doc false
  # The decision, with the NIF probe, the architecture and the computation
  # passed in so the unit tests can drive every branch on a host without the
  # archive.
  @spec check(boolean(), :ios | :android, String.t(), (-> term())) ::
          Mob.Plugin.SelfTest.result()
  def check(false, :android, arch, _compute) do
    if String.starts_with?(arch, ["x86_64", "i686", "i386"]) do
      {:skip,
       "nif not built for this abi (#{arch}): mob_dev builds the nx_eigen archive " <>
         "for arm64-v8a / armeabi-v7a only"}
    else
      not_loaded(arch)
    end
  end

  def check(false, :ios, arch, _compute), do: not_loaded(arch)

  def check(true, _platform, _arch, compute), do: verify(compute.())

  defp not_loaded(arch) do
    {:fail,
     "the nx_eigen NIF is not loaded on #{arch}: NxEigen.NIF.from_binary/3 raised, " <>
       "so MobNxEigen.configure/0 fell back to Nx.BinaryBackend"}
  end

  @doc false
  # Run the two operations on NxEigen.Backend and report what came back.
  @spec compute() :: %{dot: {module(), [number()]}, fft: [Complex.t() | number()]}
  def compute do
    a = Nx.tensor([[1.0, 2.0], [3.0, 4.0]], type: :f32, backend: NxEigen.Backend)
    dot = Nx.dot(a, a)

    signal = Nx.tensor([1.0, 0.0, 0.0, 0.0], type: :f32, backend: NxEigen.Backend)

    %{
      dot: {dot.data.__struct__, Nx.to_flat_list(dot)},
      fft: signal |> Nx.fft() |> Nx.to_flat_list()
    }
  end

  @doc false
  @spec verify(map()) :: Mob.Plugin.SelfTest.result()
  def verify(%{dot: {backend, dot}, fft: fft}) do
    cond do
      backend != NxEigen.Backend ->
        {:fail, "Nx.dot/2 on NxEigen.Backend returned a #{inspect(backend)} tensor"}

      not close?(dot, [7.0, 10.0, 15.0, 22.0]) ->
        {:fail, "Nx.dot/2 on NxEigen.Backend gave #{inspect(dot)}, expected [7, 10, 15, 22]"}

      not close?(fft, [1.0, 1.0, 1.0, 1.0]) ->
        {:fail,
         "Nx.fft/1 of [1, 0, 0, 0] on NxEigen.Backend gave #{inspect(fft)}, expected all 1"}

      true ->
        :pass
    end
  end

  defp close?(got, want) when length(got) == length(want) do
    got |> Enum.zip(want) |> Enum.all?(fn {g, w} -> distance(g, w) < 1.0e-4 end)
  end

  defp close?(_got, _want), do: false

  defp distance(%Complex{re: re, im: im}, w) when is_number(re) and is_number(im),
    do: abs(re - w) + abs(im)

  defp distance(g, w) when is_number(g), do: abs(g - w)
  defp distance(_g, _w), do: :infinity
end
