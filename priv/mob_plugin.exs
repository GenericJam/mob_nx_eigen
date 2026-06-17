%{
  name: :mob_nx_eigen,
  mob_version: "~> 0.7",
  plugin_spec_version: 1,
  description: "Eigen-backed CPU Nx backend (the always-available on-device ML baseline)",

  # The C++ NIF, cross-compiled to libnx_eigen_nif.a and static-linked into the
  # app (MobDev.Plugin.CppArchive). This is the plugin replacement for the
  # bespoke nxeigen hooks that used to live in mob_dev core.
  #
  # Sources: NxEigen's own NIF lives in the nx_eigen dep (referenced by token,
  # not vendored, so it tracks the pinned dep); the Eigen-FFT bridge is shipped
  # by this plugin (gives Nx.fft/ifft on-device via Eigen's header-only kissfft
  # — no separate FFTW cross-compile).
  #
  # CXXFLAGS mirror MobDev.NxEigenNif exactly, minus the bits the builder owns:
  # -fPIC and the armeabi-v7a ABI flags are supplied by CppArchive per target.
  # Exceptions + RTTI stay on (Fine's FINE_INIT throws); LIBNAME forces the
  # FINE_INIT symbol to nx_eigen_nif_init regardless of the NAME token.
  nifs: [
    %{
      module: :nx_eigen_nif,
      lang: :cpp_archive,
      sources: [
        {:dep, :nx_eigen, "c_src/nx_eigen_nif.cpp"},
        "c_src/nx_eigen_fft_eigen.cpp"
      ],
      includes: [
        {:dep, :nx_eigen, "c_src"},
        {:dep, :nx_eigen, "eigen-3.4.0"},
        {:dep, :fine, "c_include"}
      ],
      cxxflags: [
        "-O3",
        "-std=c++17",
        "-fvisibility=hidden",
        "-ffunction-sections",
        "-fdata-sections",
        "-DSTATIC_ERLANG_NIF_LIBNAME=nx_eigen"
      ],
      cxxflags_android: [
        "-fstrict-flex-arrays=3",
        "-mbranch-protection=standard",
        "-fstack-clash-protection",
        "-D_GNU_SOURCE"
      ],
      cxxflags_ios: [],
      nm_symbol: "nx_eigen_nif_init"
    }
  ],

  # Pick NxEigen as the global Nx backend at app boot. The host's Mob.App
  # on_start invokes each activated plugin's lifecycle.on_start MFA.
  lifecycle: %{
    on_start: {MobNxEigen, :configure, []}
  }
}
