#ifndef HLS_SPACETIME_TRACE_H
#define HLS_SPACETIME_TRACE_H

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <limits>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

// Protocol-stream dialect: eleven fixed public fields plus producer-declared taps.
// Complete pre-edge samples, compressed only across identical consecutive cycles.
// An active repeated handshake remains one action on every cycle in its run.
namespace spacetime {
constexpr uint64_t max_cycles = 4000000;
constexpr uint64_t max_records = 1000000;
constexpr uint64_t max_decoded = 256ULL * 1024 * 1024;
constexpr size_t max_line = 1024 * 1024;
constexpr size_t public_fields = 11;
const std::string header = "H\tspacetime_cycle_trace\t1";
const std::string public_header =
    "P\treset\tinput_valid\tinput_data\tinput_last\toutput_ready\tinput_ready"
    "\toutput_valid\toutput_data\toutput_last\tfault\trunning";

// VPI identity is recorded separately from values and checked before replay.
struct Tap {
    std::string id;
    uint32_t width;
    std::string path;
};

// One full sample in public-header order followed by tap declaration order.
using Values = std::vector<std::string>;

// Split TSV while preserving empty fields for the validator to reject.
inline std::vector<std::string> fields(const std::string& line) {
    std::vector<std::string> result;
    size_t start = 0;
    for (;;) {
        size_t end = line.find('\t', start);
        result.push_back(line.substr(start, end == std::string::npos ? end : end - start));
        if (end == std::string::npos) return result;
        start = end + 1;
    }
}

// Decimal counters have one spelling and never accept signs or overflow.
inline uint64_t decimal(const std::string& text) {
    if (text.empty() || (text.size() > 1 && text.front() == '0'))
        throw std::runtime_error("invalid_decimal");
    uint64_t value = 0;
    for (char c : text) {
        if (c < '0' || c > '9' || value > (std::numeric_limits<uint64_t>::max() - (c - '0')) / 10)
            throw std::runtime_error("invalid_decimal");
        value = value * 10 + c - '0';
    }
    return value;
}

// IDs and paths occupy one nonempty printable ASCII TSV field.
inline void text_field(const std::string& text) {
    if (text.empty() || text.size() > 4096)
        throw std::runtime_error("invalid_text_field");
    for (unsigned char c : text)
        if (c < 32 || c > 126 || c == '\t')
            throw std::runtime_error("invalid_text_field");
}

// Lowercase canonical hex avoids lossy numeric conversion for wide taps.
inline std::string hex(uint64_t value) {
    char buffer[17];
    std::snprintf(buffer, sizeof(buffer), "%llx", static_cast<unsigned long long>(value));
    return buffer;
}

// Check canonical spelling and exact declared bit width without wide host integers.
inline void hex_width(const std::string& value, uint32_t width) {
    if (value.empty() || value.size() > (width + 3ULL) / 4 ||
        (value.size() > 1 && value.front() == '0'))
        throw std::runtime_error("invalid_hex_width");
    for (char c : value)
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')))
            throw std::runtime_error("invalid_hex_value");
    unsigned first = value.front() <= '9' ? value.front() - '0' : value.front() - 'a' + 10;
    if (width % 4 && value.size() == (width + 3ULL) / 4 && first >= (1U << (width % 4)))
        throw std::runtime_error("invalid_hex_width");
}

// Public inputs/outputs are known fixed widths; each tap retains its own declaration.
inline void validate_values(const Values& values, const std::vector<Tap>& taps) {
    if (values.size() != public_fields + taps.size())
        throw std::runtime_error("sample_field_count");
    for (size_t i = 0; i < public_fields; ++i)
        hex_width(values[i], i == 2 || i == 7 ? 32 : 1);
    for (size_t i = 0; i < taps.size(); ++i)
        hex_width(values[public_fields + i], taps[i].width);
}

// Conservative decoded bound prices each expanded row, not compressed bytes.
inline uint64_t expanded_bytes(const Values& values) {
    uint64_t bytes = 32;
    for (const auto& value : values) bytes += value.size() + 1;
    return bytes;
}

// Error causes stay bounded single tokens so the footer remains easy to parse.
inline std::string cause_token(const std::string& cause) {
    std::string token;
    for (unsigned char c : cause.substr(0, 200))
        token += ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                  (c >= '0' && c <= '9') || c == '_' || c == '-') ? char(c) : '_';
    return token.empty() ? "unspecified" : token;
}

// Logical aliases may share a signal; IDs remain unique and shared widths must agree.
inline void validate_taps(const std::vector<Tap>& taps) {
    if (taps.size() > 4096) throw std::runtime_error("tap_count_limit");
    const auto public_names = fields(public_header);
    uint64_t width = 0;
    for (size_t i = 0; i < taps.size(); ++i) {
        const auto& tap = taps[i];
        text_field(tap.id);
        text_field(tap.path);
        if (std::find(public_names.begin() + 1, public_names.end(), tap.id) != public_names.end())
            throw std::runtime_error("public_tap_id");
        if (!tap.width || tap.width > 65536) throw std::runtime_error("tap_width_limit");
        width += (tap.width + 3ULL) / 4 + 1;
        if (width + 256 > max_line) throw std::runtime_error("sample_width_limit");
        for (size_t j = 0; j < i; ++j) {
            if (taps[j].id == tap.id) throw std::runtime_error("duplicate_tap_id");
            if (taps[j].path == tap.path && taps[j].width != tap.width)
                throw std::runtime_error("shared_tap_width");
        }
    }
}

// Read a newline-terminated bounded line; an unterminated tail is never a valid footer.
inline bool read_line(std::istream& input, std::string& line) {
    line.clear();
    char c;
    while (input.get(c)) {
        if (c == '\n') return true;
        if (line.size() == max_line) throw std::runtime_error("line_limit");
        line += c;
    }
    if (!input.eof()) throw std::runtime_error("read_error");
    if (!line.empty()) throw std::runtime_error("unterminated_line");
    return false;
}

// Fresh output owns its footer. Destruction records incomplete capture when possible.
class Writer {
public:
    Writer(const std::string& path, std::vector<Tap> taps) : taps_(std::move(taps)) {
        validate_taps(taps_);
        file_ = std::fopen(path.c_str(), "wx");
        if (!file_) throw std::runtime_error("fresh_trace_open");
        try {
            metadata(header);
            metadata(public_header);
            for (const auto& tap : taps_)
                metadata("T\t" + tap.id + "\t" + std::to_string(tap.width) + "\t" + tap.path);
        } catch (...) {
            std::fclose(file_);
            file_ = nullptr;
            throw;
        }
    }
    Writer(const Writer&) = delete;
    Writer& operator=(const Writer&) = delete;
    ~Writer() {
        if (file_) {
            try { finish(false, "writer_abandoned"); } catch (...) {}
            std::fclose(file_);
        }
    }

    // Appends one exact pre-edge sample. Limits reject before consuming its cycle.
    void append(uint64_t cycle, const Values& values) {
        if (finished_ || cycle != samples_) throw std::runtime_error("sample_order");
        if (cycle >= max_cycles) throw std::runtime_error("cycle_limit");
        validate_values(values, taps_);
        uint64_t bytes = expanded_bytes(values);
        if (decoded_ > max_decoded - bytes) throw std::runtime_error("decoded_limit");
        if (pending_count_ && values != pending_) flush();
        if (!pending_count_) {
            if (records_ == max_records) throw std::runtime_error("record_limit");
            pending_ = values;
            pending_first_ = cycle;
        }
        ++pending_count_;
        ++samples_;
        decoded_ += bytes;
    }

    // Footer covers the contiguous sampled prefix, even when the next cycle failed.
    void finish(bool complete, const std::string& cause) {
        if (finished_) return;
        flush();
        line("F\t" + std::to_string(samples_) + "\t" + (complete ? "complete" : "incomplete") +
             "\t" + std::to_string(samples_) + "\t" + std::to_string(records_) + "\t" +
             std::to_string(decoded_) + "\t" + cause_token(cause));
        if (std::fflush(file_)) throw std::runtime_error("trace_flush");
        finished_ = true;
    }

    uint64_t samples() const { return samples_; }
    uint64_t records() const { return records_ + (pending_count_ ? 1 : 0); }

private:
    FILE* file_ = nullptr;
    std::vector<Tap> taps_;
    Values pending_;
    uint64_t samples_ = 0, records_ = 0, decoded_ = 4096;
    uint64_t pending_first_ = 0, pending_count_ = 0;
    bool finished_ = false;

    // Metadata bytes join a conservative footer allowance in the decoded budget.
    void metadata(const std::string& text) {
        if (decoded_ + text.size() + 1 > max_decoded) throw std::runtime_error("metadata_limit");
        line(text);
        decoded_ += text.size() + 1;
    }
    // Every record is a complete line; I/O errors propagate to incomplete capture handling.
    void line(const std::string& text) {
        if (text.size() > max_line) throw std::runtime_error("line_limit");
        if (std::fwrite(text.data(), 1, text.size(), file_) != text.size() ||
            std::fputc('\n', file_) == EOF)
            throw std::runtime_error("trace_write");
    }
    // RLE changes representation only; first/count retain each accepted edge exactly.
    void flush() {
        if (!pending_count_) return;
        std::string text = "S\t" + std::to_string(pending_first_) + "\t" + std::to_string(pending_count_);
        for (const auto& value : pending_) text += "\t" + value;
        line(text);
        ++records_;
        pending_count_ = 0;
        pending_.clear();
    }
};

// Streaming replay reader checks complete coverage without allocating expanded runs.
class Reader {
public:
    explicit Reader(const std::string& path) : input_(path) {
        if (!input_) throw std::runtime_error("trace_read_open");
        std::string line;
        if (!read_line(input_, line) || line != header) throw std::runtime_error("trace_header");
        decoded_ += line.size() + 1;
        if (!read_line(input_, line) || line != public_header) throw std::runtime_error("public_header");
        decoded_ += line.size() + 1;
        while (read_line(input_, line)) {
            auto f = fields(line);
            if (f.front() != "T") { buffered_ = line; break; }
            if (f.size() != 4) throw std::runtime_error("tap_declaration");
            uint64_t width = decimal(f[2]);
            if (!width || width > 65536) throw std::runtime_error("tap_width_limit");
            taps_.push_back({f[1], static_cast<uint32_t>(width), f[3]});
            if (taps_.size() > 4096) throw std::runtime_error("tap_count_limit");
            decoded_ += line.size() + 1;
            if (decoded_ > max_decoded) throw std::runtime_error("decoded_limit");
        }
        validate_taps(taps_);
        if (buffered_.empty()) throw std::runtime_error("missing_footer");
    }

    const std::vector<Tap>& taps() const { return taps_; }
    uint64_t samples() const { return next_; }

    // Return one cycle's values; EOF is valid only after a verified complete footer.
    bool next(uint64_t& cycle, Values& values) {
        if (finished_) return false;
        if (!remaining_) read_record();
        if (finished_) return false;
        cycle = next_++;
        values = values_;
        --remaining_;
        return true;
    }

private:
    std::ifstream input_;
    std::vector<Tap> taps_;
    std::string buffered_;
    Values values_;
    uint64_t next_ = 0, remaining_ = 0, records_ = 0, decoded_ = 4096;
    bool finished_ = false;

    // Validate whole runs before exposing any values to the simulator.
    void read_record() {
        std::string line = std::move(buffered_);
        buffered_.clear();
        if (line.empty() && !read_line(input_, line)) throw std::runtime_error("missing_footer");
        auto f = fields(line);
        if (f.front() == "S") {
            if (f.size() != 3 + public_fields + taps_.size()) throw std::runtime_error("sample_field_count");
            uint64_t first = decimal(f[1]), count = decimal(f[2]);
            if (first != next_ || !count || first > max_cycles || count > max_cycles - first)
                throw std::runtime_error("sample_range");
            if (++records_ > max_records) throw std::runtime_error("record_limit");
            values_ = Values(f.begin() + 3, f.end());
            validate_values(values_, taps_);
            uint64_t bytes = expanded_bytes(values_);
            if (count > (max_decoded - decoded_) / bytes) throw std::runtime_error("decoded_limit");
            decoded_ += count * bytes;
            remaining_ = count;
        } else if (f.front() == "F") {
            if (f.size() != 7 || decimal(f[1]) != next_ || decimal(f[3]) != next_ ||
                decimal(f[4]) != records_ || decimal(f[5]) != decoded_)
                throw std::runtime_error("footer_counts");
            if (f[2] != "complete" || f[6] != "ok") throw std::runtime_error("incomplete_input");
            if (read_line(input_, line)) throw std::runtime_error("trailing_records");
            finished_ = true;
        } else {
            throw std::runtime_error("unexpected_record");
        }
    }
};
} // namespace spacetime
#endif
