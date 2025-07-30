defmodule GorillaStream.CompressionComparisonTest do
  use ExUnit.Case
  alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}

  # 5 minutes for large dataset tests
  @moduletag timeout: 300_000
  @moduletag :skip

  describe "Gorilla vs Zlib Compression Analysis" do
    test "comprehensive compression comparison on realistic datasets" do
      IO.puts("\n=== COMPREHENSIVE COMPRESSION ANALYSIS ===")

      datasets = [
        # Small datasets (typical API responses)
        {generate_sensor_data(100, :stable), "Small Stable Sensors (100 points)"},
        {generate_sensor_data(500, :gradual_drift), "Small Drifting Sensors (500 points)"},

        # Medium datasets (hourly data for a month)
        {generate_sensor_data(720, :daily_cycle), "Hourly Data - Month (720 points)"},
        {generate_sensor_data(1440, :noisy), "Minute Data - Day (1440 points)"},

        # Large datasets (high frequency sensors)
        {generate_sensor_data(10_000, :high_frequency), "High Freq - 3 hours (10K points)"},
        {generate_sensor_data(50_000, :mixed_patterns), "Mixed Patterns (50K points)"},
        {generate_sensor_data(100_000, :realistic_server), "Server Metrics (100K points)"},

        # Very large datasets (full day/week of data)
        {generate_sensor_data(500_000, :industrial_sensor),
         "Industrial Sensor - Week (500K points)"},
        {generate_sensor_data(1_000_000, :stock_prices), "Stock Prices - Year (1M points)"}
      ]

      results =
        Enum.map(datasets, fn {data, description} ->
          analyze_compression_methods(data, description)
        end)

      # Summary analysis
      print_summary_analysis(results)

      # Recommendations
      print_recommendations(results)
    end

    test "zlib compression levels comparison" do
      IO.puts("\n=== ZLIB COMPRESSION LEVELS ANALYSIS ===")

      # Test different zlib compression levels (1-9)
      data = generate_sensor_data(50_000, :mixed_patterns)

      IO.puts("Dataset: Mixed Patterns (50K points)")
      IO.puts("Original size: #{byte_size(data_to_binary(data))} bytes")

      # Gorilla baseline
      {gorilla_time, {:ok, gorilla_compressed}} = :timer.tc(fn -> Encoder.encode(data) end)
      gorilla_size = byte_size(gorilla_compressed)
      gorilla_ratio = gorilla_size / byte_size(data_to_binary(data))

      IO.puts(
        "Gorilla: #{gorilla_size} bytes (#{Float.round(gorilla_ratio, 4)}) - #{div(gorilla_time, 1000)}ms"
      )

      # Test different zlib levels
      original_binary = data_to_binary(data)

      Enum.each([1, 3, 6, 9], fn level ->
        # Zlib with different compression levels using deflate
        {zlib_time, zlib_compressed} =
          :timer.tc(fn ->
            z = :zlib.open()
            :zlib.deflateInit(z, level)
            compressed = :zlib.deflate(z, original_binary, :finish)
            :zlib.deflateEnd(z)
            :zlib.close(z)
            IO.iodata_to_binary(compressed)
          end)

        zlib_size = byte_size(zlib_compressed)
        zlib_ratio = zlib_size / byte_size(original_binary)

        # Calculate combined approach (Gorilla + zlib)
        {combined_time, combined_compressed} =
          :timer.tc(fn ->
            z = :zlib.open()
            :zlib.deflateInit(z, level)
            compressed = :zlib.deflate(z, gorilla_compressed, :finish)
            :zlib.deflateEnd(z)
            :zlib.close(z)
            IO.iodata_to_binary(compressed)
          end)

        combined_size = byte_size(combined_compressed)
        combined_ratio = combined_size / byte_size(original_binary)
        total_time = gorilla_time + combined_time

        IO.puts(
          "Zlib L#{level}: #{zlib_size} bytes (#{Float.round(zlib_ratio, 4)}) - #{div(zlib_time, 1000)}ms"
        )

        IO.puts(
          "  Combined: #{combined_size} bytes (#{Float.round(combined_ratio, 4)}) - #{div(total_time, 1000)}ms total"
        )
      end)
    end

    test "compression method decision matrix" do
      IO.puts("\n=== COMPRESSION DECISION MATRIX ===")

      test_scenarios = [
        # Real-time scenarios (latency critical)
        {generate_sensor_data(1000, :stable), "Real-time stable sensors", :low_latency},
        {generate_sensor_data(1000, :high_frequency), "Real-time high-freq data", :low_latency},

        # High-throughput streaming (throughput critical)
        {generate_sensor_data(100_000, :mixed_patterns), "High-throughput streaming",
         :high_throughput},
        {generate_sensor_data(100_000, :industrial_sensor), "Industrial streaming",
         :high_throughput},

        # Long-term storage (space critical)
        {generate_sensor_data(50_000, :stock_prices), "Long-term storage", :space_critical},
        {generate_sensor_data(50_000, :server_metrics), "Log archival", :space_critical}
      ]

      Enum.each(test_scenarios, fn {data, description, priority} ->
        analyze_scenario(data, description, priority)
      end)
    end
  end

  # Generate realistic test data patterns
  defp generate_sensor_data(count, pattern) do
    # Jan 1, 2022
    base_time = 1_640_995_200

    case pattern do
      :stable ->
        # Stable sensor readings with minor fluctuations (temperature sensor)
        Enum.map(0..(count - 1), fn i ->
          {base_time + i * 60, 23.5 + :rand.normal() * 0.2}
        end)

      :gradual_drift ->
        # Slowly changing values (battery voltage)
        Enum.map(0..(count - 1), fn i ->
          drift = i * 0.001
          {base_time + i * 60, 3.7 - drift + :rand.normal() * 0.05}
        end)

      :daily_cycle ->
        # Daily cyclical pattern (temperature with day/night cycle)
        Enum.map(0..(count - 1), fn i ->
          hour_of_day = rem(i, 24)
          temp = 20 + 10 * :math.sin(hour_of_day * :math.pi() / 12) + :rand.normal() * 2
          {base_time + i * 3600, temp}
        end)

      :noisy ->
        # Noisy sensor with occasional spikes
        Enum.map(0..(count - 1), fn i ->
          base_value = 50.0
          noise = :rand.normal() * 5
          spike = if :rand.uniform() < 0.02, do: :rand.uniform() * 100, else: 0
          {base_time + i * 60, base_value + noise + spike}
        end)

      :high_frequency ->
        # High frequency oscillating data (vibration sensor)
        Enum.map(0..(count - 1), fn i ->
          # 50 Hz
          freq = 2 * :math.pi() * 50
          # 100 Hz sampling
          time = i * 0.01
          value = :math.sin(freq * time) + 0.1 * :rand.normal()
          {base_time + trunc(i * 10), value}
        end)

      :mixed_patterns ->
        # Mixed patterns - some stable, some changing
        Enum.map(0..(count - 1), fn i ->
          cond do
            rem(i, 1000) < 200 ->
              # Stable period
              {base_time + i * 10, 25.0 + :rand.normal() * 0.1}

            rem(i, 1000) < 400 ->
              # Ramp up period
              ramp = (rem(i, 1000) - 200) * 0.1
              {base_time + i * 10, 25.0 + ramp + :rand.normal() * 0.5}

            rem(i, 1000) < 600 ->
              # High noise period
              {base_time + i * 10, 35.0 + :rand.normal() * 5}

            true ->
              # Oscillating period
              osc = 10 * :math.sin(i * 0.1)
              {base_time + i * 10, 30.0 + osc + :rand.normal() * 1}
          end
        end)

      :realistic_server ->
        # Server metrics (CPU, memory, etc.)
        Enum.map(0..(count - 1), fn i ->
          # Simulate business hours vs off-hours
          # Assuming 10-second intervals
          hour = rem(trunc(i / 360), 24)
          load_factor = if hour >= 9 and hour <= 17, do: 0.7, else: 0.3
          base_load = load_factor * 80
          noise = :rand.normal() * 10
          spike = if :rand.uniform() < 0.005, do: 40, else: 0
          {base_time + i * 10, max(0, min(100, base_load + noise + spike))}
        end)

      :industrial_sensor ->
        # Industrial sensor with maintenance cycles
        Enum.map(0..(count - 1), fn i ->
          # Regular maintenance every 10000 readings
          maintenance_cycle = rem(i, 10000)

          value =
            cond do
              maintenance_cycle < 50 ->
                # Maintenance period - low values
                5.0 + :rand.normal() * 1

              maintenance_cycle < 9000 ->
                # Normal operation with gradual degradation
                base = 100.0
                degradation = maintenance_cycle * 0.001
                base - degradation + :rand.normal() * 2

              true ->
                # Pre-maintenance period - increasing variability
                base = 90.0 - (maintenance_cycle - 9000) * 0.05
                base + :rand.normal() * (5 + (maintenance_cycle - 9000) * 0.1)
            end

          {base_time + i * 60, value}
        end)

      :stock_prices ->
        # Stock price simulation (random walk with trends)
        {prices, _} =
          Enum.map_reduce(0..(count - 1), 100.0, fn i, prev_price ->
            # Random walk with slight upward bias
            # 0.01% daily drift
            change_percent = :rand.normal() * 0.02 + 0.0001
            new_price = prev_price * (1 + change_percent)
            # Prevent negative prices
            new_price = max(1.0, new_price)

            # Daily prices
            {{base_time + i * 86400, new_price}, new_price}
          end)

        prices

      :server_metrics ->
        # Server performance metrics
        Enum.map(0..(count - 1), fn i ->
          # Simulate weekly patterns
          # Assuming minute intervals
          day_of_week = rem(trunc(i / 1440), 7)
          hour_of_day = rem(trunc(i / 60), 24)

          # Business hours factor
          business_factor =
            cond do
              # Weekend
              day_of_week in [5, 6] -> 0.3
              # Business hours
              hour_of_day >= 9 and hour_of_day <= 17 -> 1.0
              # Off hours
              true -> 0.5
            end

          base_value = business_factor * 75
          noise = :rand.normal() * 8
          {base_time + i * 60, max(0, min(100, base_value + noise))}
        end)
    end
  end

  defp analyze_compression_methods(data, description) do
    IO.puts("\n--- #{description} ---")

    original_binary = data_to_binary(data)
    original_size = byte_size(original_binary)

    IO.puts("Original size: #{format_bytes(original_size)}")

    # Gorilla compression
    {gorilla_encode_time, {:ok, gorilla_compressed}} =
      :timer.tc(fn ->
        Encoder.encode(data)
      end)

    {gorilla_decode_time, _decoded} =
      :timer.tc(fn ->
        Decoder.decode(gorilla_compressed)
      end)

    gorilla_size = byte_size(gorilla_compressed)
    gorilla_ratio = gorilla_size / original_size

    # Zlib compression (level 6 - default)
    {zlib_encode_time, zlib_compressed} =
      :timer.tc(fn ->
        :zlib.compress(original_binary)
      end)

    {zlib_decode_time, _decoded} =
      :timer.tc(fn ->
        :zlib.uncompress(zlib_compressed)
      end)

    zlib_size = byte_size(zlib_compressed)
    zlib_ratio = zlib_size / original_size

    # Combined approach (Gorilla first, then zlib)
    {combined_encode_time, double_compressed} =
      :timer.tc(fn ->
        :zlib.compress(gorilla_compressed)
      end)

    {combined_decode_time, _decoded} =
      :timer.tc(fn ->
        gorilla_result = :zlib.uncompress(double_compressed)
        Decoder.decode(gorilla_result)
      end)

    combined_size = byte_size(double_compressed)
    combined_ratio = combined_size / original_size

    total_encode_time = gorilla_encode_time + combined_encode_time
    total_decode_time = gorilla_decode_time + combined_decode_time

    # Print results
    IO.puts(
      "Gorilla:  #{format_bytes(gorilla_size)} (#{Float.round(gorilla_ratio, 3)}) - Encode: #{div(gorilla_encode_time, 1000)}ms, Decode: #{div(gorilla_decode_time, 1000)}ms"
    )

    IO.puts(
      "Zlib:     #{format_bytes(zlib_size)} (#{Float.round(zlib_ratio, 3)}) - Encode: #{div(zlib_encode_time, 1000)}ms, Decode: #{div(zlib_decode_time, 1000)}ms"
    )

    IO.puts(
      "Combined: #{format_bytes(combined_size)} (#{Float.round(combined_ratio, 3)}) - Encode: #{div(total_encode_time, 1000)}ms, Decode: #{div(total_decode_time, 1000)}ms"
    )

    # Calculate additional compression benefit
    additional_benefit = (gorilla_size - combined_size) / gorilla_size
    IO.puts("Additional compression benefit: #{Float.round(additional_benefit * 100, 1)}%")

    # Performance metrics
    # points/second
    gorilla_throughput = length(data) / (gorilla_encode_time / 1_000_000)
    combined_throughput = length(data) / (total_encode_time / 1_000_000)

    IO.puts("Gorilla throughput: #{format_number(gorilla_throughput)} points/sec")
    IO.puts("Combined throughput: #{format_number(combined_throughput)} points/sec")

    %{
      description: description,
      data_points: length(data),
      original_size: original_size,
      gorilla: %{
        size: gorilla_size,
        ratio: gorilla_ratio,
        encode_time: gorilla_encode_time,
        decode_time: gorilla_decode_time,
        throughput: gorilla_throughput
      },
      zlib: %{
        size: zlib_size,
        ratio: zlib_ratio,
        encode_time: zlib_encode_time,
        decode_time: zlib_decode_time
      },
      combined: %{
        size: combined_size,
        ratio: combined_ratio,
        encode_time: total_encode_time,
        decode_time: total_decode_time,
        additional_benefit: additional_benefit,
        throughput: combined_throughput
      }
    }
  end

  defp analyze_scenario(data, description, priority) do
    IO.puts("\n--- #{description} (#{priority}) ---")

    result = analyze_compression_methods(data, description)

    recommendation =
      case priority do
        :low_latency ->
          if result.gorilla.encode_time < result.combined.encode_time * 0.5 do
            "✅ Use Gorilla only - latency is critical"
          else
            "⚠️  Consider combined if space savings > #{Float.round(result.combined.additional_benefit * 100, 0)}% justify latency"
          end

        :high_throughput ->
          throughput_loss =
            (result.gorilla.throughput - result.combined.throughput) / result.gorilla.throughput

          if throughput_loss > 0.3 do
            "✅ Use Gorilla only - throughput loss too high (#{Float.round(throughput_loss * 100, 0)}%)"
          else
            "⚠️  Combined acceptable - throughput loss: #{Float.round(throughput_loss * 100, 0)}%"
          end

        :space_critical ->
          if result.combined.additional_benefit > 0.1 do
            "✅ Use combined - additional #{Float.round(result.combined.additional_benefit * 100, 0)}% space savings"
          else
            "⚠️  Gorilla sufficient - minimal additional benefit (#{Float.round(result.combined.additional_benefit * 100, 1)}%)"
          end
      end

    IO.puts("Recommendation: #{recommendation}")
  end

  defp print_summary_analysis(results) do
    IO.puts("\n=== SUMMARY ANALYSIS ===")

    # Calculate averages
    avg_gorilla_ratio =
      Enum.map(results, & &1.gorilla.ratio) |> Enum.sum() |> Kernel./(length(results))

    avg_combined_ratio =
      Enum.map(results, & &1.combined.ratio) |> Enum.sum() |> Kernel./(length(results))

    avg_additional_benefit =
      Enum.map(results, & &1.combined.additional_benefit)
      |> Enum.sum()
      |> Kernel./(length(results))

    avg_gorilla_throughput =
      Enum.map(results, & &1.gorilla.throughput) |> Enum.sum() |> Kernel./(length(results))

    avg_combined_throughput =
      Enum.map(results, & &1.combined.throughput) |> Enum.sum() |> Kernel./(length(results))

    IO.puts("Average Gorilla compression ratio: #{Float.round(avg_gorilla_ratio, 3)}")
    IO.puts("Average Combined compression ratio: #{Float.round(avg_combined_ratio, 3)}")

    IO.puts(
      "Average additional benefit from zlib: #{Float.round(avg_additional_benefit * 100, 1)}%"
    )

    IO.puts(
      "Average throughput loss: #{Float.round((avg_gorilla_throughput - avg_combined_throughput) / avg_gorilla_throughput * 100, 1)}%"
    )

    # Find best and worst cases
    best_benefit = Enum.max_by(results, & &1.combined.additional_benefit)
    worst_benefit = Enum.min_by(results, & &1.combined.additional_benefit)

    IO.puts(
      "\nBest additional compression: #{best_benefit.description} (#{Float.round(best_benefit.combined.additional_benefit * 100, 1)}%)"
    )

    IO.puts(
      "Worst additional compression: #{worst_benefit.description} (#{Float.round(worst_benefit.combined.additional_benefit * 100, 1)}%)"
    )
  end

  defp print_recommendations(results) do
    IO.puts("\n=== RECOMMENDATIONS ===")

    high_benefit_datasets = Enum.filter(results, &(&1.combined.additional_benefit > 0.15))
    low_benefit_datasets = Enum.filter(results, &(&1.combined.additional_benefit < 0.05))

    IO.puts("📈 HIGH BENEFIT from zlib (>15% additional compression):")

    Enum.each(high_benefit_datasets, fn result ->
      IO.puts(
        "  • #{result.description}: #{Float.round(result.combined.additional_benefit * 100, 1)}% benefit"
      )
    end)

    IO.puts("\n📉 LOW BENEFIT from zlib (<5% additional compression):")

    Enum.each(low_benefit_datasets, fn result ->
      IO.puts(
        "  • #{result.description}: #{Float.round(result.combined.additional_benefit * 100, 1)}% benefit"
      )
    end)

    IO.puts("\n🎯 DECISION GUIDELINES:")
    IO.puts("✅ Use Gorilla + zlib when:")
    IO.puts("  • Space is critical (archival, long-term storage)")
    IO.puts("  • Data has repetitive patterns (server logs, industrial sensors)")
    IO.puts("  • Network bandwidth is expensive")
    IO.puts("  • Processing time is not critical")

    IO.puts("\n✅ Use Gorilla only when:")
    IO.puts("  • Real-time processing required")
    IO.puts("  • High throughput needed")
    IO.puts("  • Data already highly compressed by Gorilla (>50% compression)")
    IO.puts("  • Additional benefit < 10%")

    IO.puts("\n📊 RULE OF THUMB:")
    IO.puts("  • Dataset < 10KB: Skip zlib (overhead not worth it)")
    IO.puts("  • Dataset > 100KB + space critical: Always try zlib")
    IO.puts("  • Real-time systems: Gorilla only")
    IO.puts("  • High-throughput streaming: Test both and decide based on requirements")
  end

  defp data_to_binary(data) do
    :erlang.term_to_binary(data)
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes}B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)}KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)}MB"

  defp format_number(num) when num > 1_000_000, do: "#{Float.round(num / 1_000_000, 1)}M"
  defp format_number(num) when num > 1_000, do: "#{Float.round(num / 1_000, 0)}K"
  defp format_number(num), do: "#{Float.round(num, 0)}"
end
