#ifndef HLS_TEST_FRAMED_FIFO_ENDPOINT_H
#define HLS_TEST_FRAMED_FIFO_ENDPOINT_H
#include "framed_fifo_stream.h"
#include "framed_fifo_control.h"
#include "verilated.h"
#include <memory>
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

#endif
