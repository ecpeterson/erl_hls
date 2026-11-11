#include "Vprotocol_domain.h"
#include "verilated.h"
#include "framed_fifo_stream.h"
#include "domain_codes.h"
#include <array>
#include <chrono>
#include <deque>
#include <memory>
#include <thread>
#include <vector>

// Simulation transport only. Hardware, including lifecycle decisions and source
// callbacks, comes from the emitted domain core. Management has separate FIFOs.
struct Packet {
    uint32_t route = 0, header = 0;
    std::vector<uint32_t> payload;
};
struct Beat { uint32_t word; bool last; };

// Bound packet queues independently of the byte queues in FramedFifoStream.
class Channel {
public:
    FramedFifoStream stream;
    std::deque<Packet> received;
    explicit Channel(const std::string& path): stream(path) {}

    bool room() const { return outgoing.size() < 1000; }

    // The ordinary route/header format is shared with the actual Erlang broker.
    void send(uint32_t operation, const std::vector<uint32_t>& words,
              uint32_t route = 0, uint32_t transaction = 0) {
        if (outgoing.size() + words.size() + 2 > 1024)
            throw std::runtime_error("bounded outgoing packet queue full");
        outgoing.push_back({route, false});
        outgoing.push_back({(operation << 24) | (transaction & 0x00ffff00) |
                            uint32_t(words.size()), words.empty()});
        for (size_t i = 0; i < words.size(); ++i)
            outgoing.push_back({words[i], i + 1 == words.size()});
    }

    // A partial application packet cannot consume management buffer or parser state.
    void tick(uint64_t cycle, bool delivery = true) {
        stream.pump();
        bool input_ready = received.size() < 16;
        if (stream.valid && input_ready) {
            assembling.push_back(stream.word);
            if (assembling.size() > 18) throw std::runtime_error("oversize witness packet");
            if (stream.last) {
                if (assembling.size() < 2 || assembling.size() != 2 + (assembling[1] & 255))
                    throw std::runtime_error("malformed witness packet");
                received.push_back({assembling[0], assembling[1],
                    {assembling.begin() + 2, assembling.end()}});
                assembling.clear();
            }
        }
        bool available = !outgoing.empty();
        Beat front = available ? outgoing.front() : Beat{0, false};
        bool ready = stream.output_ready() && delivery;
        stream.sample(input_ready, front.word, available, front.last, ready, cycle);
        if (available && ready) outgoing.pop_front();
    }

private:
    std::vector<uint32_t> assembling;
    std::deque<Beat> outgoing;
};

// One physical domain, with its own hardware state and both independent channels.
class Domain {
public:
    Vprotocol_domain core;
    Channel management, application;
    uint64_t admitted = 0, rejected = 0, reports = 0, replacements = 0;
    explicit Domain(const std::string& prefix):
        core(prefix.c_str()), management(prefix + "_management"), application(prefix + "_application") {
        core.clk = 0; core.reset = 1;
        core.management_valid = 0; core.ingress_valid = 0;
        core.boundary_1_0_ready = 0;
        core.eval();
    }

    // Driver work is public pin framing/backpressure; it never edits actor/controller state.
    void tick(uint64_t cycle) {
        management.tick(cycle); application.tick(cycle, deliver);
        core.reset = cycle < 4;
        core.management_valid = 0;
        core.ingress_valid = 0;
        core.boundary_1_0_ready = !held && application.room();
        bool snapshot = false;
        if (!management.received.empty()) {
            const Packet& packet = management.received.front();
            unsigned op = packet.header >> 24;
            if (op == 0 && packet.payload.size() == 1) snapshot = true;
            else if (op == 7 && packet.payload.size() == 2) {
                // Test-only transport stall/corruption: the RTL's output acceptance is unchanged.
                if (packet.payload[1] > 2) throw std::runtime_error("bad delivery control");
                if (packet.payload[1] < 2) deliver = packet.payload[1] != 0;
                omit_frontier = packet.payload[1] == 2;
                snapshot = true;
            }
            else if (op == 1 && packet.payload.size() == 9) {
                core.management_valid = 1;
                core.management_op = packet.payload[1];
                core.expected = pair(packet.payload, 2);
                core.target = pair(packet.payload, 4);
                core.transition = pair(packet.payload, 6);
                core.management_fault = packet.payload[8];
            } else throw std::runtime_error("bad management command");
        }
        if (!application.received.empty()) {
            const Packet& packet = application.received.front();
            unsigned op = packet.header >> 24;
            if (op == 3 && packet.payload.size() == 1) {
                held = packet.payload[0] != 0;
                app_send(4, {uint32_t(held)}, packet.route, packet.header);
                application.received.pop_front();
                core.boundary_1_0_ready = !held && application.room();
            } else if ((op == 5 || op == 6) && packet.payload.size() == 4) {
                // Explicit negative-wire fixture: no hardware behavior is inferred from injection.
                app_send(op == 5 ? 2 : 3, packet.payload, packet.route, packet.header);
                application.received.pop_front();
            } else if (op == 2 && packet.payload.size() == 5) {
                core.incarnation = pair(packet.payload, 0);
                for (unsigned i = 0; i < 14; ++i) core.ingress_data[i] = 0;
                core.ingress_data[0] = packet.payload[3]; // request ID
                core.ingress_data[1] = packet.payload[4]; // value
                core.ingress_data[10] = 0x02000000 | packet.payload[2];
                core.ingress_valid = 1;
            } else throw std::runtime_error("bad application command");
        }
        core.clk = 0; core.eval();
        bool management_done = !core.reset && (snapshot ||
            (core.management_valid && core.management_response_valid));
        uint32_t status = snapshot ? STATUS_OK : core.domain_status;
        uint32_t action = snapshot ? ACTION_NONE : core.domain_action;
        bool application_done = core.ingress_valid && core.app_ingress_ready;
        if (application_done) {
            const Packet& packet = application.received.front();
            app_send(2, {packet.payload[0], packet.payload[1], packet.payload[3],
                uint32_t(core.domain_rejected)}, packet.route, packet.header);
            if (core.domain_rejected) rejected++; else admitted++;
            application.received.pop_front();
        }
        if (!core.reset && core.app_boundary_1_0_valid && core.boundary_1_0_ready) {
            if (core.app_boundary_1_0_data[0] != 0x03000002)
                throw std::runtime_error("unexpected source report header");
            app_send(3, {uint32_t(core.domain_current), uint32_t(core.domain_current >> 32),
                core.app_boundary_1_0_data[1], core.app_boundary_1_0_data[2]});
            reports++;
        }
        core.clk = 1; core.eval();
        if (management_done) {
            const Packet packet = management.received.front();
            if (core.management_valid && core.management_op == OPERATION_REPLACE && status == STATUS_ACCEPTED) replacements++;
            // The disposition is from the accepted edge; all state fields now describe its commit.
            core.management_valid = 0; core.ingress_valid = 0; core.eval();
            std::vector<uint32_t> fields = {packet.payload[0], status, action, core.domain_phase,
                uint32_t(core.domain_current), uint32_t(core.domain_current >> 32),
                uint32_t(core.domain_previous), uint32_t(core.domain_previous >> 32),
                uint32_t(core.domain_target), uint32_t(core.domain_target >> 32),
                uint32_t(core.domain_transition), uint32_t(core.domain_transition >> 32),
                core.domain_fault, core.domain_source_fault, core.domain_source_actor};
            // This frontier includes every application frame accepted before this snapshot,
            // including reports waiting in the bounded transport queue. It is not a work log.
            if (!omit_frontier) fields.push_back(application_sequence);
            omit_frontier = false;
            management.send(1, fields, packet.route, packet.header);
            management.received.pop_front();
        }
    }

private:
    bool held = false, deliver = true, omit_frontier = false;
    uint32_t application_sequence = 0;
    // A nonwrapping response sequence reconciles the independently scheduled output lanes.
    void app_send(uint32_t operation, const std::vector<uint32_t>& words,
                  uint32_t route = 0, uint32_t transaction = 0) {
        if (application_sequence == UINT32_MAX) throw std::runtime_error("application sequence exhausted");
        std::vector<uint32_t> fields = {++application_sequence};
        fields.insert(fields.end(), words.begin(), words.end());
        application.send(operation, fields, route, transaction);
    }
    // Host words are explicitly little endian, independent of native machine word layout.
    static uint64_t pair(const std::vector<uint32_t>& words, size_t at) {
        return words.at(at) | (uint64_t(words.at(at + 1)) << 32);
    }
};

// Two independent domains are always clocked, including while the other is stalled or replaced.
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc != 2) return 2;
    const std::string directory = argv[1];
    try {
        Domain a(directory + "/domain0"), b(directory + "/domain1");
        auto start = std::chrono::steady_clock::now();
        uint64_t finished_at = 0;
        for (uint64_t cycle = 0; cycle < 10000000; ++cycle) {
            a.tick(cycle); b.tick(cycle);
            if (!finished_at && access((directory + "/finished").c_str(), F_OK) == 0)
                finished_at = cycle + 100;
            if (finished_at && cycle >= finished_at) {
                printf("PASS domain RTL: A admitted=%llu rejected=%llu reports=%llu replacements=%llu; "
                       "B admitted=%llu rejected=%llu reports=%llu replacements=%llu\n",
                    (unsigned long long)a.admitted, (unsigned long long)a.rejected,
                    (unsigned long long)a.reports, (unsigned long long)a.replacements,
                    (unsigned long long)b.admitted, (unsigned long long)b.rejected,
                    (unsigned long long)b.reports, (unsigned long long)b.replacements);
                return 0;
            }
            if (cycle % 256 == 0) {
                if (std::chrono::steady_clock::now() - start > std::chrono::seconds(60))
                    throw std::runtime_error("bounded domain witness timeout");
                std::this_thread::sleep_for(std::chrono::microseconds(500));
            }
        }
        throw std::runtime_error("bounded domain witness clock limit");
    } catch (const std::exception& failure) {
        fprintf(stderr, "FAIL domain RTL: %s\n", failure.what());
        return 1;
    }
}
