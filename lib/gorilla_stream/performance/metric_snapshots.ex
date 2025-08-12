defmodule GorillaStream.Performance.MetricSnapshots do
  @moduledoc """
  Periodic metric snapshot system that captures operations per second and memory usage
  every 10 seconds during benchmark execution.

  Stores snapshots in memory for CSV-style output at the end.
  """

  use GenServer
  require Logger

  # 10 seconds
  @snapshot_interval_ms 10_000

  defmodule Snapshot do
    @moduledoc "Represents a single metric snapshot"

    defstruct [
      :timestamp,
      :elapsed_seconds,
      :raw_enc_ops_since_last,
      :raw_dec_ops_since_last,
      :z_enc_ops_since_last,
      :z_dec_ops_since_last,
      :raw_enc_ops_cumulative,
      :raw_dec_ops_cumulative,
      :z_enc_ops_cumulative,
      :z_dec_ops_cumulative,
      :raw_enc_ops_per_sec_since_last,
      :raw_dec_ops_per_sec_since_last,
      :z_enc_ops_per_sec_since_last,
      :z_dec_ops_per_sec_since_last,
      :raw_enc_ops_per_sec_cumulative,
      :raw_dec_ops_per_sec_cumulative,
      :z_enc_ops_per_sec_cumulative,
      :z_dec_ops_per_sec_cumulative,
      :total_memory_bytes
    ]
  end

  defmodule State do
    @moduledoc "GenServer state for tracking metrics"

    defstruct [
      :start_time,
      :last_snapshot_time,
      :last_ops_counters,
      :snapshots,
      :timer_ref
    ]
  end

  # Client API

  @doc """
  Starts the metric snapshot process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Updates the current operation counters.

  ## Parameters
  - `ops`: A map with operation counts:
    - `:raw_enc_ops` - Raw encoding operations count
    - `:raw_dec_ops` - Raw decoding operations count  
    - `:z_enc_ops` - Zlib encoding operations count
    - `:z_dec_ops` - Zlib decoding operations count
  """
  def update_ops_counters(ops) do
    GenServer.cast(__MODULE__, {:update_ops, ops})
  end

  @doc """
  Gets all captured snapshots.
  """
  def get_snapshots do
    GenServer.call(__MODULE__, :get_snapshots)
  end

  @doc """
  Prints all snapshots in CSV format.
  """
  def print_csv_report do
    snapshots = get_snapshots()
    print_csv_header()
    Enum.each(snapshots, &print_csv_row/1)
  end

  @doc """
  Stops the metric snapshot process and returns final snapshots.
  """
  def stop_and_get_snapshots do
    GenServer.call(__MODULE__, :stop_and_get_snapshots)
  end

  # GenServer Implementation

  @impl true
  def init(_opts) do
    now = System.monotonic_time(:millisecond)

    # Schedule first snapshot
    timer_ref = Process.send_after(self(), :take_snapshot, @snapshot_interval_ms)

    initial_state = %State{
      start_time: now,
      last_snapshot_time: now,
      last_ops_counters: %{
        raw_enc_ops: 0,
        raw_dec_ops: 0,
        z_enc_ops: 0,
        z_dec_ops: 0
      },
      snapshots: [],
      timer_ref: timer_ref
    }

    Logger.info(
      "Started metric snapshots - taking snapshots every #{div(@snapshot_interval_ms, 1000)} seconds"
    )

    {:ok, initial_state}
  end

  @impl true
  def handle_cast({:update_ops, ops}, state) do
    # Store the latest operation counters
    new_state = %{state | last_ops_counters: Map.merge(state.last_ops_counters, ops)}
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_snapshots, _from, state) do
    {:reply, Enum.reverse(state.snapshots), state}
  end

  @impl true
  def handle_call(:stop_and_get_snapshots, _from, state) do
    # Cancel timer and take final snapshot
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    final_state = take_snapshot_now(state)
    snapshots = Enum.reverse(final_state.snapshots)

    {:stop, :normal, snapshots, final_state}
  end

  @impl true
  def handle_info(:take_snapshot, state) do
    # Take snapshot and schedule next one
    new_state = take_snapshot_now(state)
    timer_ref = Process.send_after(self(), :take_snapshot, @snapshot_interval_ms)

    {:noreply, %{new_state | timer_ref: timer_ref}}
  end

  # Private Functions

  defp take_snapshot_now(state) do
    now = System.monotonic_time(:millisecond)
    elapsed_total_seconds = div(now - state.start_time, 1000)
    elapsed_since_last_seconds = div(now - state.last_snapshot_time, 1000)

    # Get current memory usage
    total_memory = :erlang.memory(:total)

    # Calculate operations since last snapshot (handle case where no previous snapshot exists)
    {ops_since_last, cumulative_ops} =
      if length(state.snapshots) == 0 do
        # First snapshot - since_last equals cumulative
        ops = state.last_ops_counters
        {ops, ops}
      else
        # Calculate diff from previous snapshot
        [last_snapshot | _] = state.snapshots

        ops_since_last = %{
          raw_enc_ops: state.last_ops_counters.raw_enc_ops - last_snapshot.raw_enc_ops_cumulative,
          raw_dec_ops: state.last_ops_counters.raw_dec_ops - last_snapshot.raw_dec_ops_cumulative,
          z_enc_ops: state.last_ops_counters.z_enc_ops - last_snapshot.z_enc_ops_cumulative,
          z_dec_ops: state.last_ops_counters.z_dec_ops - last_snapshot.z_dec_ops_cumulative
        }

        {ops_since_last, state.last_ops_counters}
      end

    # Calculate ops per second
    ops_per_sec_since_last = calculate_ops_per_sec(ops_since_last, elapsed_since_last_seconds)
    ops_per_sec_cumulative = calculate_ops_per_sec(cumulative_ops, elapsed_total_seconds)

    snapshot = %Snapshot{
      timestamp: now,
      elapsed_seconds: elapsed_total_seconds,
      raw_enc_ops_since_last: ops_since_last.raw_enc_ops,
      raw_dec_ops_since_last: ops_since_last.raw_dec_ops,
      z_enc_ops_since_last: ops_since_last.z_enc_ops,
      z_dec_ops_since_last: ops_since_last.z_dec_ops,
      raw_enc_ops_cumulative: cumulative_ops.raw_enc_ops,
      raw_dec_ops_cumulative: cumulative_ops.raw_dec_ops,
      z_enc_ops_cumulative: cumulative_ops.z_enc_ops,
      z_dec_ops_cumulative: cumulative_ops.z_dec_ops,
      raw_enc_ops_per_sec_since_last: ops_per_sec_since_last.raw_enc_ops,
      raw_dec_ops_per_sec_since_last: ops_per_sec_since_last.raw_dec_ops,
      z_enc_ops_per_sec_since_last: ops_per_sec_since_last.z_enc_ops,
      z_dec_ops_per_sec_since_last: ops_per_sec_since_last.z_dec_ops,
      raw_enc_ops_per_sec_cumulative: ops_per_sec_cumulative.raw_enc_ops,
      raw_dec_ops_per_sec_cumulative: ops_per_sec_cumulative.raw_dec_ops,
      z_enc_ops_per_sec_cumulative: ops_per_sec_cumulative.z_enc_ops,
      z_dec_ops_per_sec_cumulative: ops_per_sec_cumulative.z_dec_ops,
      total_memory_bytes: total_memory
    }

    # Log the snapshot
    log_snapshot(snapshot)

    %{state | last_snapshot_time: now, snapshots: [snapshot | state.snapshots]}
  end

  defp calculate_ops_per_sec(ops, elapsed_seconds) when elapsed_seconds > 0 do
    %{
      raw_enc_ops: Float.round(ops.raw_enc_ops / elapsed_seconds, 2),
      raw_dec_ops: Float.round(ops.raw_dec_ops / elapsed_seconds, 2),
      z_enc_ops: Float.round(ops.z_enc_ops / elapsed_seconds, 2),
      z_dec_ops: Float.round(ops.z_dec_ops / elapsed_seconds, 2)
    }
  end

  defp calculate_ops_per_sec(_ops, _elapsed_seconds) do
    # Handle division by zero case
    %{raw_enc_ops: 0.0, raw_dec_ops: 0.0, z_enc_ops: 0.0, z_dec_ops: 0.0}
  end

  defp log_snapshot(snapshot) do
    Logger.info("""

    === METRIC SNAPSHOT (#{snapshot.elapsed_seconds}s elapsed) ===
    Since Last (10s):
      • Raw Encode: #{snapshot.raw_enc_ops_since_last} ops (#{snapshot.raw_enc_ops_per_sec_since_last} ops/sec)
      • Raw Decode: #{snapshot.raw_dec_ops_since_last} ops (#{snapshot.raw_dec_ops_per_sec_since_last} ops/sec)
      • Zlib Encode: #{snapshot.z_enc_ops_since_last} ops (#{snapshot.z_enc_ops_per_sec_since_last} ops/sec)
      • Zlib Decode: #{snapshot.z_dec_ops_since_last} ops (#{snapshot.z_dec_ops_per_sec_since_last} ops/sec)

    Cumulative:
      • Raw Encode: #{snapshot.raw_enc_ops_cumulative} ops (#{snapshot.raw_enc_ops_per_sec_cumulative} ops/sec)
      • Raw Decode: #{snapshot.raw_dec_ops_cumulative} ops (#{snapshot.raw_dec_ops_per_sec_cumulative} ops/sec) 
      • Zlib Encode: #{snapshot.z_enc_ops_cumulative} ops (#{snapshot.z_enc_ops_per_sec_cumulative} ops/sec)
      • Zlib Decode: #{snapshot.z_dec_ops_cumulative} ops (#{snapshot.z_dec_ops_per_sec_cumulative} ops/sec)

    Memory: #{format_bytes(snapshot.total_memory_bytes)}
    ========================================
    """)
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"

  defp print_csv_header do
    IO.puts("""
    elapsed_seconds,raw_enc_ops_since_last,raw_dec_ops_since_last,z_enc_ops_since_last,z_dec_ops_since_last,raw_enc_ops_cumulative,raw_dec_ops_cumulative,z_enc_ops_cumulative,z_dec_ops_cumulative,raw_enc_ops_per_sec_since_last,raw_dec_ops_per_sec_since_last,z_enc_ops_per_sec_since_last,z_dec_ops_per_sec_since_last,raw_enc_ops_per_sec_cumulative,raw_dec_ops_per_sec_cumulative,z_enc_ops_per_sec_cumulative,z_dec_ops_per_sec_cumulative,total_memory_bytes\
    """)
  end

  defp print_csv_row(snapshot) do
    IO.puts(
      "#{snapshot.elapsed_seconds},#{snapshot.raw_enc_ops_since_last},#{snapshot.raw_dec_ops_since_last},#{snapshot.z_enc_ops_since_last},#{snapshot.z_dec_ops_since_last},#{snapshot.raw_enc_ops_cumulative},#{snapshot.raw_dec_ops_cumulative},#{snapshot.z_enc_ops_cumulative},#{snapshot.z_dec_ops_cumulative},#{snapshot.raw_enc_ops_per_sec_since_last},#{snapshot.raw_dec_ops_per_sec_since_last},#{snapshot.z_enc_ops_per_sec_since_last},#{snapshot.z_dec_ops_per_sec_since_last},#{snapshot.raw_enc_ops_per_sec_cumulative},#{snapshot.raw_dec_ops_per_sec_cumulative},#{snapshot.z_enc_ops_per_sec_cumulative},#{snapshot.z_dec_ops_per_sec_cumulative},#{snapshot.total_memory_bytes}"
    )
  end
end
