defmodule Loggix.Mixfile do
  use Mix.Project

  def project do
    [app: :loggix,
     version: "0.0.1",
     elixir: "~> 1.4",
     dialyzer: [ignore_warnings: ".dialyzerignore"],
     package: package(),
     description: description(),
     deps: deps()]
  end

  defp description do
    "A Logger implimentation for Elixir"
  end

  defp package do
    [
      maintainers: ["kdxu"],
      licenses: ["MIT"]
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp deps do
    [
      {:dialyxir, "~> 0.5", only: [:test], runtime: false},
      {:ex_doc, "~> 0.16.2", only: [:dev], runtime: false}
    ]
  end
end
