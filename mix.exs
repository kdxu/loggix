defmodule Loggix.Mixfile do
  use Mix.Project

  def project() do
    [
      app: :loggix,
      version: "0.0.6",
      elixir: "~> 1.4",
      dialyzer: [ignore_warnings: ".dialyzerignore"],
      package: package(),
      description: description(),
      deps: deps(),
    ]
  end

  defp description() do
    "A Logger backend implimentation for Elixir"
  end

  defp package() do
    [
      maintainers: ["kdxu"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/kdxu/loggix"},
    ]
  end

  def application() do
    [applications: []]
  end

  defp deps() do
    [
      {:poison, "~> 3.1", only: [:test]},
      {:dialyxir, "~> 0.5", only: [:test], runtime: false},
      {:ex_doc, "~> 0.16.2", only: [:dev], runtime: false},
    ]
  end
end
