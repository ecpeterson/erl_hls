#ifndef HLS_TEST_FRAMED_FIFO_CONTROL_H
#define HLS_TEST_FRAMED_FIFO_CONTROL_H
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <limits>
#include <stdexcept>
#include <string>

// A transport-only schedule control pauses host receipt after RTL acceptance.
// Accepted bytes remain in FramedFifoStream's bounded queue; capacity still
// backpressures the RTL. It does not parse, alter or manufacture a packet.
class DeliveryControl {
public:
    explicit DeliveryControl(const std::string& prefix): path(prefix) {}

    // The host atomically replaces a one-byte control file; the ack reports only
    // simulator transport policy, never hardware readiness or lifecycle state.
    void poll() {
        FILE* input = fopen((path + ".control").c_str(), "r");
        if (!input) return;
        int value = fgetc(input);
        fclose(input);
        if (value != '0' && value != '1') return;
        bool next = value == '0';
        if (known && next == delivery) return;
        delivery = next;
        known = true;
        FILE* output = fopen((path + ".ack").c_str(), "w");
        if (!output) throw std::runtime_error("delivery control acknowledgement");
        fputc(value, output);
        fclose(output);
    }

    bool enabled() const { return delivery; }

private:
    std::string path;
    bool delivery = true, known = false;
};

// One atomic decimal control request and an independently observed acknowledgement.
// Callers decide what real event constitutes completion; this helper has no RTL logic.
class GenerationControl {
public:
    explicit GenerationControl(const std::string& control_path): path(control_path) {}

    // A changed file requests one new generation; identical writes are idempotent.
    bool poll() {
        FILE* input = fopen((path + ".control").c_str(), "r");
        if (!input) return false;
        uint64_t value = 0;
        bool digits = false, trailing = false, valid = true;
        for (int c = fgetc(input); c != EOF; c = fgetc(input)) {
            if (c >= '0' && c <= '9' && !trailing) {
                uint64_t digit = uint64_t(c - '0');
                if (value > (std::numeric_limits<uint64_t>::max() - digit) / 10) valid = false;
                else value = value * 10 + digit;
                digits = true;
            } else if (std::isspace(static_cast<unsigned char>(c)) && digits) {
                trailing = true;
            } else {
                valid = false;
            }
        }
        fclose(input);
        if (!valid || !digits) throw std::runtime_error("invalid session control");
        if (known && value == requested) return false;
        requested = value;
        known = pending = true;
        return true;
    }

    uint64_t generation() const { return requested; }

    // Acknowledge only after the caller has observed the requested generation.
    void observe(uint64_t actual, bool attached) {
        if (!pending || !attached || actual != requested) return;
        FILE* output = fopen((path + ".ack").c_str(), "w");
        if (!output) throw std::runtime_error("session acknowledgement");
        fprintf(output, "%llu\n", (unsigned long long)actual);
        fclose(output);
        pending = false;
    }

private:
    std::string path;
    uint64_t requested = 0;
    bool known = false, pending = false;
};

#endif
