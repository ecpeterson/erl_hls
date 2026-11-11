#include "Vdomain_stream.h"
#include "verilated.h"
#include "framed_fifo_stream.h"
#include <chrono>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <thread>
#include <unistd.h>

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

// All application selection, lifecycle decisions, sequencing, response frontiers,
// and packet contents come from synthesized RTL. This object only transfers words.
class Domain {
public:
    Vdomain_stream core;
    FramedFifoStream management, application;
    DeliveryControl management_delivery, application_delivery;

    explicit Domain(const std::string& prefix):
        core(prefix.c_str()), management(prefix + "_management"),
        application(prefix + "_application"),
        management_delivery(prefix + "_management_delivery"),
        application_delivery(prefix + "_application_delivery") {
        core.clk = 0;
        core.reset = 1;
        core.management_word = 0;
        core.management_valid = 0;
        core.management_last = 0;
        core.management_output_ready = 0;
        core.application_word = 0;
        core.application_valid = 0;
        core.application_last = 0;
        core.application_output_ready = 0;
        core.eval();
    }

    // Capture handshakes at the public edge before advancing either stream or RTL.
    void tick(uint64_t cycle) {
        if (cycle % 256 == 0) {
            management_delivery.poll();
            application_delivery.poll();
        }
        management.pump(management_delivery.enabled());
        application.pump(application_delivery.enabled());
        core.reset = cycle < 4;
        core.management_word = management.word;
        core.management_valid = management.valid;
        core.management_last = management.last;
        core.management_output_ready = management.output_ready();
        core.application_word = application.word;
        core.application_valid = application.valid;
        core.application_last = application.last;
        core.application_output_ready = application.output_ready();
        core.clk = 0;
        core.eval();
        management.sample(core.management_ready, core.management_output_word,
            core.management_output_valid, core.management_output_last,
            core.management_output_ready, cycle);
        application.sample(core.application_ready, core.application_output_word,
            core.application_output_valid, core.application_output_last,
            core.application_output_ready, cycle);
        core.clk = 1;
        core.eval();
    }
};

// Both independent cores advance on every edge; one paused byte stream cannot
// stop its peer or management lane. Limits bound this finite simulation witness.
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc != 2) return 2;
    const std::string directory = argv[1];
    try {
        Domain a(directory + "/domain0"), b(directory + "/domain1");
        auto start = std::chrono::steady_clock::now();
        uint64_t finish = 0;
        for (uint64_t cycle = 0; cycle < 50000000; ++cycle) {
            a.tick(cycle);
            b.tick(cycle);
            if (cycle % 256 == 0) {
                if (!finish && access((directory + "/finished").c_str(), F_OK) == 0)
                    finish = cycle + 256;
                if (std::chrono::steady_clock::now() - start > std::chrono::seconds(60))
                    throw std::runtime_error("bounded stream witness timeout");
                std::this_thread::sleep_for(std::chrono::microseconds(500));
            }
            if (finish && cycle >= finish) {
                printf("PASS domain stream RTL: cycles=%llu; "
                       "A management=%llu/%llu application=%llu/%llu; "
                       "B management=%llu/%llu application=%llu/%llu\n",
                    (unsigned long long)cycle,
                    (unsigned long long)a.management.inputs, (unsigned long long)a.management.outputs,
                    (unsigned long long)a.application.inputs, (unsigned long long)a.application.outputs,
                    (unsigned long long)b.management.inputs, (unsigned long long)b.management.outputs,
                    (unsigned long long)b.application.inputs, (unsigned long long)b.application.outputs);
                return 0;
            }
        }
        throw std::runtime_error("bounded stream witness clock limit");
    } catch (const std::exception& failure) {
        fprintf(stderr, "FAIL domain stream RTL: %s\n", failure.what());
        return 1;
    }
}
