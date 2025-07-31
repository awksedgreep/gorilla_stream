defmodule Mix.Tasks.GorillaStream.CompressionAnalysis do
  @moduledoc """
  Runs compression analysis to determine when to use zlib with Gorilla compression.

  ## Examples

      mix gorilla_stream.compression_analysis

  This task analyzes different data patterns and sizes to provide recommendations
  on when combining Gorilla compression with zlib is beneficial for your use case.
  """

  use Mix.Task

  @shortdoc "Analyzes when to use zlib with Gorilla compression"

  def run(_args) do
    # Start the application to ensure all dependencies are loaded
    Mix.Task.run("app.start")

    # Run the analysis script
    GorillaStream.Scripts.CompressionAnalysis.run()
  end
end
