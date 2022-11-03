defmodule ActivatorHTTP.MixProject do
  use Mix.Project

  Code.require_file("internal_versions.exs", "../../priv/")

  @app :activator_http
  @version InternalVersions.get(@app)

  def project do
    [
      app: @app,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: InternalVersions.elixir_version(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ActivatorHTTP.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:activator, path: "../activator"},
      {:spawn, path: "../../"},
      {:bakeware, "~> 0.2"},
      {:bandit, "~> 0.5"}
    ]
  end

  defp releases do
    [
      activator_http: [
        include_executables_for: [:unix],
        applications: [activator_http: :permanent],
        steps: [
          :assemble,
          &Bakeware.assemble/1
        ],
        bakeware: [compression_level: 19]
      ]
    ]
  end
end
