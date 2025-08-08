alias GorillaStream.Compression.Decoder.DeltaDecoding

input = "not bitstring"
metadata = %{count: 2}

IO.puts("Testing decode with:")
IO.inspect(input, label: "Input")
IO.inspect(metadata, label: "Metadata")
IO.puts("bit_size: #{bit_size(input)}")

result = DeltaDecoding.decode(input, metadata)
IO.inspect(result, label: "Result")

# Now test validate
validate_result = DeltaDecoding.validate_bitstream(input, 2)
IO.inspect(validate_result, label: "Validate result")
