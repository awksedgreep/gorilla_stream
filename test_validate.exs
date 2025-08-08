alias GorillaStream.Compression.Decoder.DeltaDecoding

input = "not bitstring"
IO.puts("bit_size of 'not bitstring': #{bit_size(input)}")
IO.puts("byte_size: #{byte_size(input)}")

result = DeltaDecoding.validate_bitstream(input, 2)
IO.inspect(result, label: "Validate result")

# Let's decode it directly
decode_result = DeltaDecoding.decode(input, %{count: 2})
IO.inspect(decode_result, label: "Decode result")
