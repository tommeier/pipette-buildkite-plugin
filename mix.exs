defmodule Pipette.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/tommeier/pipette"

  def project do
    [
      app: :pipette,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Pipette",
      description: "Declarative Buildkite pipeline generation for Elixir monorepos",
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
      links: %{
        "GitHub" => @source_url,
        "Buildkite Plugin" => "https://github.com/tommeier/pipette-buildkite-plugin"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "LICENSE"
      ]
    ]
  end
end
