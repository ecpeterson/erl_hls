// Host-only finite checks of the same FIFO bridge used by public-port RTL witnesses.
#include "framed_fifo_stream.h"
#include <array>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <vector>

// Keep assertions active regardless of the host compiler's NDEBUG setting.
static void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

// Small nonblocking writes exercise the real FIFO path without a simulator or another thread.
static void send_bytes(int fd, const std::vector<uint8_t>& bytes) {
    require(write(fd, bytes.data(), bytes.size()) == ssize_t(bytes.size()), "host FIFO write");
}

// A fragmented route, empty payload, and two-word payload retain their original frame boundaries.
static void input_frames(const std::string& prefix) {
    {
        FramedFifoStream stream(prefix);
        int host = open((prefix + "_tx").c_str(), O_WRONLY | O_NONBLOCK);
        require(host >= 0, "host input open");
        send_bytes(host, {0x44});
        stream.pump();
        require(!stream.valid && stream.input_pending(), "partial input word");
        send_bytes(host, {0x33, 0x22, 0x11, 0, 0, 0, 0,
            0x88, 0x77, 0x66, 0x55, 2, 0, 0, 0,
            0x04, 0x03, 0x02, 0x01, 0x08, 0x07, 0x06, 0x05});
        stream.pump();
        require(stream.valid && stream.word == 0x11223344 && !stream.last, "input endian order");
        for (unsigned i = 0; i < 3; i++) {
            stream.sample(false, 0, false, false, true, i);
            stream.pump();
            require(stream.valid && stream.word == 0x11223344 && !stream.last, "held input beat");
        }
        const std::array<uint32_t, 6> words{0x11223344, 0, 0x55667788, 2, 0x01020304, 0x05060708};
        const std::array<bool, 6> lasts{false, true, false, false, false, true};
        for (size_t i = 0; i < words.size(); i++) {
            stream.pump();
            require(stream.valid && stream.word == words[i] && stream.last == lasts[i], "input frame boundary");
            stream.sample(true, 0, false, false, true, 10 + i);
            require(stream.input_pending() == (i + 1 < words.size()), "input completion");
        }
        require(stream.inputs == 6 && stream.outputs == 0, "input accepted counts");
        close(host);
    }
    std::ifstream trace(prefix + "-words.log");
    std::string bytes((std::istreambuf_iterator<char>(trace)), std::istreambuf_iterator<char>());
    require(bytes == "I 10 11223344 0\nI 11 00000000 1\nI 12 55667788 0\n"
                     "I 13 00000002 0\nI 14 01020304 0\nI 15 05060708 1\n", "accepted input trace");
}

// Only accepted output enters the host FIFO; a stall may cover several pump calls.
static void output_words(const std::string& prefix) {
    FramedFifoStream stream(prefix);
    int host = open((prefix + "_rx").c_str(), O_RDONLY | O_NONBLOCK);
    require(host >= 0, "host output open");
    stream.sample(false, 0x78563412, true, true, false, 0);
    stream.pump();
    uint8_t bytes[4];
    require(read(host, bytes, sizeof(bytes)) == -1 && errno == EAGAIN, "stalled word leaked");
    stream.sample(false, 0x78563412, true, true, false, 1);
    stream.sample(false, 0x78563412, true, true, true, 2);
    stream.pump();
    require(read(host, bytes, sizeof(bytes)) == 4, "accepted output absent");
    require(std::vector<uint8_t>(bytes, bytes + 4) == std::vector<uint8_t>({0x12, 0x34, 0x56, 0x78}),
        "output endian order");
    require(stream.stalls == 2 && stream.outputs == 1 && stream.inputs == 0, "output accepted counts");
    close(host);
}

// Data, last, and valid are all stable obligations until a held output is accepted.
static void unstable_output(const std::string& prefix, uint32_t word, bool valid, bool last) {
    FramedFifoStream stream(prefix);
    stream.sample(false, 37, true, true, false, 0);
    try {
        stream.sample(false, word, valid, last, true, 1);
    } catch (const std::runtime_error& error) {
        require(std::string(error.what()) == "stalled output changed", "unexpected stall error");
        return;
    }
    throw std::runtime_error("unstable output accepted");
}

// Bounded buffering withdraws ready before overflow; even an illegal extra acceptance fails closed.
static void output_capacity(const std::string& prefix) {
    FramedFifoStream stream(prefix);
    for (unsigned i = 0; i < 16384; i++) {
        require(stream.output_ready() == (i < 16383), "output headroom");
        stream.sample(false, i, true, i == 16383, true, i);
    }
    require(!stream.output_ready(), "full queue ready");
    try {
        stream.sample(false, 0, true, true, true, 16384);
    } catch (const std::runtime_error& error) {
        require(std::string(error.what()) == "output capacity", "unexpected capacity error");
        stream.pump();
        require(stream.output_ready() && stream.outputs == 16384, "drained output headroom");
        return;
    }
    throw std::runtime_error("output overflow accepted");
}

// Retain all FIFO files and traces in one fresh caller-supplied evidence directory.
int main(int argc, char** argv) {
    if (argc != 2) return 2;
    try {
        const std::string root = argv[1];
        require(std::filesystem::create_directory(root), "fresh evidence directory");
        input_frames(root + "/input");
        output_words(root + "/output");
        unstable_output(root + "/changed-word", 38, true, true);
        unstable_output(root + "/changed-last", 37, true, false);
        unstable_output(root + "/withdrawn-valid", 37, false, true);
        output_capacity(root + "/capacity");
        puts("PASS framed FIFO stream");
        return 0;
    } catch (const std::exception& error) {
        fprintf(stderr, "FAIL framed FIFO stream: %s\n", error.what());
        return 1;
    }
}
