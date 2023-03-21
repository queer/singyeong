defmodule Singyeong.Mixfile do
  use Mix.Project

  def project do
    [
      app: :singyeong,
      version: "0.0.1",
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env),
      compilers: [:phoenix, :gettext] ++ Mix.compilers,
      start_permanent: Mix.env == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:mnesia]],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
      ],
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Singyeong.Application, []},
      extra_applications: [:logger, :runtime_tools, :mnesia]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.5"},
      {:phoenix_pubsub, "~> 2.0"},
      {:plug_cowboy, "~> 2.1"},
      {:gettext, "~> 0.11"},
      {:jason, "~> 1.1"},
      {:nimble_parsec, "~> 1.2.0"},
      {:fuse, "~> 2.4"},
      {:httpoison, "~> 1.6"},
      {:msgpax, "~> 2.2"},
      {:typed_struct, "~> 0.2.1"},
      {:rafted_value, "~> 0.11.1"},
      {:raft_fleet, "~> 0.10.2"},
      {:elixir_uuid, "~> 1.2"},
      {:manifold, "~> 1.4"},

      {:dialyxir, "~> 1.2.0", only: [:dev], runtime: false},
      {:credo, "~> 1.7.0", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.14.0", only: :test},

      {:singyeong_plugin, "~> 0.1.2"},
      {:lethe, "~> 0.6.0"},
      {:libcluster, "~> 3.3"},
    ]
  end
end
