#!/usr/bin/env elixir

# Gorilla + zlib Compression Decision Tool
# Usage: elixir compression_decision_tool.exs

defmodule CompressionDecisionTool do
  alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}

  def main(_args) do
    IO.puts("🎯 GORILLA + ZLIB COMPRESSION DECISION TOOL")
    IO.puts("=" |> String.duplicate(50))

    # Test with your data patterns
    scenarios = [
      {"Small API Response", 500, :api_response},
      {"Medium Sensor Data", 5000, :sensor_steady},
      {"Large Time Series", 25000, :time_series},
      {"Massive Dataset", 100000, :big_data}
    ]

    Enum.each(scenarios, fn {name, size, pattern} ->
      analyze_scenario(name, size, pattern)
    end)

    print_recommendations()
  end

  defp analyze_scenario(name, size, pattern) do
    IO.puts("\n--- #{name} (#{size} points) ---")

    data = generate_data(size, pattern)
    original_binary = :erlang.term_to_binary(data)
    original_size = byte_size(original_binary)

    # Gorilla compression
    {gorilla_time, {:ok, gorilla_result}} = :timer.tc(fn -> Encoder.encode(data) end)
    gorilla_size = byte_size(gorilla_result)

    # Combined compression
    {zlib_time, combined_result} = :timer.tc(fn -> :zlib.compress(gorilla_result) end)
    combined_size = byte_size(combined_result)

    # Calculate benefits
    gorilla_ratio = gorilla_size / original_size
    combined_ratio = combined_size / original_size
    additional_benefit = (gorilla_size - combined_size) / gorilla_size * 100
    time_overhead = zlib_time / gorilla_time * 100

    IO.puts("Original: #{format_size(original_size)}")
    IO.puts("Gorilla:  #{format_size(gorilla_size)} (#{Float.round(gorilla_ratio, 3)}) - #{div(gorilla_time, 1000)}ms")
    IO.puts("Combined: #{format_size(combined_size)} (#{Float.round(combined_ratio, 3)}) - #{div(gorilla_time + zlib_time, 1000)}ms")
    IO.puts("Extra compression: #{Float.round(additional_benefit, 1)}%")
    IO.puts("Time overhead: #{Float.round(time_overhead, 1)}%")

    # Decision
    decision = make_decision(additional_benefit, time_overhead, original_size)
    IO.puts("💡 #{decision}")
  end

  defp generate_data(count, pattern) do
    base_time = 1_640_995_200

    case pattern do
      :api_response ->
        # API response with mixed metrics
        Enum.map(0..(count-1), fn i ->
          {base_time + i, 50 + :rand.normal() * 10}
        end)

      :sensor_steady ->
        # Steady sensor with small variations
        Enum.map(0..(count-1), fn i ->
          {base_time + i * 60, 23.5 + :rand.normal() * 0.2}
        end)

      :time_series ->
        # Time series with trends and cycles
        Enum.map(0..(count-1), fn i ->
          trend = i * 0.001
          cycle = 10 * :math.sin(i * 0.01)
          noise = :rand.normal() * 2
          {base_time + i * 30, 100 + trend + cycle + noise}
        end)

      :big_data ->
        # Large dataset with various patterns
        Enum.map(0..(count-1), fn i ->
          section = rem(i, 10000)
          cond do
            section < 3000 -> {base_time + i, 25.0 + :rand.normal() * 0.5}
            section < 6000 -> {base_time + i, 25.0 + (section - 3000) * 0.01 + :rand.normal() * 1}
            true -> {base_time + i, 45.0 + :rand.normal() * 8}
          end
        end)
    end
  end

  defp make_decision(additional_benefit, time_overhead, original_size) do
    cond do
      additional_benefit > 15 and original_size > 100_000 ->
        "✅ STRONG YES - Great compression benefit on large dataset"

      additional_benefit > 10 and time_overhead < 50 ->
        "✅ YES - Good benefit with reasonable overhead"

      additional_benefit > 8 and original_size > 50_000 ->
        "✅ YES - Worthwhile for storage/bandwidth savings"

      additional_benefit < 5 ->
        "❌ NO - Minimal benefit (#{Float.round(additional_benefit, 1)}%)"

      time_overhead > 100 ->
        "❌ NO - Too much time overhead (#{Float.round(time_overhead, 0)}%)"

      true ->
        "⚠️  MAYBE - Depends on your priorities (space vs speed)"
    end
  end

  defp print_recommendations do
    IO.puts("\n" <> "=" |> String.duplicate(50))
    IO.puts("📋 QUICK DECISION FRAMEWORK")
    IO.puts("=" |> String.duplicate(50))

    IO.puts("\n🎯 Use Gorilla + zlib IF:")
    IO.puts("   • Dataset > 10KB")
    IO.puts("   • Additional compression > 8%")
    IO.puts("   • Storage/bandwidth costs matter")
    IO.puts("   • Not real-time processing")

    IO.puts("\n⚡ Use Gorilla only IF:")
    IO.puts("   • Real-time processing")
    IO.puts("   • High throughput needed")
    IO.puts("   • Small datasets < 10KB")
    IO.puts("   • Additional benefit < 5%")

    IO.puts("\n💡 Test with YOUR data:")
    IO.puts("   1. Run both approaches on sample data")
    IO.puts("   2. Measure compression ratio and time")
    IO.puts("   3. Consider your use case priorities")
    IO.puts("   4. Monitor in production")
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes}B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)}KB"
  defp format_size(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)}MB"
end

CompressionDecisionTool.main(System.argv())
