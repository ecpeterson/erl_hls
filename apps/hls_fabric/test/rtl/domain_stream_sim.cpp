#include "Vdomain_stream.h"
#include <memory>
#include <vector>
#include "verilated.h"
#include "framed_fifo_stream.h"
#include <chrono>
#include <cctype>
#include <cstdint>
#include <limits>
#include <memory>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <thread>
#include <unistd.h>

#include "framed_fifo_control.h"

// All application selection, lifecycle decisions, sequencing, response frontiers,
// and packet contents come from synthesized RTL. This object only transfers words.
class Domain {
public:
    Vdomain_stream core;
    std::unique_ptr<FramedFifoStream> management, application;
    DeliveryControl management_delivery, application_delivery;
    GenerationControl session_control, transport_control;
    std::string prefix;
    uint64_t transport_generation = 1, isolated_session = 0;
    uint64_t retired_management_inputs = 0, retired_management_outputs = 0;
    uint64_t retired_application_inputs = 0, retired_application_outputs = 0;
    bool transport_isolated = false;
    FILE* transport_trace = nullptr;

    explicit Domain(const std::string& prefix):
        core(prefix.c_str()), management(std::make_unique<FramedFifoStream>(prefix + "_management")),
        application(std::make_unique<FramedFifoStream>(prefix + "_application")),
        management_delivery(prefix + "_management_delivery"),
        application_delivery(prefix + "_application_delivery"),
        session_control(prefix + "_session"), transport_control(prefix + "_transport"), prefix(prefix) {
        transport_trace = fopen((prefix + ".transport.log").c_str(), "wx");
        if (!transport_trace) throw std::runtime_error("transport generation trace");
        core.clk = 0;
        core.reset = 1;
        core.transport_reset = 0;
        core.transport_session = 0;
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

    // Final counters and all earlier generation traces survive normal termination.
    ~Domain() {
        record_transport();
        if (transport_trace) fclose(transport_trace);
    }

    // Closing the old writers is the actual EOF boundary for blocked old readers.
    // New FIFO paths ensure those readers can never consume new-session bytes.
    void replace_transport(uint64_t generation) {
        if (generation < 2 || generation <= transport_generation)
            throw std::runtime_error("non-increasing transport generation");
        record_transport();
        retired_management_inputs += management->inputs;
        retired_management_outputs += management->outputs;
        retired_application_inputs += application->inputs;
        retired_application_outputs += application->outputs;
        management.reset();
        application.reset();
        transport_isolated = true;
        isolated_session = core.transport_session_observed;
        std::string current = prefix + "_transport" + std::to_string(generation);
        management = std::make_unique<FramedFifoStream>(current + "_management");
        application = std::make_unique<FramedFifoStream>(current + "_application");
        transport_generation = generation;
        transport_control.observe(generation, true);
    }

    // Account for retired streams without resetting their accepted-word counters.
    uint64_t management_inputs() const { return retired_management_inputs + management->inputs; }
    uint64_t management_outputs() const { return retired_management_outputs + management->outputs; }
    uint64_t application_inputs() const { return retired_application_inputs + application->inputs; }
    uint64_t application_outputs() const { return retired_application_outputs + application->outputs; }

    // This trace is transport evidence only; lifecycle evidence remains in public packets.
    void record_transport() {
        if (!transport_trace || !management || !application) return;
        fprintf(transport_trace, "%llu management=%llu/%llu application=%llu/%llu\n",
            (unsigned long long)transport_generation,
            (unsigned long long)management->inputs, (unsigned long long)management->outputs,
            (unsigned long long)application->inputs, (unsigned long long)application->outputs);
        fflush(transport_trace);
    }

    // Capture handshakes at the public edge before advancing either stream or RTL.
    void tick(uint64_t cycle) {
        bool boundary = false;
        if (cycle % 256 == 0) {
            management_delivery.poll();
            application_delivery.poll();
            if (cycle >= 4 && transport_control.poll())
                replace_transport(transport_control.generation());
            boundary = cycle >= 4 && session_control.poll();
            if (boundary) {
                transport_isolated = true;
                isolated_session = core.transport_session_observed;
                management->discard();
                application->discard();
            }
        }
        management->pump(management_delivery.enabled());
        application->pump(application_delivery.enabled());
        core.reset = cycle < 4;
        core.transport_reset = boundary;
        core.transport_session = session_control.generation();
        core.management_word = management->word;
        core.management_valid = management->valid && !transport_isolated;
        core.management_last = management->last;
        core.management_output_ready = management->output_ready() && !transport_isolated;
        core.application_word = application->word;
        core.application_valid = application->valid && !transport_isolated;
        core.application_last = application->last;
        core.application_output_ready = application->output_ready() && !transport_isolated;
        core.clk = 0;
        core.eval();
        management->sample(core.management_ready && !transport_isolated, core.management_output_word,
            core.management_output_valid && !transport_isolated, core.management_output_last,
            core.management_output_ready, cycle);
        application->sample(core.application_ready && !transport_isolated, core.application_output_word,
            core.application_output_valid && !transport_isolated, core.application_output_last,
            core.application_output_ready, cycle);
        core.clk = 1;
        core.eval();
        session_control.observe(core.transport_session_observed, core.transport_attached);
        if (core.transport_attached && core.transport_session_observed == session_control.generation() &&
            core.transport_session_observed > isolated_session)
            transport_isolated = false;
    }
};

// All independent cores advance on every edge; one paused byte stream cannot
// stop its peer or management lane. Limits bound this finite simulation witness.
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc != 2 && argc != 3) return 2;
    const std::string directory = argv[1];
    try {
        const unsigned count = argc == 3 ? std::stoul(argv[2]) : 2;
        if (count < 2 || count > 3) throw std::runtime_error("domain count outside witness bound");
        std::vector<std::unique_ptr<Domain>> domains;
        for (unsigned index = 0; index < count; ++index)
            domains.emplace_back(std::make_unique<Domain>(directory + "/domain" + std::to_string(index)));
        auto start = std::chrono::steady_clock::now();
        uint64_t finish = 0;
        for (uint64_t cycle = 0; cycle < 50000000; ++cycle) {
            for (auto& domain : domains) domain->tick(cycle);
            if (cycle % 256 == 0) {
                if (!finish && access((directory + "/finished").c_str(), F_OK) == 0)
                    finish = cycle + 256;
                if (std::chrono::steady_clock::now() - start > std::chrono::seconds(60))
                    throw std::runtime_error("bounded stream witness timeout");
                std::this_thread::sleep_for(std::chrono::microseconds(500));
            }
            if (finish && cycle >= finish) {
                printf("PASS domain stream RTL: cycles=%llu; domains=%u\n",
                    (unsigned long long)cycle, count);
                for (unsigned index = 0; index < count; ++index) {
                    const auto& domain = domains[index];
                    printf("domain%u management=%llu/%llu application=%llu/%llu\n", index,
                        (unsigned long long)domain->management_inputs(),
                        (unsigned long long)domain->management_outputs(),
                        (unsigned long long)domain->application_inputs(),
                        (unsigned long long)domain->application_outputs());
                }
                return 0;
            }
        }
        throw std::runtime_error("bounded stream witness clock limit");
    } catch (const std::exception& failure) {
        fprintf(stderr, "FAIL domain stream RTL: %s\n", failure.what());
        return 1;
    }
}
