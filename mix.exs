defmodule AshJido.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/agentjido/ash_jido"
  @description "[EXPERIMENTAL] Integration between the Ash framework and the Jido agent ecosystem. APIs may change without notice."

  def project do
    [
      app: :ash_jido,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ash, "~> 3.5"},
      {:jido, "~> 1.1"},
      {:usage_rules, "~> 0.1", only: [:dev]},
      {:igniter, "~> 0.6", only: [:dev, :test]}
    ]
  end
end
