defmodule GorillaStream.MixProject do
  use Mix.Project

  def project do
    [
      app: :gorilla_stream,
      version: "2.0.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_env: fn ->
        erts_include_dir =
          Path.join([
            to_string(:code.root_dir()),
            "erts-#{:erlang.system_info(:version)}",
            "include"
          ])

        %{
          "FINE_INCLUDE_DIR" => Fine.include_dir(),
          "ERTS_INCLUDE_DIR" => erts_include_dir
        }
      end,
      deps: deps(),
      dialyzer: dialyzer(),
      aliases: aliases(),
      description:
        "A high-performance, lossless compression library for time series data implementing Facebook's Gorilla compression algorithm.",
      package: package(),
      source_url: "https://github.com/awksedgreep/gorilla_stream",
      docs: docs()
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
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      # Optional zstd compression - provides better compression than zlib
      {:ezstd, "~> 1.2", optional: true},
      # Optional OpenZL compression - format-aware compression extending zstd
      {:ex_openzl, "~> 0.4", optional: true},
      # NIF build support
      {:fine, "~> 0.1.4"},
      {:elixir_make, "~> 0.9", runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/awksedgreep/gorilla_stream"},
      files: ~w(lib c_src Makefile .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "GorillaStream",
      extras: [
        "docs/user_guide.md",
        "docs/performance_guide.md",
        "docs/troubleshooting.md"
      ]
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
