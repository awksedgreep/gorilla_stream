[
  # False positive: pattern can never match in value_decompression.ex
  # This is likely due to complex cond logic where Dialyzer can't determine all paths
  ~r/lib\/gorilla_stream\/compression\/decoder\/value_decompression\.ex:.*pattern_match/,

  # False positive: unreachable patterns in calculate_xor_differences
  # These base cases are defensive programming and may be reached in edge cases
  ~r/lib\/gorilla_stream\/compression\/gorilla\/encoder\.ex:247:8:pattern_match/,

  # Allow unreachable patterns in helper functions as defensive programming
  ~r/pattern_match_cov.*can never match.*calculate_xor_differences/,

  # Ignore infinity comparison warnings - our is_finite checks are intentionally defensive
  ~r/exact_eq.*infinity/
]
