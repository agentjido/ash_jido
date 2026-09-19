defmodule AshJido.MixProject do
  use Mix.Project

  @version "3.0.0-beta.1"
  @source_url "https://github.com/agentjido/ash_jido"
  @description "Integration between the Ash Framework and the Jido Agent ecosystem."

  def project do
    [
      app: :ash_jido,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      aliases: aliases(),

      # Documentation
      name: "AshJido",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),

      # Test Coverage
      test_coverage: [
        tool: ExCoveralls,
        ignore_modules: [
          AshJido,
          AshJido.Domain.Transformers.CompileActions,
          AshJido.Generator,
          AshJido.Persistence.Transformers.DefineStore,
          AshJido.Resource.Dsl,
          AshJido.Resource.Transformers.CompilePublications,
          AshJido.Resource.Transformers.GenerateJidoActions,
          AshJido.Schema,
          ~r/^Mix\.Tasks\.AshJido\.Install/
        ],
        summary: [threshold: 90],
        export: "cov"
      ],

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix],
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt"
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.github": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Runtime dependencies
      {:ash, "~> 3.31 and >= 3.31.3"},
      {:jido, "~> 3.0.0-beta.1"},
      {:jido_action, "~> 3.0.0-beta.11"},
      {:jido_signal, "~> 3.0.0-beta.4"},
      {:zoi, "~> 0.18"},

      # Dev/Test dependencies
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: :dev, runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false},
      {:igniter, "~> 0.7", only: [:dev, :test]},
      {:picosat_elixir, "~> 0.2", only: [:dev, :test], runtime: false},
      {:usage_rules, "~> 1.2", only: [:dev]}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      install_hooks: ["git_hooks.install"],
      test: "test --exclude flaky",
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --min-priority higher",
        "dialyzer",
        "doctor --raise"
      ]
    ]
  end

  defp package do
    [
      files: ["lib", "guides", "mix.exs", "README.md", "LICENSE", "CHANGELOG.md", "usage-rules.md"],
      maintainers: ["Matt Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "https://hexdocs.pm/ash_jido/changelog.html",
        "Discord" => "https://agentjido.xyz/discord",
        "Documentation" => "https://hexdocs.pm/ash_jido",
        "GitHub" => @source_url,
        "Website" => "https://agentjido.xyz"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        {"README.md", title: "Home"},
        {"guides/getting-started.md", title: "Getting Started"},
        {"guides/flow.md", title: "Jido Flow Composition"},
        {"guides/persistence.md", title: "Ash Persistence Adapter"},
        {"guides/signals.md", title: "Jido Signal Publications"},
        {"guides/v3-migration.md", title: "Migrate to Version 3"},
        {"CHANGELOG.md", title: "Changelog"},
        {"CONTRIBUTING.md", title: "Contributing"},
        {"usage-rules.md", title: "Usage Rules"}
      ],
      groups_for_extras: [
        "Start Here": [
          "README.md",
          "guides/getting-started.md",
          "guides/v3-migration.md"
        ],
        "Jido Integration": [
          "guides/flow.md",
          "guides/persistence.md",
          "guides/signals.md"
        ],
        Project: [
          "CHANGELOG.md",
          "CONTRIBUTING.md",
          "usage-rules.md"
        ]
      ]
    ]
  end
end
