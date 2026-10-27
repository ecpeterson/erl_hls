#ifndef HLS_TEST_FRAMED_FIFO_STREAM_H
#define HLS_TEST_FRAMED_FIFO_STREAM_H

#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <fcntl.h>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

// One bounded host FIFO pair carrying little-endian route/header/payload words.
// The header's low byte is the payload word count. Simulation owns the held beat;
// pump() performs nonblocking OS I/O and sample() advances only accepted handshakes.
class FramedFifoStream {
public:
    uint32_t word = 0;
    bool valid = false, last = false;
    uint64_t inputs = 0, outputs = 0, stalls = 0;

    // Require fresh FIFO and trace names; retain files after closure as witness evidence.
    explicit FramedFifoStream(const std::string& prefix) {
        try {
            if (mkfifo((prefix + "_tx").c_str(), 0600) ||
                mkfifo((prefix + "_rx").c_str(), 0600))
                throw std::runtime_error("fresh FIFO creation failed");
            input = open((prefix + "_tx").c_str(), O_RDWR | O_NONBLOCK);
            output = open((prefix + "_rx").c_str(), O_RDWR | O_NONBLOCK);
            trace = fopen((prefix + "-words.log").c_str(), "wx");
            if (input < 0 || output < 0 || !trace)
                throw std::runtime_error("FIFO open failed");
        } catch (...) {
            close_files();
            throw;
        }
    }

    // Each stream uniquely owns its OS descriptors and accepted-word trace.
    FramedFifoStream(const FramedFifoStream&) = delete;
    FramedFifoStream& operator=(const FramedFifoStream&) = delete;
    ~FramedFifoStream() { close_files(); }

    // Preserve the witnesses' original output headroom before asserting public ready.
    bool output_ready() const { return tx.size() < capacity - word_bytes; }

    // An accepted partial frame remains pending even without a currently held word.
    bool input_pending() const { return valid || !rx.empty() || phase != 0; }

    // Count buffered bytes separately from the public word already removed from the queue.
    size_t pending_input_bytes() const { return rx.size(); }

    // Partial OS reads/writes never change the held public beat; queues stay at most 64 KiB.
    void pump() {
        uint8_t bytes[4096];
        if (rx.size() + sizeof(bytes) <= capacity) {
            ssize_t n = read(input, bytes, sizeof(bytes));
            if (n > 0) rx.insert(rx.end(), bytes, bytes + n);
            else if (n < 0 && errno != EAGAIN && errno != EINTR)
                throw std::runtime_error("FIFO read");
        }
        size_t count = std::min(tx.size(), sizeof(bytes));
        for (size_t i = 0; i < count; i++) bytes[i] = tx[i];
        if (count) {
            ssize_t n = write(output, bytes, count);
            if (n > 0) for (ssize_t i = 0; i < n; i++) tx.pop_front();
            else if (n < 0 && errno != EAGAIN && errno != EINTR)
                throw std::runtime_error("FIFO write");
        }
        if (!valid && rx.size() >= word_bytes) {
            word = 0;
            for (unsigned i = 0; i < word_bytes; i++) {
                word |= uint32_t(rx.front()) << (8 * i);
                rx.pop_front();
            }
            valid = true;
            if (phase == 0) { last = false; phase = 1; }
            else if (phase == 1) {
                remaining = word & 255;
                last = remaining == 0;
                phase = last ? 0 : 2;
            } else {
                last = --remaining == 0;
                if (last) phase = 0;
            }
        }
    }

    // Reject unstable stalled output and trace only words accepted at this clock edge.
    void sample(bool in_ready, uint32_t out_word, bool out_valid, bool out_last,
                bool out_ready, uint64_t cycle) {
        if (blocked && (!out_valid || out_word != prior || out_last != prior_last))
            throw std::runtime_error("stalled output changed");
        blocked = out_valid && !out_ready;
        prior = out_word;
        prior_last = out_last;
        if (blocked) stalls++;
        if (valid && in_ready) {
            fprintf(trace, "I %llu %08x %u\n", (unsigned long long)cycle, word, last);
            inputs++;
            valid = false;
        }
        if (out_valid && out_ready) {
            if (tx.size() > capacity - word_bytes) throw std::runtime_error("output capacity");
            fprintf(trace, "O %llu %08x %u\n", (unsigned long long)cycle, out_word, out_last);
            outputs++;
            for (unsigned i = 0; i < word_bytes; i++) tx.push_back(uint8_t(out_word >> (8 * i)));
        }
    }

private:
    static constexpr size_t capacity = 65536, word_bytes = 4;
    int input = -1, output = -1;
    std::deque<uint8_t> rx, tx;
    unsigned phase = 0, remaining = 0;
    uint32_t prior = 0;
    bool blocked = false, prior_last = false;
    FILE* trace = nullptr;

    // Constructor failure and normal destruction both release every acquired descriptor.
    void close_files() {
        if (input >= 0) close(input);
        if (output >= 0) close(output);
        if (trace) fclose(trace);
    }
};

#endif
