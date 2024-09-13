defmodule Algolia.Mixfile do
  use Mix.Project

  def project do
    [
      app: :algolia,
      version: "0.10.0",
      description: "Elixir implementation of Algolia Search API",
      elixir: "~> 1.5",
      package: package(),
      deps: deps(),
      docs: [extras: ["README.md"], main: "readme"],
      source_url: "https://github.com/slab/algolia-elixir"
    ]
  end

  def package do
    [
      name: "algolia_ex",
      maintainers: ["Slab"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/slab/algolia-elixir"}
    ]
  end

  def application do
    [extra_applications: [:logger, :telemetry]]
  end

  defp deps do
    [
      {:tesla, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:telemetry, "~> 1.0"},
      {:mint, "~> 1.0", only: :test},
      {:castore, "~> 1.0", only: :test},
      # Docs
      {:ex_doc, "~> 0.19", only: :dev},
      {:inch_ex, ">= 0.0.0", only: :dev}
    ]
  end
end
