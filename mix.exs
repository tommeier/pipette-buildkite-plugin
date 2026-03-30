defmodule Pipette.MixProject do
  use Mix.Project

  @version "0.1.1"
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
          Pipette.Pipeline,
          Pipette.Branch,
          Pipette.Scope,
          Pipette.Group,
          Pipette.Step,
          Pipette.Trigger
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
