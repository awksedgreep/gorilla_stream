defmodule GorillaStream.Performance.StreamingOpsTest do
  use ExUnit.Case, async: false
  require Logger
  @moduletag :streaming_performance
  alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}

  @tag timeout: 300_000
  test "streaming compression/decompression ops/sec test - 5 million points" do
    total_points = 5_000_000
    batch_size = 10_000
    total_batches = div(total_points, batch_size)

    Logger.info("\n=== Streaming Performance Test ===")
    Logger.info("Total data points: #{total_points}")
    Logger.info("Batch size: #{batch_size}")
    Logger.info("Total batches: #{total_batches}")

    # Start timing
    start_time = :os.system_time(:microsecond)

    # Process all batches
    Enum.each(1..total_batches, fn batch_num ->
      # Generate batch data
      batch_data = generate_batch_data(batch_size, batch_num)

      # Encode -> Decode (round trip)
      {:ok, compressed} = Encoder.encode(batch_data)
      {:ok, decompressed} = Decoder.decode(compressed)

      # Verify correctness
      assert length(decompressed) == batch_size

      # Progress report every 100 batches
      if rem(batch_num, 100) == 0 do
        current_time = :os.system_time(:microsecond)
        elapsed = (current_time - start_time) / 1_000_000
        processed_points = batch_num * batch_size
        ops_per_sec = processed_points / elapsed

        Logger.info(
          "Batch #{batch_num}/#{total_batches}: #{processed_points} points, #{Float.round(ops_per_sec, 0)} ops/sec"
        )
      end
    end)

    # Final timing
    end_time = :os.system_time(:microsecond)
    total_time = (end_time - start_time) / 1_000_000

    # Calculate final ops/sec
    total_ops_per_sec = total_points / total_time

    Logger.info("\n=== Final Results ===")
    Logger.info("Total time: #{Float.round(total_time, 2)} seconds")
    Logger.info("Total operations/sec: #{Float.round(total_ops_per_sec, 0)} ops/sec")
    # Assert reasonable performance
    assert total_ops_per_sec > 10_000,
           "Should achieve at least 10k ops/sec, got #{Float.round(total_ops_per_sec, 0)}"

    Logger.info("Streaming test completed successfully")
  end

  @tag timeout: 300_000
  test "streaming ops with VictoriaMetrics preprocessing (gauge)" do
    require Logger
    total_points = 100_000
    batch_size = 5_000
    total_batches = div(total_points, batch_size)

    Logger.info("\n=== Streaming Performance (VM gauge) ===")
    Logger.info("Total data points: #{total_points}")
    Logger.info("Batch size: #{batch_size}")

    start_time = :os.system_time(:microsecond)

    Enum.each(1..total_batches, fn batch_num ->
      batch_data = generate_batch_data(batch_size, batch_num)

      {:ok, compressed} =
        Encoder.encode(batch_data,
          victoria_metrics: true,
          is_counter: false,
          scale_decimals: :auto
        )

      {:ok, decompressed} = Decoder.decode(compressed)
      assert length(decompressed) == batch_size

      if rem(batch_num, 5) == 0 do
        current_time = :os.system_time(:microsecond)
        elapsed = (current_time - start_time) / 1_000_000
        processed_points = batch_num * batch_size
        ops_per_sec = processed_points / elapsed

        Logger.info(
          "Batch #{batch_num}/#{total_batches}: #{processed_points} points, #{Float.round(ops_per_sec, 0)} ops/sec"
        )
      end
    end)

    end_time = :os.system_time(:microsecond)
    total_time = (end_time - start_time) / 1_000_000
    total_ops_per_sec = total_points / total_time
    Logger.info("Total operations/sec (VM gauge): #{Float.round(total_ops_per_sec, 0)} ops/sec")

    assert total_ops_per_sec > 5000
  end

  # Generate streaming sensor data
  defp generate_batch_data(count, batch_offset) do
    base_timestamp = 1_609_459_200 + (batch_offset - 1) * count * 60
    # Use realistic temperature profile; vary seed per-batch for deterministic uniqueness
    GorillaStream.Performance.RealisticData.generate(count, :temperature,
      interval: 60,
      base_timestamp: base_timestamp,
      seed: {batch_offset, 123, 456}
    )
  end
end
