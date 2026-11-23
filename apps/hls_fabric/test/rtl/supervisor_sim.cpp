#include "Vprotocol_supervisor.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>

// Public-pin test instrument. It advances the device clock even when the host
// management adapter is disconnected; it never reads or writes private RTL state.
class Device {
    Vprotocol_supervisor core;
    uint64_t cycles = 0;
    struct Report { uint64_t count = 0, incarnation = 0; uint32_t request = 0, value = 0; };
    std::array<Report, 2> reports{};
    uint32_t status = 0, action = 0;
    bool accepted_grant = false, accepted_application = false, rejected_application = false;

    // Capture only transfers at actual source-network outputs.
    void sample() {
#define CAPTURE(N) \
        if (!core.reset && core.child_##N##_app_boundary_1_0_valid && core.child_##N##_boundary_1_0_ready) { \
            Report &r = reports[N]; r.count++; r.incarnation = core.child_##N##_domain_current; \
            r.request = core.child_##N##_app_boundary_1_0_data[1]; \
            r.value = core.child_##N##_app_boundary_1_0_data[2]; \
        }
        CAPTURE(0) CAPTURE(1)
#undef CAPTURE
    }

    // Every requested edge advances all separately resettable domains together.
    void edge() {
        core.clk = 0; core.eval(); sample();
        core.clk = 1; core.eval(); ++cycles;
    }

    // Finite test horizon prevents a broken implementation from hanging a check.
    void advance(uint64_t count) {
        if (count > 10000000) throw std::runtime_error("clock horizon exceeded");
        while (count--) edge();
    }

    // Integer fields make the test protocol independent of Erlang term encoding.
    void snapshot() {
        std::cout << "{\"cycles\":" << cycles
          << ",\"response_status\":" << status << ",\"response_action\":" << action
          << ",\"grant_accepted\":" << (accepted_grant ? "true" : "false")
          << ",\"app_accepted\":" << (accepted_application ? "true" : "false")
          << ",\"app_rejected\":" << (rejected_application ? "true" : "false");
#define FIELD(NAME) std::cout << ",\"" #NAME "\":" << uint64_t(core.NAME)
        FIELD(domain_phase); FIELD(domain_current); FIELD(domain_previous);
        FIELD(domain_target); FIELD(domain_transition); FIELD(domain_fault);
        FIELD(domain_admission); FIELD(domain_initialized);
        FIELD(supervisor_phase); FIELD(supervisor_reason); FIELD(local_seconds);
        FIELD(grant_next);
        FIELD(child_0_domain_phase); FIELD(child_0_domain_current);
        FIELD(child_1_domain_phase); FIELD(child_1_domain_current);
#undef FIELD
        for (unsigned i = 0; i < reports.size(); ++i) {
            const auto &r = reports[i];
            std::cout << ",\"report_" << i << "\":{\"count\":" << r.count
              << ",\"incarnation\":" << r.incarnation << ",\"request\":" << r.request
              << ",\"value\":" << r.value << "}";
        }
        std::cout << "}" << std::endl;
    }

public:
    // Cold simulation begins with public reset, exactly as an external device would.
    Device() {
        core.clk = 0; core.reset = 1;
        core.management_valid = 0; core.grant_valid = 0;
        core.child_0_ingress_valid = 0; core.child_1_ingress_valid = 0;
        core.child_0_transport_fault = 0; core.child_1_transport_fault = 0;
        core.child_0_boundary_1_0_ready = 1; core.child_1_boundary_1_0_ready = 1;
        advance(4); core.reset = 0; advance(4);
    }

    // Commands are bounded public test actions; source faults come from explode.
    void command(const std::string &line) {
        std::istringstream in(line); std::string op; in >> op;
        accepted_grant = accepted_application = rejected_application = false;
        if (op == "step") { uint64_t n; in >> n; advance(n); }
        else if (op == "snapshot") advance(32);
        else if (op == "grant") {
            uint64_t epoch, first, last; in >> epoch >> first >> last;
            core.grant_epoch = epoch; core.grant_first = first; core.grant_last = last;
            core.grant_valid = 1; core.clk = 0; core.eval();
            accepted_grant = core.grant_accepted;
            edge(); core.grant_valid = 0; advance(2);
        } else if (op == "management") {
            uint64_t operation, expected, target, transition, fault;
            in >> operation >> expected >> target >> transition >> fault;
            core.management_op = operation; core.expected = expected;
            core.target = target; core.transition = transition;
            core.management_fault = fault; core.management_valid = 1;
            bool done = false;
            for (unsigned i = 0; i < 256 && !done; ++i) {
                core.clk = 0; core.eval();
                done = core.management_response_valid;
                status = core.domain_status; action = core.domain_action; edge();
            }
            core.management_valid = 0;
            if (!done) throw std::runtime_error("management handshake timeout");
            advance(2);
        } else if (op == "application") {
            uint64_t slot, epoch, tag, request, value; in >> slot >> epoch >> tag >> request >> value;
            if (slot >= 2) throw std::runtime_error("bad child slot");
#define INPUT(N) \
            if (slot == N) { \
                core.child_##N##_incarnation = epoch; \
                for (unsigned i = 0; i < 14; ++i) core.child_##N##_ingress_data[i] = 0; \
                core.child_##N##_ingress_data[0] = request; core.child_##N##_ingress_data[1] = value; \
                core.child_##N##_ingress_data[10] = 0x02000000 | tag; core.child_##N##_ingress_valid = 1; \
            }
            INPUT(0) INPUT(1)
#undef INPUT
            for (unsigned i = 0; i < 512 && !accepted_application; ++i) {
                core.clk = 0; core.eval();
                accepted_application = slot == 0 ? core.child_0_app_ingress_ready : core.child_1_app_ingress_ready;
                rejected_application = slot == 0 ? core.child_0_domain_rejected : core.child_1_domain_rejected;
                edge();
            }
            core.child_0_ingress_valid = 0; core.child_1_ingress_valid = 0;
            if (!accepted_application) throw std::runtime_error("application handshake timeout");
            advance(64);
        } else if (op == "hold") {
            unsigned slot, hold; in >> slot >> hold;
            if (slot == 0) core.child_0_boundary_1_0_ready = !hold;
            else if (slot == 1) core.child_1_boundary_1_0_ready = !hold;
            else throw std::runtime_error("bad hold slot");
            advance(8);
        } else throw std::runtime_error("unsupported test command");
        if (!in) throw std::runtime_error("malformed test command");
        snapshot();
    }
};

// EOF closes only the test instrument; no recovery policy runs in this program.
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    try { Device device; std::string line; while (std::getline(std::cin, line)) device.command(line); }
    catch (const std::exception &error) { std::cerr << error.what() << std::endl; return 1; }
    return 0;
}
