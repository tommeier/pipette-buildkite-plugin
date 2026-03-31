defmodule Pipette.MixProject do
  use Mix.Project

  @version "0.4.1"
  @source_url "https://github.com/tommeier/pipette-buildkite-plugin"

  def project do
    [
      app: :buildkite_pipette,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Pipette",
      description: "Declarative Buildkite pipeline generation for monorepos, written in Elixir",
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:spark, "~> 2.6"},
      {:ymlr, "~> 5.0"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      files: ~w(lib mix.exs README.md LICENSE .formatter.exs),
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "guides/getting-started.md",
        "guides/production-example.md",
        "guides/activation.md",
        "guides/targeting.md",
        "guides/dynamic-groups.md",
        "guides/testing.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        "Pipeline Definition": [
          Pipette.DSL,
          Pipette.Info,
          Pipette.Branch,
          Pipette.Scope,
          Pipette.Group,
          Pipette.Step,
          Pipette.Trigger
        ],
        "DSL Internals": [
          Pipette.Dsl.Extension,
          Pipette.Dsl.Transformers.GenerateKeys,
          Pipette.Dsl.Verifiers.ValidateRefs,
          Pipette.Dsl.Verifiers.ValidateAcyclic,
          Pipette.Dsl.Verifiers.ValidateSteps
        ],
        Engine: [
          Pipette.Activation,
          Pipette.Git,
          Pipette.Graph,
          Pipette.Target,
          Pipette.Context
        ],
        Output: [
          Pipette.Buildkite
        ]
      ]
    ]
  end
end
