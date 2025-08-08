alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}

# Generate some test data
test_data = [{1609459200, 20.0}, {1609459260, 20.1}, {1609459320, 19.9}]

IO.puts("Original data: #{inspect(test_data)}")

# Encode it
{:ok, compressed} = Encoder.encode(test_data)
IO.puts("Compressed successfully")

# Try to decode it and see what we get
result = Decoder.decode(compressed)
IO.puts("Decoder result: #{inspect(result)}")

# Check the type
IO.puts("Result type: #{inspect(elem(result, 0))}")
