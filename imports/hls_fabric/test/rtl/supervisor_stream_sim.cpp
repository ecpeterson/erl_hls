#include "Vprotocol_supervisor_stream.h"
#include "verilated.h"
#include "framed_fifo_stream.h"
#include "framed_fifo_control.h"
#include <chrono>
#include <memory>
#include <thread>
#include <vector>

// References bind only public sampled top-level pins; no actor state is accessible.
struct LanePins {
    IData &word, &output_word;
    CData &valid, &last, &output_ready, &ready, &output_valid, &output_last;
};
struct SessionPins {
    QData &session, &observed;
    CData &reset, &attached;
};

// One independent endpoint owns bounded FIFO lanes and deployment-only session controls.
class Endpoint {
public:
    struct Lane {
        LanePins pins;
        std::unique_ptr<FramedFifoStream> fifo;
        DeliveryControl delivery;
        std::string name;
        Lane(LanePins pins, const std::string& prefix, const std::string& name):
            pins(pins), fifo(std::make_unique<FramedFifoStream>(prefix + "_" + name)),
            delivery(prefix + "_" + name + "_delivery"), name(name) {}
    };
    SessionPins pins;
    GenerationControl session_control, transport_control;
    std::string prefix;
    std::vector<std::unique_ptr<Lane>> lanes;
    uint64_t generation = 1, isolated_session = 0;
    bool isolated = true;
    explicit Endpoint(SessionPins pins, const std::string& prefix):
        pins(pins), session_control(prefix + "_session"),
        transport_control(prefix + "_transport"), prefix(prefix) {}
    void add(LanePins pins, const std::string& name) {
        lanes.emplace_back(std::make_unique<Lane>(pins, prefix, name));
    }
    // Actual descriptor rotation excludes all prior byte owners before a new session.
    void rotate(uint64_t next) {
        if (next <= generation) throw std::runtime_error("non-increasing descriptor generation");
        isolated = true; isolated_session = pins.observed;
        for (auto& lane : lanes) {
            lane->fifo.reset();
            lane->fifo = std::make_unique<FramedFifoStream>(prefix + "_transport" +
                std::to_string(next) + "_" + lane->name);
        }
        generation = next;
        transport_control.observe(next, true);
    }
    // File controls change delivery scheduling, never manufacture lifecycle responses.
    void drive(uint64_t cycle) {
        bool boundary = false;
        if (cycle % 256 == 0) {
            for (auto& lane : lanes) lane->delivery.poll();
            if (cycle >= 4 && transport_control.poll()) rotate(transport_control.generation());
            boundary = cycle >= 4 && session_control.poll();
            if (boundary) {
                isolated = true; isolated_session = pins.observed;
                for (auto& lane : lanes) lane->fifo->discard();
            }
        }
        pins.reset = boundary; pins.session = session_control.generation();
        for (auto& lane : lanes) {
            auto& fifo = *lane->fifo; auto& p = lane->pins;
            fifo.pump(lane->delivery.enabled());
            p.word = fifo.word; p.valid = fifo.valid && !isolated; p.last = fifo.last;
            p.output_ready = fifo.output_ready() && !isolated;
        }
    }
    // Only actual handshakes advance transport bytes; stalled beat stability is checked.
    void sample(uint64_t cycle) {
        for (auto& lane : lanes) {
            auto& p = lane->pins;
            lane->fifo->sample(p.ready && !isolated, p.output_word,
                p.output_valid && !isolated, p.output_last, p.output_ready, cycle);
        }
    }
    // The real RTL session output alone acknowledges attachment.
    void observe() {
        session_control.observe(pins.observed, pins.attached);
        if (pins.attached && pins.observed == session_control.generation() &&
            pins.observed > isolated_session) isolated = false;
    }
};

// Static generated port bindings describe the fixture, not recovery policy.
#define SESSION(P) SessionPins{core.P##_transport_session,core.P##_transport_session_observed,core.P##_transport_reset,core.P##_transport_attached}
#define LANE(P,L) LanePins{core.P##_##L##_word,core.P##_##L##_output_word,core.P##_##L##_valid,core.P##_##L##_last,core.P##_##L##_output_ready,core.P##_##L##_ready,core.P##_##L##_output_valid,core.P##_##L##_output_last}

// One clock advances parent policy and both child datapaths irrespective of host stalls.
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc != 2) return 2;
    try {
        std::string directory = argv[1];
        Vprotocol_supervisor_stream core;
        core.clk = 0; core.reset = 1;
        Endpoint parent(SESSION(parent),directory + "/parent");
        parent.add(LANE(parent,management),"management");
        Endpoint a(SESSION(child_0),directory + "/domain0");
        a.add(LANE(child_0,management),"management"); a.add(LANE(child_0,application),"application");
        Endpoint b(SESSION(child_1),directory + "/domain1");
        b.add(LANE(child_1,management),"management"); b.add(LANE(child_1,application),"application");
        std::vector<Endpoint*> endpoints = {&parent,&a,&b};
        auto start = std::chrono::steady_clock::now();
        uint64_t finish = 0;
        for (uint64_t cycle=0; cycle<50000000; ++cycle) {
            core.reset = cycle < 4;
            for (auto e : endpoints) e->drive(cycle);
            core.clk=0; core.eval();
            for (auto e : endpoints) e->sample(cycle);
            core.clk=1; core.eval();
            for (auto e : endpoints) e->observe();
            if (cycle%256==0) {
                if (!finish && access((directory+"/finished").c_str(),F_OK)==0) finish=cycle+256;
                if (std::chrono::steady_clock::now()-start > std::chrono::seconds(90))
                    throw std::runtime_error("bounded supervisor stream timeout");
                std::this_thread::sleep_for(std::chrono::microseconds(500));
            }
            if (finish && cycle>=finish) {
                printf("PASS supervisor stream RTL: cycles=%llu\n",(unsigned long long)cycle);
                return 0;
            }
        }
        throw std::runtime_error("bounded supervisor stream clocks");
    } catch(const std::exception& failure) {
        fprintf(stderr,"FAIL supervisor stream RTL: %s\n",failure.what()); return 1;
    }
}
