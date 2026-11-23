// Standalone wire-transport tests: native semantics belong to the Erlang validators.
#include "spacetime_trace.h"
#include <filesystem>
#include <functional>
#include <iterator>

// A failed transport obligation must stop the executable with a useful label.
static void require(bool condition, const std::string& label) {
    if (!condition) throw std::runtime_error("test_" + label);
}

// Every deliberately corrupt recording must fail before claiming complete coverage.
static void rejects(const std::string& label, const std::function<void()>& action) {
    try { action(); }
    catch (const std::runtime_error&) { return; }
    throw std::runtime_error("accepted_" + label);
}

// Retain bounded fixture text, including broken footer bytes, for failure diagnosis.
static std::string read(const std::string& path) {
    std::ifstream input(path);
    if (!input) throw std::runtime_error("fixture_read");
    return std::string(std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>());
}

// Test fixtures must never overwrite previous evidence from another execution.
static void write_fresh(const std::string& path, const std::string& text) {
    FILE* file = std::fopen(path.c_str(), "wx");
    if (!file) throw std::runtime_error("fresh_fixture_open");
    bool ok = std::fwrite(text.data(), 1, text.size(), file) == text.size();
    ok = std::fclose(file) == 0 && ok;
    require(ok, "fixture_write");
}

// Exhaustion authenticates the footer; merely accepting the first row does not.
static void consume(const std::string& path) {
    spacetime::Reader reader(path);
    uint64_t cycle;
    spacetime::Values sample;
    while (reader.next(cycle, sample)) {}
}

// Replace one selected TSV field while retaining all delimiters and the newline.
static std::string replace_field(const std::string& text, size_t row, size_t field,
                                 const std::string& value) {
    size_t start = row;
    for (size_t i = 0; i < field; ++i) {
        start = text.find('\t', start);
        if (start == std::string::npos) throw std::runtime_error("fixture_field");
        ++start;
    }
    size_t end = text.find_first_of("\t\n", start);
    if (end == std::string::npos) throw std::runtime_error("fixture_field_end");
    return text.substr(0, start) + value + text.substr(end);
}

// One fresh directory retains the valid fixture and each deliberately broken variant.
int main(int argc, char** argv) {
    try {
        if (argc != 2 || !std::filesystem::is_directory(argv[1]))
            throw std::runtime_error("usage_header_tests_FRESH_DIRECTORY");
        std::string dir = argv[1];
        const std::vector<spacetime::Tap> taps = {
            {"left", 8, "TOP.dut.shared"}, {"right", 8, "TOP.dut.shared"}
        };
        spacetime::Values repeated = {"0", "1", "ab", "0", "1", "1", "1", "ef", "1", "0", "1", "ff", "ff"};
        auto changed = repeated;
        changed[2] = "cd";
        {
            spacetime::Writer writer(dir + "/valid.tsv", taps);
            for (uint64_t cycle = 0; cycle < 3; ++cycle) writer.append(cycle, repeated);
            writer.append(3, changed);
            require(writer.records() == 2, "rle_row_count");
            writer.finish(true, "ok");
        }
        {
            spacetime::Reader reader(dir + "/valid.tsv");
            uint64_t cycle = 0, count = 0;
            spacetime::Values sample;
            while (reader.next(cycle, sample)) {
                require(cycle == count, "expanded_cycle");
                require(sample == (count < 3 ? repeated : changed), "expanded_value");
                ++count;
            }
            require(count == 4, "repeated_active_transactions");
            require(reader.taps().size() == 2, "shared_tap_aliases");
        }
        rejects("duplicate_id", [&] {
            auto bad = taps;
            bad[1].id = bad[0].id;
            spacetime::Writer writer(dir + "/duplicate.tsv", bad);
        });
        rejects("shared_width", [&] {
            auto bad = taps;
            bad[1].width = 16;
            spacetime::Writer writer(dir + "/shared-width.tsv", bad);
        });
        rejects("public_id", [&] {
            auto bad = taps;
            bad[0].id = "reset";
            spacetime::Writer writer(dir + "/public-id.tsv", bad);
        });
        std::string valid = read(dir + "/valid.tsv");
        size_t footer = valid.rfind("\nF\t") + 1;
        size_t first = valid.find("\nS\t") + 1;
        size_t second = valid.find("\nS\t", first) + 1;
        require(footer && first && second, "fixture_rows");
        const std::vector<std::pair<std::string, std::string>> corrupt = {
            {"missing-footer", valid.substr(0, footer)},
            {"unterminated-footer", valid.substr(0, valid.size() - 1)},
            {"false-record-count", replace_field(valid, footer, 4, "3")},
            {"overlap", replace_field(valid, second, 1, "2")},
            {"out-of-horizon", replace_field(valid, first, 2, "4000001")},
            {"invalid-bit", replace_field(valid, first, 3, "2")},
            {"trailing-data", valid + "S\t4\t1\n"},
            {"false-decoded-count", replace_field(valid, footer, 5, "4096")}
        };
        for (const auto& [name, text] : corrupt) {
            std::string path = dir + "/" + name + ".tsv";
            write_fresh(path, text);
            rejects(name, [&] { consume(path); });
        }
        {
            spacetime::Writer writer(dir + "/abandoned.tsv", taps);
            writer.append(0, repeated);
        }
        rejects("abandoned_incomplete", [&] { consume(dir + "/abandoned.tsv"); });
        std::printf("PASS spacetime trace transport: RLE/shared-path roundtrip and 12 rejecting cases\n");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "FAIL spacetime trace transport: %s\n", error.what());
        return 1;
    }
}
