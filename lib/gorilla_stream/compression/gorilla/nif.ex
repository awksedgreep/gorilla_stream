defmodule GorillaStream.Compression.Gorilla.NIF do
  @moduledoc false

  @on_load :load_nif

  def load_nif do
    path = :filename.join(:code.priv_dir(:gorilla_stream), ~c"gorilla_nif")

    case :erlang.load_nif(path, 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def nif_gorilla_encode(_data, _opts), do: :erlang.nif_error(:not_loaded)
  def nif_gorilla_decode(_data), do: :erlang.nif_error(:not_loaded)
end
