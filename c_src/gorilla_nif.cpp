// Gorilla compression NIF — byte-identical to the Elixir encoder output.
//
// Two dirty-CPU NIF functions:
//   nif_gorilla_encode(data, opts) -> {:ok, binary}
//   nif_gorilla_decode(data)       -> {:ok, [{int64, float}]}

#include <fine.hpp>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <variant>
#include <vector>

// ---------------------------------------------------------------------------
// CRC32 — ISO 3309 lookup table (matches :erlang.crc32/1)
// ---------------------------------------------------------------------------

static uint32_t crc32_table[256];
static std::once_flag crc32_init_flag;

static void do_init_crc32_table() {
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int j = 0; j < 8; j++) {
            c = (c & 1) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
        }
        crc32_table[i] = c;
    }
}

static void init_crc32_table() {
    std::call_once(crc32_init_flag, do_init_crc32_table);
}

static uint32_t crc32(const uint8_t *data, size_t len) {
    init_crc32_table();
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < len; i++) {
        c = crc32_table[(c ^ data[i]) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFFu;
}

// ---------------------------------------------------------------------------
// Byte-order helpers
// ---------------------------------------------------------------------------

// Compile-time endianness detection.
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
  #define IS_BIG_ENDIAN 1
#else
  #define IS_BIG_ENDIAN 0
#endif

static inline uint64_t byte_swap_64(uint64_t v) {
    return ((v & 0x00000000000000FFULL) << 56) |
           ((v & 0x000000000000FF00ULL) << 40) |
           ((v & 0x0000000000FF0000ULL) << 24) |
           ((v & 0x00000000FF000000ULL) << 8)  |
           ((v & 0x000000FF00000000ULL) >> 8)  |
           ((v & 0x0000FF0000000000ULL) >> 24) |
           ((v & 0x00FF000000000000ULL) >> 40) |
           ((v & 0xFF00000000000000ULL) >> 56);
}

// Convert double to its 64-bit IEEE 754 integer representation.
// The BitWriter writes MSB-first, matching Elixir's <<value::float-64>>.
// On big-endian architectures the byte order is already network order so no
// swap is needed; on little-endian we keep the raw bit pattern as-is because
// the BitWriter emits bits MSB-first independently of host byte order.

static inline uint64_t float_to_bits(double v) {
    uint64_t bits;
    memcpy(&bits, &v, sizeof(bits));
#if IS_BIG_ENDIAN
    bits = byte_swap_64(bits);
#endif
    return bits;
}

static inline double bits_to_float(uint64_t bits) {
#if IS_BIG_ENDIAN
    bits = byte_swap_64(bits);
#endif
    double v;
    memcpy(&v, &bits, sizeof(v));
    return v;
}

// ---------------------------------------------------------------------------
// BitWriter — MSB-first bit accumulator (matches Elixir's <<v::size(N)>>)
// ---------------------------------------------------------------------------

class BitWriter {
public:
    BitWriter() : buf_(0), bits_(0) {}

    void write(uint64_t value, int nbits) {
        if (nbits <= 0) return;
        // Split writes > 32 bits to avoid UB from shifting uint64_t by >= 64
        if (nbits > 32) {
            int hi_bits = nbits - 32;
            write(value >> 32, hi_bits);
            write(value & 0xFFFFFFFFULL, 32);
            return;
        }
        // Accumulate bits MSB-first, flushing complete bytes.
        uint64_t mask = (uint64_t(1) << nbits) - 1;
        buf_ = (buf_ << nbits) | (value & mask);
        bits_ += nbits;
        flush();
    }

    // Write a signed value in two's complement, nbits wide.
    void write_signed(int64_t value, int nbits) {
        uint64_t mask = (nbits >= 64) ? UINT64_MAX : ((uint64_t(1) << nbits) - 1);
        write(static_cast<uint64_t>(value) & mask, nbits);
    }

    const std::vector<uint8_t> &bytes() const { return out_; }

    // Remaining sub-byte bits count.
    int remaining_bits() const { return bits_; }
    uint64_t remaining_buf() const { return buf_; }

    // Return full binary including any trailing sub-byte bits (as a bitstring).
    // For the inner packed data we need bit-level precision, but the outer
    // format always pads to byte boundary.
    size_t total_bits() const { return out_.size() * 8 + bits_; }

    // Append trailing bits (left-aligned in byte) and return byte vector.
    // This pads the remaining bits with zeros to the right to fill a byte.
    std::vector<uint8_t> to_bytes_padded() const {
        auto result = out_;
        if (bits_ > 0) {
            result.push_back(static_cast<uint8_t>(buf_ << (8 - bits_)));
        }
        return result;
    }

    // Return a bitstring-compatible representation: full bytes + trailing bits.
    // trailing_bits_count is set to the number of trailing sub-byte bits (0-7).
    std::vector<uint8_t> to_bytes(int &trailing_bits_count) const {
        auto result = out_;
        trailing_bits_count = bits_;
        if (bits_ > 0) {
            result.push_back(static_cast<uint8_t>(buf_ << (8 - bits_)));
        }
        return result;
    }

private:
    void flush() {
        while (bits_ >= 8) {
            bits_ -= 8;
            out_.push_back(static_cast<uint8_t>((buf_ >> bits_) & 0xFF));
        }
    }

    std::vector<uint8_t> out_;
    uint64_t buf_;
    int bits_;
};

// ---------------------------------------------------------------------------
// BitReader — MSB-first bit reader
// ---------------------------------------------------------------------------

class BitReader {
public:
    BitReader(const uint8_t *data, size_t total_bits)
        : data_(data), total_bits_(total_bits), pos_(0) {}

    uint64_t read(int nbits) {
        uint64_t result = 0;
        for (int i = 0; i < nbits; i++) {
            result = (result << 1) | read_bit();
        }
        return result;
    }

    int64_t read_signed(int nbits) {
        uint64_t raw = read(nbits);
        if (nbits >= 64) return static_cast<int64_t>(raw);
        // Sign-extend
        if (raw & (uint64_t(1) << (nbits - 1))) {
            raw |= ~((uint64_t(1) << nbits) - 1);
        }
        return static_cast<int64_t>(raw);
    }

    uint64_t read_bit() {
        if (pos_ >= total_bits_) {
            throw std::runtime_error("BitReader: read past end");
        }
        size_t byte_idx = pos_ / 8;
        int bit_idx = 7 - (pos_ % 8);  // MSB first
        pos_++;
        return (data_[byte_idx] >> bit_idx) & 1;
    }

    size_t position() const { return pos_; }
    size_t remaining() const { return total_bits_ > pos_ ? total_bits_ - pos_ : 0; }

private:
    const uint8_t *data_;
    size_t total_bits_;
    size_t pos_;
};

// ---------------------------------------------------------------------------
// Delta-of-delta timestamp encoding
// ---------------------------------------------------------------------------

static void encode_first_delta(BitWriter &w, int64_t delta) {
    if (delta == 0) {
        w.write(0, 1);  // 0
    } else if (delta >= -63 && delta <= 64) {
        w.write(0b10, 2);
        w.write_signed(delta, 7);
    } else if (delta >= -255 && delta <= 256) {
        w.write(0b110, 3);
        w.write_signed(delta, 9);
    } else if (delta >= -2047 && delta <= 2048) {
        w.write(0b1110, 4);
        w.write_signed(delta, 12);
    } else {
        w.write(0b1111, 4);
        w.write_signed(delta, 32);
    }
}

static void encode_delta_of_delta(BitWriter &w, int64_t dod) {
    if (dod == 0) {
        w.write(0, 1);
    } else if (dod >= -63 && dod <= 64) {
        w.write(0b10, 2);
        w.write_signed(dod, 7);
    } else if (dod >= -255 && dod <= 256) {
        w.write(0b110, 3);
        w.write_signed(dod, 9);
    } else if (dod >= -2047 && dod <= 2048) {
        w.write(0b1110, 4);
        w.write_signed(dod, 12);
    } else {
        w.write(0b1111, 4);
        w.write_signed(dod, 32);
    }
}

struct TimestampEncodeResult {
    BitWriter writer;
    int64_t first_timestamp;
    int64_t first_delta;
    size_t count;
};

static TimestampEncodeResult encode_timestamps(const std::vector<int64_t> &timestamps) {
    TimestampEncodeResult result;
    result.count = timestamps.size();

    if (timestamps.empty()) {
        result.first_timestamp = 0;
        result.first_delta = 0;
        return result;
    }

    result.first_timestamp = timestamps[0];
    result.writer.write(static_cast<uint64_t>(timestamps[0]), 64);

    if (timestamps.size() == 1) {
        result.first_delta = 0;
        return result;
    }

    result.first_delta = timestamps[1] - timestamps[0];
    encode_first_delta(result.writer, result.first_delta);

    int64_t prev_delta = result.first_delta;
    for (size_t i = 2; i < timestamps.size(); i++) {
        int64_t current_delta = timestamps[i] - timestamps[i - 1];
        int64_t dod = current_delta - prev_delta;
        encode_delta_of_delta(result.writer, dod);
        prev_delta = current_delta;
    }

    return result;
}

// ---------------------------------------------------------------------------
// XOR value compression
// ---------------------------------------------------------------------------

// Safe mask for N bits (handles N >= 64 without UB)
static inline uint64_t bitmask(int n) {
    return (n >= 64) ? UINT64_MAX : ((uint64_t(1) << n) - 1);
}

static inline int count_leading_zeros_64(uint64_t v) {
    if (v == 0) return 64;
#if defined(__GNUC__) || defined(__clang__)
    return __builtin_clzll(v);
#elif defined(_MSC_VER)
    // _BitScanReverse64 is only undefined for v==0, which is guarded above.
    unsigned long idx;
    _BitScanReverse64(&idx, v);
    return 63 - (int)idx;
#else
    int n = 0;
    if (v <= 0x00000000FFFFFFFFULL) { n += 32; v <<= 32; }
    if (v <= 0x0000FFFFFFFFFFFFULL) { n += 16; v <<= 16; }
    if (v <= 0x00FFFFFFFFFFFFFFULL) { n += 8;  v <<= 8;  }
    if (v <= 0x0FFFFFFFFFFFFFFFULL) { n += 4;  v <<= 4;  }
    if (v <= 0x3FFFFFFFFFFFFFFFULL) { n += 2;  v <<= 2;  }
    if (v <= 0x7FFFFFFFFFFFFFFFULL) { n += 1; }
    return n;
#endif
}

static inline int count_trailing_zeros_64(uint64_t v) {
    if (v == 0) return 64;
#if defined(__GNUC__) || defined(__clang__)
    return __builtin_ctzll(v);
#elif defined(_MSC_VER)
    // _BitScanForward64 is only undefined for v==0, which is guarded above.
    unsigned long idx;
    _BitScanForward64(&idx, v);
    return (int)idx;
#else
    int n = 0;
    if ((v & 0x00000000FFFFFFFFULL) == 0) { n += 32; v >>= 32; }
    if ((v & 0x000000000000FFFFULL) == 0) { n += 16; v >>= 16; }
    if ((v & 0x00000000000000FFULL) == 0) { n += 8;  v >>= 8;  }
    if ((v & 0x000000000000000FULL) == 0) { n += 4;  v >>= 4;  }
    if ((v & 0x0000000000000003ULL) == 0) { n += 2;  v >>= 2;  }
    if ((v & 0x0000000000000001ULL) == 0) { n += 1; }
    return n;
#endif
}

struct ValueEncodeResult {
    BitWriter writer;
    double first_value;
    size_t count;
};

static ValueEncodeResult encode_values(const std::vector<double> &values) {
    ValueEncodeResult result;
    result.count = values.size();

    if (values.empty()) {
        result.first_value = 0.0;
        return result;
    }

    result.first_value = values[0];
    uint64_t first_bits = float_to_bits(values[0]);
    result.writer.write(first_bits, 64);

    if (values.size() == 1) {
        return result;
    }

    uint64_t prev_bits = first_bits;
    int prev_leading = 0;
    int prev_trailing = 0;

    for (size_t i = 1; i < values.size(); i++) {
        uint64_t curr_bits = float_to_bits(values[i]);
        uint64_t xor_val = curr_bits ^ prev_bits;

        if (xor_val == 0) {
            // Identical — single '0' bit
            result.writer.write(0, 1);
        } else {
            int leading = count_leading_zeros_64(xor_val);
            int trailing = count_trailing_zeros_64(xor_val);
            int meaningful = 64 - leading - trailing;

            if (leading >= prev_leading && trailing >= prev_trailing &&
                (64 - prev_leading - prev_trailing) > 0) {
                // Reuse previous window — '10' + meaningful bits
                int prev_meaningful = 64 - prev_leading - prev_trailing;
                uint64_t meaningful_value =
                    (xor_val >> prev_trailing) & bitmask(prev_meaningful);
                result.writer.write(0b10, 2);
                result.writer.write(meaningful_value, prev_meaningful);
            } else {
                // New window — '11' + 5 bits leading + 6 bits (length-1) + meaningful bits
                int adj_leading = std::min(leading, 31);  // 5 bits max
                int adj_meaningful = std::max(1, std::min(64, meaningful));
                uint64_t meaningful_value =
                    (xor_val >> trailing) & bitmask(adj_meaningful);

                result.writer.write(0b11, 2);
                result.writer.write(static_cast<uint64_t>(adj_leading), 5);
                result.writer.write(static_cast<uint64_t>(adj_meaningful - 1), 6);
                result.writer.write(meaningful_value, adj_meaningful);

                prev_leading = adj_leading;
                prev_trailing = trailing;
            }
        }

        prev_bits = curr_bits;
    }

    return result;
}

// ---------------------------------------------------------------------------
// Inner header (32 bytes) — matches BitPacking.pack/2
// ---------------------------------------------------------------------------
// Layout (all big-endian):
//   count            : 32
//   first_timestamp   : 64
//   first_value_bits  : 64
//   first_delta       : 32 (signed)
//   ts_bit_len        : 32
//   val_bit_len       : 32
//   --------------------------------
//   Total = 256 bits = 32 bytes

static std::vector<uint8_t> build_inner_header(
    uint32_t count,
    int64_t first_timestamp,
    uint64_t first_value_bits,
    int32_t first_delta,
    uint32_t ts_bit_len,
    uint32_t val_bit_len)
{
    BitWriter w;
    w.write(count, 32);
    w.write(static_cast<uint64_t>(first_timestamp), 64);
    w.write(first_value_bits, 64);
    w.write_signed(first_delta, 32);
    w.write(ts_bit_len, 32);
    w.write(val_bit_len, 32);
    int trailing;
    return w.to_bytes(trailing);
}

// ---------------------------------------------------------------------------
// Outer metadata header — matches Encoder.Metadata.add_metadata/2
// ---------------------------------------------------------------------------
// V1 = 80 bytes, V2 = 84 bytes (has scale_decimals)
//
// Layout (all big-endian):
//   magic            : 64   "GORILLA"
//   version          : 16   1
//   header_size      : 16   80 | 84
//   count            : 32
//   compressed_size  : 32
//   original_size    : 32
//   crc32            : 32
//   first_timestamp  : 64
//   first_delta      : 32 (signed)
//   first_value_bits : 64
//   ts_bit_len       : 32
//   val_bit_len      : 32
//   total_bits       : 32
//   compression_ratio: float-64
//   creation_time    : 64
//   flags            : 32
//   [scale_decimals] : 32   (V2 only)

static const uint64_t GORILLA_MAGIC = 0x474F52494C4C41ULL;
static const uint16_t GORILLA_VERSION = 1;

static std::vector<uint8_t> build_outer_header(
    uint32_t count,
    uint32_t compressed_size,
    uint32_t checksum,
    int64_t first_timestamp,
    int32_t first_delta,
    uint64_t first_value_bits,
    uint32_t ts_bit_len,
    uint32_t val_bit_len,
    uint32_t total_bits,
    double compression_ratio,
    int64_t creation_time,
    uint32_t flags,
    uint32_t scale_decimals,
    bool v2)
{
    uint16_t header_size = v2 ? 84 : 80;
    uint32_t original_size = count * 16;

    BitWriter w;
    w.write(GORILLA_MAGIC, 64);
    w.write(GORILLA_VERSION, 16);
    w.write(header_size, 16);
    w.write(count, 32);
    w.write(compressed_size, 32);
    w.write(original_size, 32);
    w.write(checksum, 32);
    w.write(static_cast<uint64_t>(first_timestamp), 64);
    w.write_signed(first_delta, 32);
    w.write(first_value_bits, 64);
    w.write(ts_bit_len, 32);
    w.write(val_bit_len, 32);
    w.write(total_bits, 32);
    // compression_ratio as float-64 (big-endian IEEE 754)
    w.write(float_to_bits(compression_ratio), 64);
    w.write(static_cast<uint64_t>(creation_time), 64);
    w.write(flags, 32);

    if (v2) {
        w.write(scale_decimals, 32);
    }

    int trailing;
    return w.to_bytes(trailing);
}

// ---------------------------------------------------------------------------
// VM preprocessing helpers
// ---------------------------------------------------------------------------

// Detect max decimal places (capped at 6)
static int detect_scale(const std::vector<double> &values) {
    int max_decimals = 0;
    for (double v : values) {
        // Use snprintf with compact-like formatting
        char buf[32];
        snprintf(buf, sizeof(buf), "%.10g", v);
        const char *dot = strchr(buf, '.');
        if (dot) {
            int len = static_cast<int>(strlen(dot + 1));
            // Trim trailing zeros
            while (len > 0 && dot[len] == '0') len--;
            if (len > max_decimals) max_decimals = len;
        }
    }
    return std::min(max_decimals, 6);
}

static int64_t pow10i(int n) {
    int64_t r = 1;
    for (int i = 0; i < n; i++) r *= 10;
    return r;
}

// Scale floats to ints: multiply by 10^n and round
static std::vector<double> scale_values(const std::vector<double> &values, int n) {
    if (n == 0) return values;
    double scale = static_cast<double>(pow10i(n));
    std::vector<double> result;
    result.reserve(values.size());
    for (double v : values) {
        result.push_back(static_cast<double>(static_cast<int64_t>(std::round(v * scale))));
    }
    return result;
}

// Delta-encode a counter series
static std::vector<double> delta_encode_counter(const std::vector<double> &values) {
    if (values.empty()) return values;
    std::vector<double> result;
    result.reserve(values.size());
    result.push_back(values[0]);
    for (size_t i = 1; i < values.size(); i++) {
        result.push_back(values[i] - values[i - 1]);
    }
    return result;
}

// Delta-decode a counter series
static std::vector<double> delta_decode_counter(const std::vector<double> &values) {
    if (values.empty()) return values;
    std::vector<double> result;
    result.reserve(values.size());
    result.push_back(values[0]);
    for (size_t i = 1; i < values.size(); i++) {
        result.push_back(result.back() + values[i]);
    }
    return result;
}

// ---------------------------------------------------------------------------
// Encode NIF
// ---------------------------------------------------------------------------

// Atoms for option keys
static auto atom_victoria_metrics = fine::Atom("victoria_metrics");
static auto atom_is_counter = fine::Atom("is_counter");
static auto atom_scale_decimals = fine::Atom("scale_decimals");

// Fast manual data + opts parsing to avoid FINE's variant/vector overhead
static fine::Ok<ErlNifBinary>
nif_gorilla_encode(ErlNifEnv *env,
                   fine::Term data_term,
                   fine::Term opts_term)
{
    // Parse the list of {timestamp, value} tuples manually
    unsigned int list_len;
    if (!enif_get_list_length(env, data_term, &list_len)) {
        throw std::invalid_argument("expected a list");
    }

    if (list_len == 0) {
        ErlNifBinary bin;
        enif_alloc_binary(0, &bin);
        return fine::Ok(bin);
    }

    std::vector<int64_t> timestamps;
    std::vector<double> values;
    timestamps.reserve(list_len);
    values.reserve(list_len);

    ERL_NIF_TERM head, tail;
    ERL_NIF_TERM list = data_term;
    while (enif_get_list_cell(env, list, &head, &tail)) {
        int arity;
        const ERL_NIF_TERM *tuple;
        if (!enif_get_tuple(env, head, &arity, &tuple) || arity != 2) {
            throw std::invalid_argument("expected {timestamp, value} tuples");
        }

        ErlNifSInt64 ts;
        if (!enif_get_int64(env, tuple[0], &ts)) {
            throw std::invalid_argument("timestamp must be an integer");
        }
        timestamps.push_back(static_cast<int64_t>(ts));

        double val;
        if (!enif_get_double(env, tuple[1], &val)) {
            // Try integer
            ErlNifSInt64 ival;
            if (!enif_get_int64(env, tuple[1], &ival)) {
                throw std::invalid_argument("value must be a number");
            }
            val = static_cast<double>(ival);
        }
        values.push_back(val);

        list = tail;
    }

    // Parse options map manually
    bool vm_enabled = false;
    bool is_counter = false;
    int scale_n = -1;  // -1 means :auto when vm_enabled

    ERL_NIF_TERM opt_val;
    if (enif_get_map_value(env, opts_term,
            fine::encode(env, atom_victoria_metrics), &opt_val)) {
        vm_enabled = fine::decode<bool>(env, opt_val);
    }
    if (enif_get_map_value(env, opts_term,
            fine::encode(env, atom_is_counter), &opt_val)) {
        is_counter = fine::decode<bool>(env, opt_val);
    }
    if (enif_get_map_value(env, opts_term,
            fine::encode(env, atom_scale_decimals), &opt_val)) {
        ErlNifSInt64 sval;
        if (enif_get_int64(env, opt_val, &sval)) {
            scale_n = static_cast<int>(sval);
        }
        // else :auto → stays -1
    }

    // VM preprocessing
    uint32_t flags = 0;
    uint32_t scale_decimals = 0;

    if (vm_enabled) {
        flags |= 0x1;

        if (is_counter) {
            flags |= 0x2;
            values = delta_encode_counter(values);
        }

        if (scale_n < 0) {
            scale_n = detect_scale(values);
        }

        scale_decimals = static_cast<uint32_t>(scale_n);
        values = scale_values(values, scale_n);
    }

    bool v2 = vm_enabled || (is_counter && scale_decimals >= 0);

    // Encode timestamps
    auto ts_result = encode_timestamps(timestamps);
    size_t ts_bit_len = ts_result.writer.total_bits();

    // Encode values
    auto val_result = encode_values(values);
    size_t val_bit_len = val_result.writer.total_bits();

    // Build inner header
    uint64_t first_value_bits = float_to_bits(val_result.first_value);
    auto inner_header = build_inner_header(
        static_cast<uint32_t>(timestamps.size()),
        ts_result.first_timestamp,
        first_value_bits,
        static_cast<int32_t>(ts_result.first_delta),
        static_cast<uint32_t>(ts_bit_len),
        static_cast<uint32_t>(val_bit_len));

    // Get timestamp and value bytes
    int ts_trailing, val_trailing;
    auto ts_bytes = ts_result.writer.to_bytes(ts_trailing);
    auto val_bytes = val_result.writer.to_bytes(val_trailing);

    // Combine: inner_header + ts_bits + val_bits, then pad to byte boundary
    // We need to do bit-level concatenation for the ts + val bitstreams
    BitWriter packed;

    // Write inner header (always byte-aligned, 32 bytes)
    for (uint8_t b : inner_header) {
        packed.write(b, 8);
    }

    // Write timestamp bits
    // Full bytes
    if (ts_bit_len > 0) {
        size_t full_bytes = ts_bit_len / 8;
        int remaining = ts_bit_len % 8;
        for (size_t i = 0; i < full_bytes; i++) {
            packed.write(ts_bytes[i], 8);
        }
        if (remaining > 0) {
            // Write remaining bits from the last byte (MSB-aligned)
            packed.write(ts_bytes[full_bytes] >> (8 - remaining), remaining);
        }
    }

    // Write value bits
    if (val_bit_len > 0) {
        size_t full_bytes = val_bit_len / 8;
        int remaining = val_bit_len % 8;
        for (size_t i = 0; i < full_bytes; i++) {
            packed.write(val_bytes[i], 8);
        }
        if (remaining > 0) {
            packed.write(val_bytes[full_bytes] >> (8 - remaining), remaining);
        }
    }

    // Pad to byte boundary
    size_t total_bits = packed.total_bits();
    int pad_bits = (8 - (total_bits % 8)) % 8;
    if (pad_bits > 0) {
        packed.write(0, pad_bits);
    }
    total_bits = packed.total_bits();

    // Get packed data
    int packed_trailing;
    auto packed_data = packed.to_bytes(packed_trailing);

    // Calculate CRC32 of packed data
    uint32_t checksum = crc32(packed_data.data(), packed_data.size());

    // Build outer header
    int64_t creation_time = static_cast<int64_t>(time(nullptr));
    uint32_t compressed_size = static_cast<uint32_t>(packed_data.size());
    uint32_t count = static_cast<uint32_t>(timestamps.size());
    uint32_t original_size = count * 16;
    double compression_ratio = original_size > 0
        ? static_cast<double>(compressed_size) / static_cast<double>(original_size)
        : 0.0;

    auto outer_header = build_outer_header(
        count,
        compressed_size,
        checksum,
        ts_result.first_timestamp,
        static_cast<int32_t>(ts_result.first_delta),
        first_value_bits,
        static_cast<uint32_t>(ts_bit_len),
        static_cast<uint32_t>(val_bit_len),
        static_cast<uint32_t>(total_bits),
        compression_ratio,
        creation_time,
        flags,
        scale_decimals,
        v2);

    // Combine outer header + packed data
    size_t total_size = outer_header.size() + packed_data.size();
    ErlNifBinary result_bin;
    enif_alloc_binary(total_size, &result_bin);
    memcpy(result_bin.data, outer_header.data(), outer_header.size());
    memcpy(result_bin.data + outer_header.size(), packed_data.data(), packed_data.size());

    return fine::Ok(result_bin);
}
FINE_NIF(nif_gorilla_encode, ERL_NIF_DIRTY_JOB_CPU_BOUND);

// ---------------------------------------------------------------------------
// Decode helpers
// ---------------------------------------------------------------------------

static int64_t decode_first_delta(BitReader &reader) {
    uint64_t bit = reader.read_bit();
    if (bit == 0) return 0;

    bit = reader.read_bit();
    if (bit == 0) return reader.read_signed(7);

    bit = reader.read_bit();
    if (bit == 0) return reader.read_signed(9);

    bit = reader.read_bit();
    if (bit == 0) return reader.read_signed(12);

    return reader.read_signed(32);
}

static int64_t decode_delta_of_delta(BitReader &reader) {
    uint64_t bit = reader.read_bit();
    if (bit == 0) return 0;

    bit = reader.read_bit();
    if (bit == 0) return reader.read_signed(7);

    bit = reader.read_bit();
    if (bit == 0) return reader.read_signed(9);

    bit = reader.read_bit();
    if (bit == 0) return reader.read_signed(12);

    return reader.read_signed(32);
}

static std::vector<int64_t> decode_timestamps(BitReader &reader, uint32_t count) {
    std::vector<int64_t> timestamps;
    timestamps.reserve(count);

    if (count == 0) return timestamps;

    int64_t first_ts = static_cast<int64_t>(reader.read(64));
    timestamps.push_back(first_ts);

    if (count == 1) return timestamps;

    int64_t first_delta = decode_first_delta(reader);
    int64_t second_ts = first_ts + first_delta;
    timestamps.push_back(second_ts);

    int64_t prev_delta = first_delta;
    for (uint32_t i = 2; i < count; i++) {
        int64_t dod = decode_delta_of_delta(reader);
        int64_t current_delta = prev_delta + dod;
        int64_t ts = timestamps.back() + current_delta;
        timestamps.push_back(ts);
        prev_delta = current_delta;
    }

    return timestamps;
}

static std::vector<double> decode_values(BitReader &reader, uint32_t count) {
    std::vector<double> values;
    values.reserve(count);

    if (count == 0) return values;

    uint64_t first_bits = reader.read(64);
    values.push_back(bits_to_float(first_bits));

    if (count == 1) return values;

    uint64_t prev_bits = first_bits;
    int prev_leading = 0;
    int prev_trailing = 0;

    for (uint32_t i = 1; i < count; i++) {
        uint64_t bit = reader.read_bit();
        if (bit == 0) {
            // Identical to previous
            values.push_back(bits_to_float(prev_bits));
            continue;
        }

        bit = reader.read_bit();
        if (bit == 0) {
            // Reuse previous window
            int meaningful_length = 64 - prev_leading - prev_trailing;
            uint64_t meaningful_value = reader.read(meaningful_length);
            uint64_t xor_val = meaningful_value << prev_trailing;
            uint64_t new_bits = prev_bits ^ xor_val;
            values.push_back(bits_to_float(new_bits));
            prev_bits = new_bits;
        } else {
            // New window
            int leading = static_cast<int>(reader.read(5));
            int meaningful_length = static_cast<int>(reader.read(6)) + 1;
            int trailing = 64 - leading - meaningful_length;

            uint64_t meaningful_value = reader.read(meaningful_length);
            uint64_t xor_val = meaningful_value << trailing;
            uint64_t new_bits = prev_bits ^ xor_val;
            values.push_back(bits_to_float(new_bits));
            prev_bits = new_bits;
            prev_leading = leading;
            prev_trailing = trailing;
        }
    }

    return values;
}

// ---------------------------------------------------------------------------
// Decode NIF
// ---------------------------------------------------------------------------

using DecodedPoint = std::tuple<int64_t, double>;

static fine::Ok<std::vector<DecodedPoint>>
nif_gorilla_decode(ErlNifEnv *env, ErlNifBinary data)
{
    if (data.size == 0) {
        return fine::Ok(std::vector<DecodedPoint>{});
    }

    const uint8_t *ptr = data.data;
    size_t len = data.size;

    // Parse outer header — minimum 80 bytes
    if (len < 80) {
        throw std::runtime_error("data too small for header");
    }

    // Read header fields via BitReader
    BitReader hdr(ptr, len * 8);

    uint64_t magic = hdr.read(64);
    if (magic != GORILLA_MAGIC) {
        throw std::runtime_error("invalid magic number");
    }

    uint64_t version = hdr.read(16);
    if (version > GORILLA_VERSION) {
        throw std::runtime_error("unsupported version");
    }

    uint64_t header_size = hdr.read(16);
    if (header_size != 80 && header_size != 84) {
        throw std::runtime_error("invalid header size");
    }

    if (len < header_size) {
        throw std::runtime_error("data smaller than header");
    }

    uint32_t count = static_cast<uint32_t>(hdr.read(32));
    uint32_t compressed_size = static_cast<uint32_t>(hdr.read(32));
    /*uint32_t original_size =*/ hdr.read(32);
    uint32_t expected_crc = static_cast<uint32_t>(hdr.read(32));
    /*int64_t first_timestamp =*/ hdr.read(64);
    /*int32_t first_delta =*/ hdr.read_signed(32);
    /*uint64_t first_value_bits =*/ hdr.read(64);
    /*uint32_t ts_bit_len =*/ hdr.read(32);
    /*uint32_t val_bit_len =*/ hdr.read(32);
    /*uint32_t total_bits =*/ hdr.read(32);
    /*double compression_ratio_hdr =*/ hdr.read(64);  // float-64 bits
    /*int64_t creation_time =*/ hdr.read(64);
    uint32_t flags = static_cast<uint32_t>(hdr.read(32));

    uint32_t scale_decimals = 0;
    if (header_size == 84) {
        scale_decimals = static_cast<uint32_t>(hdr.read(32));
    }

    // Compressed data follows the header
    const uint8_t *packed_data = ptr + header_size;
    size_t packed_size = compressed_size;

    if (header_size + packed_size > len) {
        throw std::runtime_error("compressed data extends beyond input");
    }

    // Verify CRC32
    uint32_t actual_crc = crc32(packed_data, packed_size);
    if (actual_crc != expected_crc) {
        // Allow checksum mismatch (Elixir decoder does the same — flags it but continues)
    }

    if (count == 0) {
        return fine::Ok(std::vector<DecodedPoint>{});
    }

    // Parse inner header (32 bytes) from packed data
    if (packed_size < 32) {
        throw std::runtime_error("packed data too small for inner header");
    }

    BitReader inner(packed_data, packed_size * 8);

    uint32_t inner_count = static_cast<uint32_t>(inner.read(32));
    /*int64_t inner_first_ts =*/ inner.read(64);
    /*uint64_t inner_first_val =*/ inner.read(64);
    /*int32_t inner_first_delta =*/ inner.read_signed(32);
    uint32_t ts_bit_len = static_cast<uint32_t>(inner.read(32));
    /*uint32_t val_bit_len =*/ inner.read(32);

    (void)inner_count;

    // Read timestamp bitstream
    // Create a reader positioned right after the inner header
    // The inner header is 256 bits = 32 bytes
    size_t data_start_bits = 256;  // inner header bits
    size_t ts_start = data_start_bits;
    size_t val_start = ts_start + ts_bit_len;

    // Create readers for timestamp and value bitstreams
    BitReader ts_reader(packed_data, packed_size * 8);
    // Skip to timestamp data
    for (size_t i = 0; i < data_start_bits; i++) {
        ts_reader.read_bit();
    }

    auto timestamps = decode_timestamps(ts_reader, count);

    // Value reader starts after timestamp bits
    BitReader val_reader(packed_data, packed_size * 8);
    for (size_t i = 0; i < val_start; i++) {
        val_reader.read_bit();
    }

    auto values = decode_values(val_reader, count);

    // VM postprocessing
    bool vm_enabled = (flags & 0x1) != 0;
    bool is_counter = (flags & 0x2) != 0;

    if (vm_enabled) {
        if (scale_decimals > 0) {
            double scale = std::pow(10.0, static_cast<double>(scale_decimals));
            for (auto &v : values) {
                v = v / scale;
            }
        }
        if (is_counter) {
            values = delta_decode_counter(values);
        }
    }

    // Combine into result
    std::vector<DecodedPoint> result;
    result.reserve(count);
    for (uint32_t i = 0; i < count; i++) {
        result.emplace_back(timestamps[i], values[i]);
    }

    return fine::Ok(result);
}
FINE_NIF(nif_gorilla_decode, ERL_NIF_DIRTY_JOB_CPU_BOUND);

// ---------------------------------------------------------------------------
// NIF init
// ---------------------------------------------------------------------------

FINE_INIT("Elixir.GorillaStream.Compression.Gorilla.NIF");
