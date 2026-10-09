defmodule MobNxEigen.SelfTest do
  @moduledoc """
  The plugin's on-device proof (`Mob.Plugin.SelfTest`), run by
  `mix mob.selftest` and mob_ci for every activated plugin.

  Real Nx work through `NxEigen.Backend`, i.e. through the statically linked
  `nx_eigen` NIF:

    * `Nx.dot/2` of `[[1, 2], [3, 4]]` with itself must give
      `[[7, 10], [15, 22]]`, with the result still on `NxEigen.Backend`
      (the matrix product runs in Eigen, not in `Nx.BinaryBackend`).
    * `Nx.fft/1` of `[1, 2, 3, 4]` must give `[10, -2+2i, -2, -2-2i]`: that
      runs the Eigen/kissfft bridge this plugin ships
      (`c_src/nx_eigen_fft_eigen.cpp`, which upstream nx_eigen does not), and
      an asymmetric input also catches a wrong direction (twiddle sign) or a
      broken re/im interleave.

  When the NIF is not loaded (`MobNxEigen.nif_loaded?/0` is false) it is a
  failure (the plugin is activated and `MobNxEigen.configure/0` silently
  fell back to `Nx.BinaryBackend`), with one exception: on x86 Android,
  mob_dev (0.7.17) cross-compiles the archive but installs the `nx_eigen`
  OTP library the NIF loads from only for `arm64-v8a` / `armeabi-v7a`
  (`MobDev.NativeBuild`, "NxEigen only ships 32/64-bit ARM builds"). When
  the architecture is x86 and `:code.priv_dir(:nx_eigen)` is
  `{:error, :bad_name}`, that is
  `{:skip, "nif not built for this abi (...)"}`. An x86 build that has the
  OTP library and still no NIF fails like any other.
  """
  @behaviour Mob.Plugin.SelfTest

  @impl true
  def run(%{platform: platform}) do
    arch = :erlang.system_info(:system_architecture) |> to_string()
    otp_lib? = is_list(:code.priv_dir(:nx_eigen))
    check(MobNxEigen.nif_loaded?(), platform, arch, otp_lib?, &compute/0)
  end

  @doc false
  # The decision, with the NIF probe, the architecture, whether the nx_eigen
  # OTP library is installed and the computation passed in, so the unit tests
  # can drive every branch on a host without the archive.
  @spec check(boolean(), :ios | :android, String.t(), boolean(), (-> term())) ::
          Mob.Plugin.SelfTest.result()
  def check(true, _platform, _arch, _otp_lib?, compute), do: verify(compute.())

  def check(false, :android, arch, false, _compute) do
    if String.starts_with?(arch, ["x86_64", "i686", "i386"]) do
      {:skip,
       "nif not built for this abi (#{arch}): mob_dev installs the nx_eigen OTP " <>
         "library for arm64-v8a / armeabi-v7a only, so NxEigen.NIF cannot load"}
    else
      not_loaded(arch)
    end
  end

  def check(false, _platform, arch, _otp_lib?, _compute), do: not_loaded(arch)

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

    signal = Nx.tensor([1.0, 2.0, 3.0, 4.0], type: :f32, backend: NxEigen.Backend)

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

      not close?(fft, [{10.0, 0.0}, {-2.0, 2.0}, {-2.0, 0.0}, {-2.0, -2.0}]) ->
        {:fail,
         "Nx.fft/1 of [1, 2, 3, 4] on NxEigen.Backend gave #{inspect(fft)}, " <>
           "expected [10, -2+2i, -2, -2-2i]"}

      true ->
        :pass
    end
  end

  # `want` entries are reals or {re, im}; `got` entries are numbers or
  # %Complex{} as Nx.to_flat_list/1 returns them.
  defp close?(got, want) when length(got) == length(want) do
    got |> Enum.zip(want) |> Enum.all?(fn {g, w} -> near?(parts(g), parts(w)) end)
  end

  defp close?(_got, _want), do: false

  defp parts(%Complex{re: re, im: im}), do: {re, im}
  defp parts({re, im}), do: {re, im}
  defp parts(x) when is_number(x), do: {x, 0.0}
  defp parts(_other), do: :error

  defp near?({gr, gi}, {wr, wi}) when is_number(gr) and is_number(gi),
    do: abs(gr - wr) + abs(gi - wi) < 1.0e-4

  defp near?(_got, _want), do: false
end
