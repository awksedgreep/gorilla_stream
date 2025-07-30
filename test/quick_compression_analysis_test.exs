defmodule GorillaStream.QuickCompressionAnalysis do
  use ExUnit.Case
  alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}

  test "focused compression comparison - when to use zlib" do
    IO.puts("\n🎯 WHEN TO USE ZLIB WITH GORILLA COMPRESSION")
    IO.puts("=" |> String.duplicate(60))

    # Test different data patterns and sizes
    scenarios = [
      # Small datasets - overhead matters
      {1000, :stable, "1K Stable Sensor Data"},
      {5000, :noisy, "5K Noisy Sensor Data"},

      # Medium datasets - sweet spot
      {10_000, :mixed_patterns, "10K Mixed Pattern Data"},
      {25_000, :server_metrics, "25K Server Metrics"},

      # Larger datasets
      {50_000, :industrial, "50K Industrial Sensor"},
      {100_000, :high_frequency, "100K High-Freq Data"}
    ]

    results =
      Enum.map(scenarios, fn {size, pattern, description} ->
        data = generate_test_data(size, pattern)
        analyze_compression_tradeoffs(data, description)
      end)

    print_key_insights(results)
    print_decision_guide()
  end

  defp generate_test_data(count, pattern) do
    base_time = 1_640_995_200

    case pattern do
      :stable ->
        # Temperature sensor with small variations
        Enum.map(0..(count - 1), fn i ->
          {base_time + i * 60, 23.5 + :rand.normal() * 0.1}
        end)

      :noisy ->
        # Sensor with noise and occasional spikes
        Enum.map(0..(count - 1), fn i ->
          base = 50.0
          noise = :rand.normal() * 3
          spike = if :rand.uniform() < 0.01, do: 20, else: 0
          {base_time + i * 10, base + noise + spike}
        end)

      :mixed_patterns ->
        # Mix of stable, ramping, and noisy periods
        Enum.map(0..(count - 1), fn i ->
          section = rem(i, 1000)

          cond do
            section < 300 ->
              {base_time + i * 10, 25.0 + :rand.normal() * 0.1}

            section < 600 ->
              {base_time + i * 10, 25.0 + (section - 300) * 0.05 + :rand.normal() * 0.5}

            true ->
              {base_time + i * 10, 40.0 + :rand.normal() * 5}
          end
        end)

      :server_metrics ->
        # Server CPU utilization with business hours pattern
        Enum.map(0..(count - 1), fn i ->
          # Minute intervals
          hour = rem(trunc(i / 60), 24)
          load = if hour >= 9 and hour <= 17, do: 70, else: 30
          {base_time + i * 60, load + :rand.normal() * 10}
        end)

      :industrial ->
        # Industrial sensor with degradation cycles
        Enum.map(0..(count - 1), fn i ->
          cycle_pos = rem(i, 5000)
          # Gradual degradation
          base = 100.0 - cycle_pos * 0.01
          {base_time + i * 30, base + :rand.normal() * 2}
        end)

      :high_frequency ->
        # High frequency vibration sensor
        Enum.map(0..(count - 1), fn i ->
          # 50 Hz
          freq = 2 * :math.pi() * 50
          time = i * 0.01
          {base_time + trunc(i * 10), :math.sin(freq * time) + 0.1 * :rand.normal()}
        end)
    end
  end

  defp analyze_compression_tradeoffs(data, description) do
    IO.puts("\n--- #{description} (#{length(data)} points) ---")

    original_binary = :erlang.term_to_binary(data)
    original_size = byte_size(original_binary)

    # Gorilla compression
    {gorilla_time, {:ok, gorilla_compressed}} =
      :timer.tc(fn ->
        Encoder.encode(data)
      end)

    gorilla_size = byte_size(gorilla_compressed)
    gorilla_ratio = gorilla_size / original_size

    # Combined compression (Gorilla + zlib)
    {zlib_time, zlib_compressed} =
      :timer.tc(fn ->
        :zlib.compress(gorilla_compressed)
      end)

    combined_size = byte_size(zlib_compressed)
    combined_ratio = combined_size / original_size

    # Just zlib for comparison
    {pure_zlib_time, pure_zlib_compressed} =
      :timer.tc(fn ->
        :zlib.compress(original_binary)
      end)

    pure_zlib_size = byte_size(pure_zlib_compressed)
    pure_zlib_ratio = pure_zlib_size / original_size

    # Calculate metrics
    total_encode_time = gorilla_time + zlib_time
    additional_benefit = (gorilla_size - combined_size) / gorilla_size * 100
    space_vs_zlib = (pure_zlib_size - combined_size) / pure_zlib_size * 100
    time_overhead = (total_encode_time - gorilla_time) / gorilla_time * 100

    # Results
    IO.puts("Original size: #{format_bytes(original_size)}")

    IO.puts(
      "Gorilla only:  #{format_bytes(gorilla_size)} (#{Float.round(gorilla_ratio, 3)}) - #{div(gorilla_time, 1000)}ms"
    )

    IO.puts(
      "Zlib only:     #{format_bytes(pure_zlib_size)} (#{Float.round(pure_zlib_ratio, 3)}) - #{div(pure_zlib_time, 1000)}ms"
    )

    IO.puts(
      "Combined:      #{format_bytes(combined_size)} (#{Float.round(combined_ratio, 3)}) - #{div(total_encode_time, 1000)}ms"
    )

    IO.puts("")
    IO.puts("📊 Additional compression: #{Float.round(additional_benefit, 1)}%")
    IO.puts("⚡ Time overhead: #{Float.round(time_overhead, 1)}%")
    IO.puts("🆚 Better than zlib by: #{Float.round(space_vs_zlib, 1)}%")

    # Recommendation
    recommendation =
      cond do
        additional_benefit > 15 and original_size > 50_000 ->
          "✅ STRONG YES - High benefit, large dataset"

        additional_benefit > 10 and time_overhead < 100 ->
          "✅ YES - Good benefit, reasonable overhead"

        additional_benefit > 5 and original_size > 100_000 ->
          "⚠️  MAYBE - For storage/bandwidth critical scenarios"

        time_overhead > 200 ->
          "❌ NO - Too much time overhead"

        additional_benefit < 5 ->
          "❌ NO - Minimal benefit"

        true ->
          "⚠️  DEPENDS - Consider your priorities"
      end

    IO.puts("🎯 Recommendation: #{recommendation}")

    %{
      description: description,
      points: length(data),
      original_size: original_size,
      additional_benefit: additional_benefit,
      time_overhead: time_overhead,
      space_vs_zlib: space_vs_zlib,
      recommendation: recommendation
    }
  end

  defp print_key_insights(results) do
    IO.puts(("\n" <> "=") |> String.duplicate(60))
    IO.puts("🔍 KEY INSIGHTS")
    IO.puts("=" |> String.duplicate(60))

    # Categorize results
    strong_yes = Enum.filter(results, &String.contains?(&1.recommendation, "STRONG YES"))
    yes = Enum.filter(results, &String.contains?(&1.recommendation, "YES"))
    maybe = Enum.filter(results, &String.contains?(&1.recommendation, "MAYBE"))
    no = Enum.filter(results, &String.contains?(&1.recommendation, "NO"))

    if length(strong_yes) > 0 do
      IO.puts("\n✅ STRONG CANDIDATES for Gorilla + zlib:")

      Enum.each(strong_yes, fn r ->
        IO.puts(
          "   • #{r.description}: #{Float.round(r.additional_benefit, 1)}% extra compression"
        )
      end)
    end

    if length(yes) > 0 do
      IO.puts("\n✅ GOOD CANDIDATES for Gorilla + zlib:")

      Enum.each(yes, fn r ->
        IO.puts(
          "   • #{r.description}: #{Float.round(r.additional_benefit, 1)}% extra compression, #{Float.round(r.time_overhead, 0)}% slower"
        )
      end)
    end

    if length(no) > 0 do
      IO.puts("\n❌ NOT RECOMMENDED for zlib:")

      Enum.each(no, fn r ->
        IO.puts(
          "   • #{r.description}: Only #{Float.round(r.additional_benefit, 1)}% extra compression"
        )
      end)
    end

    # Overall stats
    avg_benefit =
      Enum.map(results, & &1.additional_benefit) |> Enum.sum() |> Kernel./(length(results))

    avg_overhead =
      Enum.map(results, & &1.time_overhead) |> Enum.sum() |> Kernel./(length(results))

    IO.puts("\n📈 OVERALL AVERAGES:")
    IO.puts("   Average additional compression: #{Float.round(avg_benefit, 1)}%")
    IO.puts("   Average time overhead: #{Float.round(avg_overhead, 1)}%")
  end

  defp print_decision_guide do
    IO.puts(("\n" <> "=") |> String.duplicate(60))
    IO.puts("🎯 DECISION GUIDE: When to use Gorilla + zlib")
    IO.puts("=" |> String.duplicate(60))

    IO.puts("\n✅ USE Gorilla + zlib when:")
    IO.puts("   📁 Long-term storage (cost per GB matters)")
    IO.puts("   🌐 Network transfer over expensive/slow connections")
    IO.puts("   📊 Dataset > 50KB AND additional compression > 10%")
    IO.puts("   ⏱️  Processing time is not critical")
    IO.puts("   🔄 Batch processing scenarios")

    IO.puts("\n❌ DON'T USE zlib when:")
    IO.puts("   ⚡ Real-time processing (latency critical)")
    IO.puts("   📊 Small datasets < 10KB (overhead not worth it)")
    IO.puts("   🎯 Additional compression < 5%")
    IO.puts("   🔄 High throughput scenarios")
    IO.puts("   💻 Client-side processing on mobile devices")

    IO.puts("\n🔧 CONFIGURATION RECOMMENDATIONS:")
    IO.puts("   • Use zlib level 1-3 for speed-sensitive cases")
    IO.puts("   • Use zlib level 6-9 for storage-sensitive cases")
    IO.puts("   • Consider adaptive compression based on data size")
    IO.puts("   • Benchmark with your actual data patterns")

    IO.puts("\n💡 RULE OF THUMB:")
    IO.puts("   If (dataset_size > 50KB) AND (storage_cost > CPU_cost) → Try zlib")
    IO.puts("   If (latency < 100ms required) → Gorilla only")
    IO.puts("   If (additional_compression < 10%) → Probably not worth it")
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes}B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)}KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)}MB"
end
