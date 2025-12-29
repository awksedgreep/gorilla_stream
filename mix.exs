defmodule GorillaStream.MixProject do
  use Mix.Project

  def project do
    [
      app: :gorilla_stream,
      version: "1.3.6",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  def deps do
    [
      # No zlib dependency needed as it's built into Erlang standard library
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      # Optional zstd compression - provides better compression than zlib
      {:ezstd, "~> 1.2", optional: true}
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  defp aliases do
    [
      "check.format": ["format --check-formatted"],
      ci: ["check.format", "test"]
    ]
  end
end
