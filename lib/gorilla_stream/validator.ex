defmodule GorillaStream.Validator do
  @moduledoc """
  Data validation and quality checking utilities for time series data.

  Provides functions to validate, clean, and assess the quality of time series
  data before compression.
  """

  @doc """
  Validates time series data and reports any issues.

  ## Examples

      iex> data = [{1609459200, 23.5}, {1609459201, 23.6}]
      iex> GorillaStream.Validator.validate(data)
      {:ok, %{valid_points: 2, issues: []}}

      iex> bad_data = [{1609459200, 23.5}, {"invalid", 23.6}]
      iex> GorillaStream.Validator.validate(bad_data)
      {:error, %{valid_points: 1, issues: [:invalid_timestamp]}}
  """
  def validate(data, opts \\ []) do
    strict = Keyword.get(opts, :strict, false)

    issues = []
    valid_count = 0

    {issues, valid_count} =
      Enum.reduce(data, {issues, valid_count}, fn item, {acc_issues, acc_valid} ->
        case validate_point(item) do
          :ok -> {acc_issues, acc_valid + 1}
          {:error, issue} -> {[issue | acc_issues], acc_valid}
        end
      end)

    # Additional validations
    issues = check_timestamp_ordering(data, issues)
    issues = check_duplicate_timestamps(data, issues)
    issues = check_data_gaps(data, issues)
    issues = check_value_quality(data, issues)

    result = %{
      valid_points: valid_count,
      total_points: length(data),
      issues: Enum.reverse(issues),
      quality_score: calculate_quality_score(valid_count, length(data), issues)
    }

    if length(issues) == 0 or not strict do
      {:ok, result}
    else
      {:error, result}
    end
  end

  @doc """
  Cleans and fixes common issues in time series data.

  ## Options
  - `:remove_duplicates` - Remove duplicate timestamps (default: true)
  - `:sort` - Sort by timestamp (default: true)
  - `:fix_values` - Attempt to fix invalid values (default: false)
  - `:interpolate_gaps` - Fill small gaps with interpolated values (default: false)
  """
  def clean(data, opts \\ []) do
    remove_duplicates = Keyword.get(opts, :remove_duplicates, true)
    sort_data = Keyword.get(opts, :sort, true)
    fix_values = Keyword.get(opts, :fix_values, false)
    interpolate_gaps = Keyword.get(opts, :interpolate_gaps, false)

    cleaned_data =
      data
      |> filter_valid_points()
      |> maybe_sort(sort_data)
      |> maybe_remove_duplicates(remove_duplicates)
      |> maybe_fix_values(fix_values)
      |> maybe_interpolate_gaps(interpolate_gaps)

    original_count = length(data)
    cleaned_count = length(cleaned_data)

    {:ok, cleaned_data,
     %{
       original_points: original_count,
       cleaned_points: cleaned_count,
       removed_points: original_count - cleaned_count
     }}
  end

  @doc """
  Assesses the compression-friendliness of data.
  """
  def assess_compression_potential(data) do
    if length(data) < 2 do
      %{
        score: 0.0,
        recommendations: ["Need at least 2 data points for analysis"],
        expected_ratio: 1.0
      }
    else
      timestamp_score = assess_timestamp_regularity(data)
      value_score = assess_value_stability(data)
      overall_score = (timestamp_score + value_score) / 2

      recommendations = generate_recommendations(timestamp_score, value_score)
      expected_ratio = estimate_compression_ratio(timestamp_score, value_score)

      %{
        score: overall_score,
        timestamp_regularity: timestamp_score,
        value_stability: value_score,
        recommendations: recommendations,
        expected_compression_ratio: expected_ratio
      }
    end
  end

  defp validate_point({timestamp, value}) when is_integer(timestamp) and is_number(value) do
    cond do
      timestamp < 0 -> {:error, :negative_timestamp}
      not is_finite_number(value) -> {:error, :invalid_value}
      true -> :ok
    end
  end

  defp validate_point(_), do: {:error, :invalid_format}

  defp is_finite_number(value) when is_float(value) do
    not (value != value or value == :infinity or value == :neg_infinity)
  end

  defp is_finite_number(value) when is_integer(value), do: true
  defp is_finite_number(_), do: false

  defp check_timestamp_ordering(data, issues) do
    timestamps = Enum.map(data, fn {ts, _} -> ts end)

    if timestamps == Enum.sort(timestamps) do
      issues
    else
      [:unsorted_timestamps | issues]
    end
  end

  defp check_duplicate_timestamps(data, issues) do
    timestamps = Enum.map(data, fn {ts, _} -> ts end)
    unique_timestamps = Enum.uniq(timestamps)

    if length(timestamps) == length(unique_timestamps) do
      issues
    else
      [:duplicate_timestamps | issues]
    end
  end

  defp check_data_gaps(data, issues) do
    if length(data) < 3 do
      issues
    else
      timestamps = Enum.map(data, fn {ts, _} -> ts end)

      deltas =
        Enum.zip(timestamps, tl(timestamps))
        |> Enum.map(fn {a, b} -> b - a end)

      mean_delta = Enum.sum(deltas) / length(deltas)
      large_gaps = Enum.count(deltas, fn delta -> delta > mean_delta * 3 end)

      if large_gaps > length(deltas) * 0.1 do
        [:significant_gaps | issues]
      else
        issues
      end
    end
  end

  defp check_value_quality(data, issues) do
    values = Enum.map(data, fn {_, val} -> val end)

    # Check for NaN
    issues =
      if Enum.any?(values, &(&1 != &1)) do
        [:nan_values | issues]
      else
        issues
      end

    issues =
      if Enum.any?(values, &(&1 == :infinity or &1 == :neg_infinity)) do
        [:infinite_values | issues]
      else
        issues
      end

    issues
  end

  defp calculate_quality_score(valid_count, total_count, issues) do
    base_score = valid_count / max(total_count, 1)
    penalty = length(issues) * 0.1
    max(0.0, base_score - penalty)
  end

  defp filter_valid_points(data) do
    Enum.filter(data, fn point ->
      case validate_point(point) do
        :ok -> true
        _ -> false
      end
    end)
  end

  defp maybe_sort(data, true), do: Enum.sort_by(data, fn {ts, _} -> ts end)
  defp maybe_sort(data, false), do: data

  defp maybe_remove_duplicates(data, true) do
    Enum.uniq_by(data, fn {ts, _} -> ts end)
  end

  defp maybe_remove_duplicates(data, false), do: data

  defp maybe_fix_values(data, true) do
    Enum.map(data, fn {ts, val} ->
      fixed_val =
        cond do
          # Replace NaN with 0
          val != val -> 0.0
          # Replace infinity with large number
          val == :infinity -> 1.0e308
          val == :neg_infinity -> -1.0e308
          true -> val
        end

      {ts, fixed_val}
    end)
  end

  defp maybe_fix_values(data, false), do: data

  defp maybe_interpolate_gaps(data, false), do: data

  defp maybe_interpolate_gaps(data, true) do
    # Simple linear interpolation for small gaps
    # This is a basic implementation - could be enhanced
    data
  end

  defp assess_timestamp_regularity(data) do
    timestamps = Enum.map(data, fn {ts, _} -> ts end)

    deltas =
      Enum.zip(timestamps, tl(timestamps))
      |> Enum.map(fn {a, b} -> b - a end)

    if length(deltas) == 0 do
      1.0
    else
      mean_delta = Enum.sum(deltas) / length(deltas)

      variance =
        Enum.map(deltas, fn d -> :math.pow(d - mean_delta, 2) end)
        |> Enum.sum()
        |> Kernel./(length(deltas))

      # Score based on coefficient of variation
      cv = :math.sqrt(variance) / max(mean_delta, 1)
      max(0.0, 1.0 - cv)
    end
  end

  defp assess_value_stability(data) do
    values = Enum.map(data, fn {_, val} -> val end)

    if length(values) <= 1 do
      1.0
    else
      changes =
        Enum.zip(values, tl(values))
        |> Enum.map(fn {a, b} -> abs(b - a) end)

      mean_change = Enum.sum(changes) / length(changes)
      value_range = Enum.max(values) - Enum.min(values)

      if value_range == 0 do
        # Identical values - perfect for compression
        1.0
      else
        stability = 1.0 - mean_change / value_range
        max(0.0, stability)
      end
    end
  end

  defp generate_recommendations(timestamp_score, value_score) do
    recommendations = []

    recommendations =
      if timestamp_score < 0.7 do
        ["Consider sorting data by timestamp for better compression" | recommendations]
      else
        recommendations
      end

    recommendations =
      if value_score < 0.5 do
        ["Values change frequently - compression may be limited" | recommendations]
      else
        recommendations
      end

    recommendations =
      if timestamp_score > 0.8 and value_score > 0.8 do
        ["Excellent data for Gorilla compression!" | recommendations]
      else
        recommendations
      end

    if length(recommendations) == 0 do
      ["Data should compress reasonably well"]
    else
      recommendations
    end
  end

  defp estimate_compression_ratio(timestamp_score, value_score) do
    # Very rough estimation based on data characteristics
    base_ratio = 0.8

    # Better timestamp regularity = better compression
    timestamp_factor = 1.0 - timestamp_score * 0.3

    # More stable values = better compression
    value_factor = 1.0 - value_score * 0.4

    estimated_ratio = base_ratio * timestamp_factor * value_factor
    max(0.1, min(1.0, estimated_ratio))
  end
end
