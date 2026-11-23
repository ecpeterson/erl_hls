#ifndef XLS_SIM_AXIS_H
#define XLS_SIM_AXIS_H

#include <stdint.h>
#include <stddef.h>

/* Four-state samples; unknown contains the VPI X/Z mask. */
typedef struct { uint32_t value, unknown; } axis_value_t;
typedef struct { axis_value_t data, keep, last, valid, ready; } axis_sample_t;
typedef enum { AXIS_ROUTE, AXIS_HEADER, AXIS_PAYLOAD } axis_phase_t;
typedef struct {
    axis_phase_t phase;
    unsigned remaining;
    int stalled;
    axis_sample_t held;
} axis_monitor_t;

/* The FIFO transport carries word-aligned routed frames: route, inner header,
 * then the header's low-byte payload count (including the full debug range).
 * Call once per active clock edge. A zeroed monitor starts a reset epoch. */
static const char *axis_check(axis_monitor_t *monitor, axis_sample_t beat) {
    if (beat.valid.unknown) return "unknown TVALID";
    if (monitor->stalled && !beat.valid.value)
        return "TVALID dropped while stalled";
    if (!beat.valid.value) return NULL;
    if (beat.ready.unknown) return "unknown TREADY while valid";
    if (beat.keep.unknown) return "unknown TKEEP while valid";
    if (beat.last.unknown) return "unknown TLAST while valid";
    if (beat.data.unknown) return "unknown TDATA while valid";
    if (beat.keep.value != 0xf) return "partial TKEEP on word-aligned transport";
    if (monitor->stalled &&
        (beat.data.value != monitor->held.data.value ||
         beat.keep.value != monitor->held.keep.value ||
         beat.last.value != monitor->held.last.value))
        return "beat changed while stalled";
    monitor->stalled = !beat.ready.value;
    monitor->held = beat;
    if (!beat.ready.value) return NULL;

    int expected_last = 0;
    switch (monitor->phase) {
    case AXIS_ROUTE:
        monitor->phase = AXIS_HEADER;
        break;
    case AXIS_HEADER:
        monitor->remaining = beat.data.value & 0xff;
        expected_last = monitor->remaining == 0;
        monitor->phase = expected_last ? AXIS_ROUTE : AXIS_PAYLOAD;
        break;
    case AXIS_PAYLOAD:
        expected_last = --monitor->remaining == 0;
        if (expected_last) monitor->phase = AXIS_ROUTE;
        break;
    }
    if (beat.last.value != (unsigned)expected_last)
        return beat.last.value ? "early TLAST" : "missing TLAST at declared end";
    return NULL;
}

static const char *axis_finish(const axis_monitor_t *monitor) {
    return monitor->stalled || monitor->phase != AXIS_ROUTE ?
        "simulation ended with an incomplete transfer" : NULL;
}

#endif
