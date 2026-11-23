/* Cycle-accurate, read-only taps from the existing debug projection.
 * No application memory, hierarchy discovery, signal writes, or hardware history. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "vpi_user.h"

#define LIMIT 32768
#define DEVICES 64
/* One checked slice, optionally qualified by a committed write/address. */
typedef struct {
    unsigned device, id, offset, width;
    char kind;
    int valid, address, address_width, slot, seen;
    uint32_t previous[4];
} probe_t;
static probe_t probes[LIMIT];
static unsigned count;
static FILE *trace;
static vpiHandle clocks[DEVICES], resets[DEVICES], active, physical[DEVICES], actors[DEVICES];
static uint64_t cycles[DEVICES];
static unsigned first[DEVICES], end[DEVICES];
static int failed;

/* Fail closed when a generated projection no longer matches its manifest. */
static void fail(const char *reason) {
    if (failed) return;
    failed = 1;
    vpi_printf("phi_service_trace: %s\n", reason);
    vpip_set_return_value(1);
    vpi_control(vpiFinish, 1);
}

/* Resolve only the named testbench clocks and generated observation outputs. */
static vpiHandle require_signal(const char *name) {
    vpiHandle result = vpi_handle_by_name((PLI_BYTE8 *)name, NULL);
    if (!result) fail(name);
    return result;
}

/* Scalar controls are sampled at the rising edge before sequential updates. */
static int bit(vpiHandle handle) {
    s_vpi_value value = {.format = vpiScalarVal};
    vpi_get_value(handle, &value);
    return value.value.scalar == vpi1;
}

/* Copy up to 128 bits, rejecting unknown values only within the selected slice. */
static void slice(s_vpi_vecval *bits, unsigned offset, unsigned width, uint32_t out[4]) {
    memset(out, 0, 4*sizeof(uint32_t));
    for (unsigned i = 0; i < width; ++i) {
        unsigned source = offset+i;
        uint32_t mask = (uint32_t)1 << (source%32);
        if ((uint32_t)bits[source/32].bval & mask) { fail("unknown observation bit"); return; }
        if ((uint32_t)bits[source/32].aval & mask) out[i/32] |= (uint32_t)1 << (i%32);
    }
}

/* Emit physical state changes and every committed actor-state write. */
static void sample(unsigned device, char bus, vpiHandle handle, double time) {
    s_vpi_value value = {.format = vpiVectorVal};
    vpi_get_value(handle, &value);
    for (unsigned i = first[device]; i < end[device] && !failed; ++i) {
        probe_t *p = &probes[i];
        if ((strchr("FC", p->kind) ? 'F' : 'A') != bus) continue;
        uint32_t current[4];
        if (p->valid >= 0) {
            slice(value.value.vector, (unsigned)p->valid, 1, current);
            if (!current[0]) continue;
        }
        if (p->address >= 0) {
            slice(value.value.vector, (unsigned)p->address, (unsigned)p->address_width, current);
            if (current[0] != (unsigned)p->slot) continue;
        }
        slice(value.value.vector, p->offset, p->width, current);
        if (p->kind == 'S' || !p->seen || memcmp(current, p->previous, sizeof(current))) {
            fprintf(trace, "%.0f,%u,%llu,%c,%u,%08x%08x%08x%08x\n", time, device,
                    (unsigned long long)cycles[device], p->kind, p->id,
                    current[3], current[2], current[1], current[0]);
            memcpy(p->previous, current, sizeof(current));
            p->seen = 1;
        }
    }
}

/* Independent counters share the debug controller's reset and pre-edge convention. */
static PLI_INT32 clock_changed(p_cb_data callback) {
    unsigned d = (unsigned)(uintptr_t)callback->user_data;
    if (failed || !bit(clocks[d])) return 0;
    if (bit(resets[d])) {
        cycles[d] = 0;
        for (unsigned i = first[d]; i < end[d]; ++i) probes[i].seen = 0;
    } else {
        if (bit(active)) {
            s_vpi_time time = {.type = vpiScaledRealTime};
            vpi_get_time(clocks[d], &time);
            sample(d, 'F', physical[d], time.real);
            sample(d, 'A', actors[d], time.real);
        }
        cycles[d]++;
    }
    return 0;
}

/* Close the append-only trace after the simulator's final assertions. */
static PLI_INT32 finish(p_cb_data callback) {
    (void)callback;
    if (trace) fclose(trace);
    return 0;
}

/* The plan supplies slices derived from schema-5 manifests and validated tap layouts. */
static PLI_INT32 start(p_cb_data callback) {
    (void)callback;
    FILE *config = fopen("cycle-probes.txt", "r");
    trace = fopen("cycle-trace.csv", "w");
    if (!config || !trace) { fail("missing cycle profile files"); return 0; }
    active = require_signal("phi_bridge_tb.resetn");
    probe_t p;
    while (!failed) {
        int n = fscanf(config, "%u %c %u %u %u %d %d %d %d", &p.device, &p.kind, &p.id,
                       &p.offset, &p.width, &p.valid, &p.address, &p.address_width, &p.slot);
        if (n == EOF) break;
        if (n != 9 || p.device >= DEVICES || count == LIMIT || p.width < 1 || p.width > 128 ||
            !strchr("FCSM", p.kind) || (count && p.device < probes[count-1].device)) { fail("invalid cycle probe declaration"); break; }
        if (!clocks[p.device]) {
            unsigned d = p.device;
            char name[160];
            snprintf(name, sizeof(name), "phi_bridge_tb.clk%u", d); clocks[d] = require_signal(name);
            snprintf(name, sizeof(name), "phi_bridge_tb.reset%u", d); resets[d] = require_signal(name);
            snprintf(name, sizeof(name), "phi_bridge_tb.device_%u.probe_values", d); physical[d] = require_signal(name);
            snprintf(name, sizeof(name), "phi_bridge_tb.device_%u.actor_writes", d); actors[d] = require_signal(name);
            first[d] = count;
            if (failed) break;
        }
        unsigned width = (unsigned)vpi_get(vpiSize, strchr("FC", p.kind) ? physical[p.device] : actors[p.device]);
        if (p.offset+p.width > width || (p.valid >= 0 && (unsigned)p.valid >= width) ||
            (p.address >= 0 && (unsigned)(p.address+p.address_width) > width)) {
            fail("cycle probe exceeds observation output"); break;
        }
        p.seen = 0;
        memset(p.previous, 0, sizeof(p.previous));
        probes[count++] = p;
        end[p.device] = count;
    }
    fclose(config);
    fprintf(trace, "time_ns,device,cycle,kind,id,value\n");
    for (unsigned d = 0; d < DEVICES && !failed; ++d) {
        if (!clocks[d]) continue;
        s_cb_data cb = {.reason = cbValueChange, .cb_rtn = clock_changed,
                       .obj = clocks[d], .user_data = (PLI_BYTE8 *)(uintptr_t)d};
        vpi_register_cb(&cb);
    }
    s_cb_data finished = {.reason = cbEndOfSimulation, .cb_rtn = finish};
    vpi_register_cb(&finished);
    return 0;
}

/* Register this read-only observer independently of the host transport. */
static void entry(void) {
    s_cb_data cb = {.reason = cbStartOfSimulation, .cb_rtn = start};
    vpi_register_cb(&cb);
}
void (*vlog_startup_routines[])(void) = {entry, 0};
