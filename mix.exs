defmodule Protohacker.MixProject do
  use Mix.Project

  def project do
    [
      app: :protohacker,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      config_path: "config/config.exs",
      aliases: aliases(),
      dialyzer: [
        ignore_warnings: "dialyzer.ignore-warnings.exs",
        plt_add_apps: [:mix]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Protohacker.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:jason, "~> 1.4"},
      {:phoenix, "~> 1.8.0"},
      {:nimble_parsec, "~> 1.4"},

      # Dev and test dependencies
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  defp aliases do
    [
      setup: ["deps.get"],
      test: ["test"],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format --check-formatted",
        "test --exclude flaky",
        "dialyzer.check",
        "credo --strict"
      ],
      "dialyzer.check": ["dialyzer --format dialyxir"],
      "dialyzer.setup": ["dialyzer --plt"],
      "credo.check": ["credo --strict"],
      "code.quality": ["format", "dialyzer.check", "credo --strict"]
    ]
  end

  defp releases do
    [
      protohacker: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end
end
