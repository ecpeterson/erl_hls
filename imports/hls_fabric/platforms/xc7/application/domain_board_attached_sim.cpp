#include "Vboard0.h"
#include "Vboard1.h"
#include "framed_fifo_stream.h"
#include <array>
#include <chrono>
#include <fstream>
#include <optional>
#include <thread>

// Host framing uses the existing bounded FIFO adapter. Sessions and inspection
// are driven only by actual route-4/route-3 commands from the production client.
template<class Board> struct Host {
    Board& board;
    FramedFifoStream application, management;
    Host(Board& board, const std::string& prefix): board(board),
        application(prefix + "_application"), management(prefix + "_management") {}
    void drive(uint64_t cycle, unsigned role) {
        application.pump(); management.pump();
        board.application_word = application.word;
        board.application_valid = application.valid && !board.reset;
        board.application_last = application.last;
        board.application_output_ready = application.output_ready() && (cycle + role) % 19 >= 3;
        board.host_word = management.word;
        board.host_valid = management.valid && !board.reset;
        board.host_last = management.last;
        board.host_output_ready = management.output_ready() && (cycle + 7 + role) % 17 >= 3;
    }
    void sample(uint64_t cycle) {
        application.sample(board.application_ready && !board.reset,
            board.application_output_word, board.application_output_valid && !board.reset,
            board.application_output_last, board.application_output_ready, cycle);
        management.sample(board.host_ready && !board.reset,
            board.host_output_word, board.host_output_valid && !board.reset,
            board.host_output_last, board.host_output_ready, cycle);
    }
    void result(FILE* out) const {
        if (!application.inputs || !application.outputs || !management.inputs || !management.outputs ||
            !(application.stalls + management.stalls))
            throw std::runtime_error("missing attached host lane traffic");
        fprintf(out, "{\"application_words\":[%llu,%llu],\"management_words\":[%llu,%llu],\"output_stalls\":%llu}",
            (unsigned long long)application.inputs, (unsigned long long)application.outputs,
            (unsigned long long)management.inputs, (unsigned long long)management.outputs,
            (unsigned long long)(application.stalls + management.stalls));
    }
};

// Atomic transport has one retained slot per direction, with unequal endpoint
// clocks. It neither interprets identity nor supplies a remote ready/session pin.
template<class Source, class Destination> struct Direction {
    struct Packet { std::array<uint32_t,32> words; unsigned count; };
    Source& source; Destination& destination;
    std::optional<Packet> slot;
    uint64_t after = 0, accepted = 0, delivered = 0, stalls = 0;
    Direction(Source& source, Destination& destination): source(source), destination(destination) {}
    void drive(uint64_t tick, uint64_t cycle, unsigned role) {
        source.packet_tx_ready = !source.reset && !slot && (cycle + role * 3) % 11 >= 3;
        destination.packet_rx_valid = !destination.reset && slot && tick >= after;
        destination.packet_rx_words = slot ? slot->count : 0;
        for (unsigned i = 0; i < 32; ++i) destination.packet_rx[i] = slot ? slot->words[i] : 0;
    }
    void sample(uint64_t tick, bool source_edge, bool destination_edge) {
        bool take = source_edge && source.packet_tx_valid && source.packet_tx_ready;
        bool give = destination_edge && destination.packet_rx_valid && destination.packet_rx_ready;
        if (source_edge && source.packet_tx_valid && !source.packet_tx_ready) ++stalls;
        if (take && slot) throw std::runtime_error("atomic carrier slot overflow");
        if (give) { slot.reset(); ++delivered; }
        if (take) {
            Packet packet; packet.count = source.packet_tx_words;
            if (packet.count != 11 && packet.count != 32) throw std::runtime_error("invalid packet word count");
            for (unsigned i = 0; i < 32; ++i) packet.words[i] = source.packet_tx[i];
            slot = packet; after = tick + 5 + (accepted * 3) % 29; ++accepted;
        }
    }
    void result(FILE* out) const {
        if (!accepted || !delivered || !stalls || accepted != delivered + (slot ? 1 : 0))
            throw std::runtime_error("incomplete bounded carrier coverage");
        fprintf(out, "{\"capacity\":1,\"accepted\":%llu,\"delivered\":%llu,\"stalls\":%llu,\"remaining\":%u}",
            (unsigned long long)accepted, (unsigned long long)delivered,
            (unsigned long long)stalls, slot ? 1 : 0);
    }
};

// The two emitted domain_board modules intentionally retain their ordinary names.
// Separate Verilator prefixes namespace their C++ models without rewriting RTL.
int main(int argc, char** argv) {
    if (argc != 2) return 2;
    try {
        VerilatedContext context; context.threads(1); context.commandArgs(argc, argv);
        Vboard0 a(&context, "board0"); Vboard1 b(&context, "board1");
        std::string directory = argv[1];
        a.clk = b.clk = 0; a.reset = b.reset = 1;
        a.carrier_fault = b.carrier_fault = 0;
        a.carrier_armed = b.carrier_armed = 1; // Explicit ideal carrier; no physical MAC/CDC claim.
        Host<Vboard0> host0(a, directory + "/board0");
        Host<Vboard1> host1(b, directory + "/board1");
        Direction<Vboard0,Vboard1> forward(a,b);
        Direction<Vboard1,Vboard0> reverse(b,a);
        std::array<uint64_t,2> cycles{0,0};
        bool ready = false; uint64_t finish = 0;
        auto start = std::chrono::steady_clock::now();
        for (uint64_t tick = 0; tick < 2000000000ull; ++tick) {
            bool rise0 = tick % 6 == 0, rise1 = tick % 10 == 1;
            bool fall0 = tick % 6 == 3, fall1 = tick % 10 == 6;
            if (rise0) { a.reset = cycles[0] < 4; host0.drive(cycles[0],0); }
            if (rise1) { b.reset = cycles[1] < 4; host1.drive(cycles[1],1); }
            forward.drive(tick,cycles[0],0); reverse.drive(tick,cycles[1],1);
            a.eval(); b.eval();
            if (rise0) host0.sample(cycles[0]);
            if (rise1) host1.sample(cycles[1]);
            forward.sample(tick,rise0,rise1); reverse.sample(tick,rise1,rise0);
            if (rise0) { a.clk = 1; ++cycles[0]; } else if (fall0) a.clk = 0;
            if (rise1) { b.clk = 1; ++cycles[1]; } else if (fall1) b.clk = 0;
            a.eval(); b.eval();
            if (!ready && cycles[0] >= 5 && cycles[1] >= 5) {
                std::ofstream marker(directory + "/transport.ready"); marker << "1\n";
                if (!marker) throw std::runtime_error("transport readiness write");
                ready = true;
            }
            if (tick % 1024 == 0) {
                if (!finish && access((directory + "/finished").c_str(),F_OK) == 0) finish = tick + 4096;
                if (std::chrono::steady_clock::now() - start > std::chrono::seconds(600))
                    throw std::runtime_error("attached board witness wallclock exceeded");
                std::this_thread::sleep_for(std::chrono::microseconds(200));
            }
            if (finish && tick >= finish) {
                FILE* out = fopen((directory + "/transport.json").c_str(),"wx");
                if (!out) throw std::runtime_error("transport result create");
                fprintf(out,"{\"clock_periods\":[6,10],\"clock_phases\":[0,1],\"local_cycles\":[%llu,%llu],\"hosts\":[",
                    (unsigned long long)cycles[0],(unsigned long long)cycles[1]);
                host0.result(out); fprintf(out,","); host1.result(out);
                fprintf(out,"],\"links\":["); forward.result(out); fprintf(out,","); reverse.result(out);
                fprintf(out,"],\"physical_carrier\":false,\"session_pin_injection\":false}\n"); fclose(out);
                a.final(); b.final();
                printf("PASS attached board host: public control and application streams\n"); return 0;
            }
        }
        throw std::runtime_error("attached board witness cycle bound exceeded");
    } catch (const std::exception& error) {
        fprintf(stderr,"FAIL attached board host: %s\n",error.what()); return 1;
    }
}
