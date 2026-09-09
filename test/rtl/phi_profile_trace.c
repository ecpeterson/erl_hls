#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vpi_user.h"

#define PATH_SIZE 4096
#define PHI_PLANE_COUNT 2
#define MAX_PHI_SHARDS 32
#define MAX_PHI_SCHEDULERS (PHI_PLANE_COUNT * MAX_PHI_SHARDS)
#define MAX_ROUTERS MAX_PHI_SCHEDULERS

/* phi_halo_cell::ReductionAggregateRequest is a 32-bit slot followed by the
 * 171-bit public ReductionAggregate. These least-significant bit positions
 * are stable under the DSLX struct's most-significant-field packing order.
 * Rejecting any other width makes an ABI change fail closed instead of
 * silently attaching misleading reduction metadata to a trace. */
#define AGGREGATE_REQUEST_BITS 203
#define AGGREGATE_KEY_LSB 135
#define AGGREGATE_SITE_LSB 167
#define AGGREGATE_FAILED_LSB 169
#define AGGREGATE_VALID_LSB 170

typedef struct {
    char hierarchy[PATH_SIZE];
    char name[32];
    vpiHandle read_request;
    vpiHandle read_valid;
    vpiHandle read_ready;
    vpiHandle write_request;
    vpiHandle write_valid;
    vpiHandle write_ready;
    vpiHandle egress_valid;
    vpiHandle egress_ready;
    vpiHandle aggregate;
    vpiHandle aggregate_valid;
    vpiHandle aggregate_ready;
} phi_scheduler_t;

typedef struct {
    char hierarchy[PATH_SIZE];
    char name[32];
    unsigned index;
    vpiHandle scheduled_valid;
    vpiHandle scheduled_ready;
    vpiHandle reduction;
    vpiHandle reduction_valid;
    vpiHandle reduction_ready;
} phi_router_t;

typedef struct {
    char hierarchy[PATH_SIZE];
    char name[32];
    vpiHandle batch[MAX_PHI_SHARDS];
    vpiHandle batch_valid[MAX_PHI_SHARDS];
    vpiHandle batch_ready[MAX_PHI_SHARDS];
    vpiHandle aggregate[MAX_PHI_SHARDS];
    vpiHandle aggregate_valid[MAX_PHI_SHARDS];
    vpiHandle aggregate_ready[MAX_PHI_SHARDS];
} phi_plane_t;

static vpiHandle h_clk;
static vpiHandle h_resetn;
static phi_scheduler_t schedulers[MAX_PHI_SCHEDULERS];
static unsigned scheduler_count;
static phi_router_t routers[MAX_ROUTERS];
static unsigned router_count;
static phi_plane_t planes[PHI_PLANE_COUNT];
static unsigned plane_count;
static unsigned profile_shard_count;
static uint64_t cycle_number;
static FILE *trace_file;

static unsigned expected_scheduler_count(void) {
    return PHI_PLANE_COUNT * profile_shard_count;
}

static int read_profile_configuration(void) {
    const char *text = getenv("ERL_HLS_PHI_PROFILE_SHARDS");
    char *end = NULL;
    unsigned long value;

    if (!text || text[0] == '\0')
        text = "3";
    value = strtoul(text, &end, 10);
    if (end == text || *end != '\0' || value == 0 ||
        value > MAX_PHI_SHARDS) {
        vpi_printf(
            "phi_profile_trace: ERL_HLS_PHI_PROFILE_SHARDS must be "
            "between 1 and %u, got %s\n",
            MAX_PHI_SHARDS,
            text);
        return 0;
    }
    profile_shard_count = (unsigned)value;
    return 1;
}

static vpiHandle module_signal(vpiHandle module, const char *name) {
    char path[PATH_SIZE + 128];
    const char *full_name = vpi_get_str(vpiFullName, module);

    snprintf(path, sizeof(path), "%s.%s", full_name, name);
    return vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
}

static vpiHandle top_signal(const char *top, const char *name) {
    char path[PATH_SIZE + 128];

    snprintf(path, sizeof(path), "%s.%s", top, name);
    return vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
}

static uint32_t get_u32(vpiHandle signal) {
    s_vpi_value value;

    value.format = vpiIntVal;
    vpi_get_value(signal, &value);
    return (uint32_t)value.value.integer;
}

static int get_bit(vpiHandle signal) {
    return (get_u32(signal) & 1U) != 0;
}

static uint32_t get_vector_u32(vpiHandle signal, unsigned lsb) {
    s_vpi_value value;
    unsigned word = lsb / 32;
    unsigned shift = lsb % 32;
    uint64_t result;

    value.format = vpiVectorVal;
    vpi_get_value(signal, &value);
    result = (uint32_t)value.value.vector[word].aval >> shift;
    if (shift != 0)
        result |= (uint64_t)(uint32_t)value.value.vector[word + 1].aval
            << (32 - shift);
    return (uint32_t)result;
}

/* DSLX structs place their first field at the most-significant end.  The
 * requests and batches traced here deliberately put slot/source first. */
static uint32_t get_high_u32(vpiHandle signal) {
    int size = vpi_get(vpiSize, signal);

    if (size <= 32)
        return get_u32(signal);
    return get_vector_u32(signal, (unsigned)(size - 32));
}

static const char *reduction_site_name(unsigned site) {
    switch (site) {
    case 0:
        return "gathering";
    case 1:
        return "comparing";
    case 2:
        return "flipping";
    default:
        return "unknown";
    }
}

static int aggregate_request_has_expected_width(vpiHandle request) {
    return request && vpi_get(vpiSize, request) == AGGREGATE_REQUEST_BITS;
}

static void aggregate_detail(
    vpiHandle request,
    const char *prefix,
    char *detail,
    size_t detail_size
) {
    unsigned valid = get_vector_u32(request, AGGREGATE_VALID_LSB) & 1U;
    unsigned failed = get_vector_u32(request, AGGREGATE_FAILED_LSB) & 1U;
    unsigned site = get_vector_u32(request, AGGREGATE_SITE_LSB) & 3U;
    unsigned key = get_vector_u32(request, AGGREGATE_KEY_LSB);

    snprintf(
        detail,
        detail_size,
        "%ssite=%s;key=%u;valid=%u;failed=%u",
        prefix ? prefix : "",
        reduction_site_name(site),
        key,
        valid,
        failed);
}

static int handshake(vpiHandle valid, vpiHandle ready) {
    return valid && ready && get_bit(valid) && get_bit(ready);
}

static void trace_event(
    const char *component,
    const char *event,
    int64_t slot,
    const char *detail
) {
    fprintf(
        trace_file,
        "%llu,%s,%s,%lld,%s\n",
        (unsigned long long)cycle_number,
        component,
        event,
        (long long)slot,
        detail ? detail : "");
}

static int scheduler_complete(const phi_scheduler_t *scheduler) {
    return scheduler->read_request && scheduler->read_valid &&
        scheduler->read_ready && scheduler->write_request &&
        scheduler->write_valid && scheduler->write_ready &&
        scheduler->egress_valid && scheduler->egress_ready &&
        scheduler->aggregate && scheduler->aggregate_valid &&
        scheduler->aggregate_ready &&
        aggregate_request_has_expected_width(scheduler->aggregate);
}

static void discover_scheduler(vpiHandle module) {
    phi_scheduler_t *scheduler;

    if (scheduler_count >= expected_scheduler_count()) {
        vpi_printf(
            "phi_profile_trace: more than %u phi schedulers found\n",
            expected_scheduler_count());
        scheduler_count++;
        return;
    }
    scheduler = &schedulers[scheduler_count];
    memset(scheduler, 0, sizeof(*scheduler));
    snprintf(
        scheduler->hierarchy,
        sizeof(scheduler->hierarchy),
        "%s",
        vpi_get_str(vpiFullName, module));
    scheduler->read_request = module_signal(module, "_ram_read_req_out");
    scheduler->read_valid = module_signal(module, "_ram_read_req_out_vld");
    scheduler->read_ready = module_signal(module, "_ram_read_req_out_rdy");
    scheduler->write_request = module_signal(module, "_ram_write_req_out");
    scheduler->write_valid = module_signal(module, "_ram_write_req_out_vld");
    scheduler->write_ready = module_signal(module, "_ram_write_req_out_rdy");
    scheduler->egress_valid = module_signal(module, "_egress_out_vld");
    scheduler->egress_ready = module_signal(module, "_egress_out_rdy");
    scheduler->aggregate = module_signal(module, "_aggregate_in");
    scheduler->aggregate_valid = module_signal(module, "_aggregate_in_vld");
    scheduler->aggregate_ready = module_signal(module, "_aggregate_in_rdy");
    if (!scheduler_complete(scheduler)) {
        vpi_printf(
            "phi_profile_trace: incomplete phi scheduler at %s\n",
            scheduler->hierarchy);
        scheduler_count++;
        return;
    }
    scheduler_count++;
}

static int parse_router_index(const char *definition, unsigned *index) {
    const char *marker = strstr(definition, "SchedulerRouter");
    char *end = NULL;
    unsigned long value;

    if (!marker)
        return 0;
    marker += strlen("SchedulerRouter");
    value = strtoul(marker, &end, 10);
    if (end == marker || value > UINT32_MAX)
        return 0;
    *index = (unsigned)value;
    return 1;
}

static void discover_router(vpiHandle module, const char *definition) {
    phi_router_t candidate;
    vpiHandle reduction;
    vpiHandle reduction_valid;
    vpiHandle reduction_ready;

    memset(&candidate, 0, sizeof(candidate));
    reduction = module_signal(module, "_phi_x_reduction_out");
    reduction_valid = module_signal(module, "_phi_x_reduction_out_vld");
    reduction_ready = module_signal(module, "_phi_x_reduction_out_rdy");
    if (!reduction || !reduction_valid || !reduction_ready) {
        reduction = module_signal(module, "_phi_z_reduction_out");
        reduction_valid = module_signal(module, "_phi_z_reduction_out_vld");
        reduction_ready = module_signal(module, "_phi_z_reduction_out_rdy");
    }
    /* Source schedulers have routers too, but only phi routers feed a
     * reduction plane. */
    if (!reduction || !reduction_valid || !reduction_ready)
        return;
    if (router_count >= MAX_ROUTERS ||
        !parse_router_index(definition, &candidate.index)) {
        vpi_printf(
            "phi_profile_trace: cannot identify phi router %s\n",
            vpi_get_str(vpiFullName, module));
        router_count = MAX_ROUTERS + 1;
        return;
    }
    snprintf(
        candidate.hierarchy,
        sizeof(candidate.hierarchy),
        "%s",
        vpi_get_str(vpiFullName, module));
    candidate.scheduled_valid = module_signal(module, "_scheduled_in_vld");
    candidate.scheduled_ready = module_signal(module, "_scheduled_in_rdy");
    candidate.reduction = reduction;
    candidate.reduction_valid = reduction_valid;
    candidate.reduction_ready = reduction_ready;
    if (!candidate.scheduled_valid || !candidate.scheduled_ready) {
        vpi_printf(
            "phi_profile_trace: incomplete phi router at %s\n",
            candidate.hierarchy);
        router_count = MAX_ROUTERS + 1;
        return;
    }
    routers[router_count++] = candidate;
}

static int plane_complete(const phi_plane_t *plane) {
    unsigned index;

    for (index = 0; index < profile_shard_count; index++) {
        if (!plane->batch[index] || !plane->batch_valid[index] ||
            !plane->batch_ready[index] || !plane->aggregate[index] ||
            !plane->aggregate_valid[index] ||
            !plane->aggregate_ready[index] ||
            !aggregate_request_has_expected_width(plane->aggregate[index]))
            return 0;
    }
    return 1;
}

static void discover_plane(vpiHandle module, const char *definition) {
    phi_plane_t *plane;
    unsigned index;
    char signal_name[64];

    if (plane_count >= PHI_PLANE_COUNT) {
        vpi_printf("phi_profile_trace: more than two phi planes found\n");
        plane_count++;
        return;
    }
    plane = &planes[plane_count];
    memset(plane, 0, sizeof(*plane));
    snprintf(
        plane->hierarchy,
        sizeof(plane->hierarchy),
        "%s",
        vpi_get_str(vpiFullName, module));
    snprintf(
        plane->name,
        sizeof(plane->name),
        "%s",
        strstr(definition, "Phi_xReductionPlane") ?
            "phi_x_plane" : "phi_z_plane");
    for (index = 0; index < profile_shard_count; index++) {
        snprintf(signal_name, sizeof(signal_name), "_batch_in__%u", index);
        plane->batch[index] = module_signal(module, signal_name);
        snprintf(
            signal_name, sizeof(signal_name), "_batch_in__%u_vld", index);
        plane->batch_valid[index] = module_signal(module, signal_name);
        snprintf(
            signal_name, sizeof(signal_name), "_batch_in__%u_rdy", index);
        plane->batch_ready[index] = module_signal(module, signal_name);
        snprintf(
            signal_name, sizeof(signal_name), "_aggregate_out_%u", index);
        plane->aggregate[index] = module_signal(module, signal_name);
        snprintf(
            signal_name,
            sizeof(signal_name),
            "_aggregate_out_%u_vld",
            index);
        plane->aggregate_valid[index] = module_signal(module, signal_name);
        snprintf(
            signal_name,
            sizeof(signal_name),
            "_aggregate_out_%u_rdy",
            index);
        plane->aggregate_ready[index] = module_signal(module, signal_name);
    }
    if (!plane_complete(plane))
        vpi_printf(
            "phi_profile_trace: incomplete reduction plane at %s\n",
            plane->hierarchy);
    plane_count++;
}

static void discover(vpiHandle scope) {
    vpiHandle iterator = vpi_iterate(vpiModule, scope);
    vpiHandle module;

    if (!iterator)
        return;
    while ((module = vpi_scan(iterator)) != NULL) {
        char definition[512];
        const char *definition_text = vpi_get_str(vpiDefName, module);

        snprintf(
            definition,
            sizeof(definition),
            "%s",
            definition_text ? definition_text : "");
        if (strstr(definition, "phi_halo_cell") &&
            strstr(definition, "SharedService"))
            discover_scheduler(module);
        else if (strstr(definition, "SchedulerRouter"))
            discover_router(module, definition);
        else if (strstr(definition, "Phi_xReductionPlane") ||
                 strstr(definition, "Phi_zReductionPlane"))
            discover_plane(module, definition);
        discover(module);
    }
}

static int compare_naturally(const char *left, const char *right) {
    while (*left != '\0' && *right != '\0') {
        if (isdigit((unsigned char)*left) &&
            isdigit((unsigned char)*right)) {
            uint64_t left_number = 0;
            uint64_t right_number = 0;

            while (isdigit((unsigned char)*left)) {
                left_number = left_number * 10 + (uint64_t)(*left - '0');
                left++;
            }
            while (isdigit((unsigned char)*right)) {
                right_number = right_number * 10 +
                    (uint64_t)(*right - '0');
                right++;
            }
            if (left_number != right_number)
                return left_number < right_number ? -1 : 1;
        } else {
            if (*left != *right)
                return (unsigned char)*left < (unsigned char)*right ? -1 : 1;
            left++;
            right++;
        }
    }
    return *left == *right ? 0 : (*left == '\0' ? -1 : 1);
}

static int compare_scheduler(const void *left, const void *right) {
    const phi_scheduler_t *a = left;
    const phi_scheduler_t *b = right;

    return compare_naturally(a->hierarchy, b->hierarchy);
}

static int compare_router(const void *left, const void *right) {
    const phi_router_t *a = left;
    const phi_router_t *b = right;

    return a->index < b->index ? -1 : a->index != b->index;
}

static int compare_plane(const void *left, const void *right) {
    const phi_plane_t *a = left;
    const phi_plane_t *b = right;

    return strcmp(a->name, b->name);
}

static int discovered_profile_is_complete(void) {
    unsigned index;

    if (scheduler_count != expected_scheduler_count() ||
        router_count != expected_scheduler_count() ||
        plane_count != PHI_PLANE_COUNT)
        return 0;
    for (index = 0; index < expected_scheduler_count(); index++) {
        if (!scheduler_complete(&schedulers[index]))
            return 0;
    }
    for (index = 0; index < PHI_PLANE_COUNT; index++) {
        if (!plane_complete(&planes[index]))
            return 0;
    }
    return 1;
}

static void name_profile(void) {
    unsigned index;

    qsort(
        schedulers,
        scheduler_count,
        sizeof(schedulers[0]),
        compare_scheduler);
    qsort(routers, router_count, sizeof(routers[0]), compare_router);
    qsort(planes, plane_count, sizeof(planes[0]), compare_plane);
    for (index = 0; index < scheduler_count; index++) {
        snprintf(
            schedulers[index].name,
            sizeof(schedulers[index].name),
            "phi_%u",
            index);
        snprintf(
            routers[index].name,
            sizeof(routers[index].name),
            "window_router_%u",
            routers[index].index);
        vpi_printf(
            "phi_profile_trace: %s at %s, routed by %s at %s\n",
            schedulers[index].name,
            schedulers[index].hierarchy,
            routers[index].name,
            routers[index].hierarchy);
    }
    for (index = 0; index < plane_count; index++)
        vpi_printf(
            "phi_profile_trace: %s at %s\n",
            planes[index].name,
            planes[index].hierarchy);
}

static void step_scheduler(const phi_scheduler_t *scheduler) {
    char detail[96];

    if (handshake(scheduler->aggregate_valid, scheduler->aggregate_ready)) {
        aggregate_detail(scheduler->aggregate, NULL, detail, sizeof(detail));
        trace_event(
            scheduler->name,
            "aggregate_receive",
            (int64_t)get_high_u32(scheduler->aggregate),
            detail);
    }
    if (handshake(scheduler->read_valid, scheduler->read_ready))
        trace_event(
            scheduler->name,
            "state_read",
            (int64_t)get_u32(scheduler->read_request),
            "");
    if (handshake(scheduler->write_valid, scheduler->write_ready))
        trace_event(
            scheduler->name,
            "state_write",
            (int64_t)get_high_u32(scheduler->write_request),
            "");
    if (handshake(scheduler->egress_valid, scheduler->egress_ready))
        trace_event(scheduler->name, "effects_egress", -1, "");
}

static void step_router(const phi_router_t *router) {
    if (handshake(router->scheduled_valid, router->scheduled_ready))
        trace_event(router->name, "effects_accept", -1, "");
    if (handshake(router->reduction_valid, router->reduction_ready))
        trace_event(
            router->name,
            "reduction_send",
            (int64_t)get_high_u32(router->reduction),
            "");
}

static void step_plane(const phi_plane_t *plane) {
    unsigned index;
    char detail[112];
    char prefix[32];

    for (index = 0; index < profile_shard_count; index++) {
        if (handshake(plane->batch_valid[index], plane->batch_ready[index])) {
            snprintf(detail, sizeof(detail), "source=%u", index);
            trace_event(
                plane->name,
                "batch_accept",
                (int64_t)get_high_u32(plane->batch[index]),
                detail);
        }
        if (handshake(
                plane->aggregate_valid[index],
                plane->aggregate_ready[index])) {
            snprintf(prefix, sizeof(prefix), "shard=%u;", index);
            aggregate_detail(
                plane->aggregate[index], prefix, detail, sizeof(detail));
            trace_event(
                plane->name,
                "aggregate_send",
                (int64_t)get_high_u32(plane->aggregate[index]),
                detail);
        }
    }
}

static void schedule_sync_cb(PLI_INT32 reason, PLI_INT32 (*callback)(p_cb_data)) {
    static s_vpi_time time;
    s_cb_data cb;

    memset(&cb, 0, sizeof(cb));
    time.type = vpiSimTime;
    cb.reason = reason;
    cb.cb_rtn = callback;
    cb.time = &time;
    vpi_register_cb(&cb);
}

static PLI_INT32 cb_readonly(p_cb_data cb) {
    unsigned index;

    (void)cb;
    if (!get_bit(h_clk))
        return 0;
    if (!get_bit(h_resetn)) {
        cycle_number = 0;
        return 0;
    }
    cycle_number++;
    for (index = 0; index < scheduler_count; index++)
        step_scheduler(&schedulers[index]);
    for (index = 0; index < router_count; index++)
        step_router(&routers[index]);
    for (index = 0; index < plane_count; index++)
        step_plane(&planes[index]);
    return 0;
}

static PLI_INT32 cb_clk_change(p_cb_data cb) {
    (void)cb;
    schedule_sync_cb(cbReadOnlySynch, cb_readonly);
    return 0;
}

static PLI_INT32 cb_end_of_sim(p_cb_data cb) {
    (void)cb;
    if (trace_file) {
        fclose(trace_file);
        trace_file = NULL;
    }
    return 0;
}

static PLI_INT32 cb_start_of_sim(p_cb_data cb) {
    const char *path = getenv("ERL_HLS_SIM_PHI_TRACE");
    const char *top = getenv("ERL_HLS_SIM_TOP");
    s_cb_data clock_cb;
    s_cb_data end_cb;

    (void)cb;
    if (!path || path[0] == '\0')
        return 0;
    if (!top || top[0] == '\0')
        top = "phi_decoder_profile_tb";
    if (!read_profile_configuration()) {
        vpi_control(vpiFinish, 1);
        return 0;
    }
    h_clk = top_signal(top, "clk");
    h_resetn = top_signal(top, "resetn");
    trace_file = fopen(path, "w");
    if (!h_clk || !h_resetn || !trace_file) {
        vpi_printf(
            "phi_profile_trace: cannot open trace or find %s clock/reset\n",
            top);
        if (trace_file) {
            fclose(trace_file);
            trace_file = NULL;
        }
        vpi_control(vpiFinish, 1);
        return 0;
    }
    setvbuf(trace_file, NULL, _IOLBF, 0);
    fprintf(trace_file, "cycle,component,event,slot,detail\n");
    discover(NULL);
    if (!discovered_profile_is_complete()) {
        vpi_printf(
            "phi_profile_trace: expected %u phi schedulers, %u phi routers, "
            "and 2 %u-shard reduction planes; found %u, %u, and %u\n",
            expected_scheduler_count(),
            expected_scheduler_count(),
            profile_shard_count,
            scheduler_count,
            router_count,
            plane_count);
        vpi_control(vpiFinish, 1);
        return 0;
    }
    name_profile();
    memset(&clock_cb, 0, sizeof(clock_cb));
    clock_cb.reason = cbValueChange;
    clock_cb.cb_rtn = cb_clk_change;
    clock_cb.obj = h_clk;
    vpi_register_cb(&clock_cb);
    memset(&end_cb, 0, sizeof(end_cb));
    end_cb.reason = cbEndOfSimulation;
    end_cb.cb_rtn = cb_end_of_sim;
    vpi_register_cb(&end_cb);
    return 0;
}

static void entry_point(void) {
    s_cb_data cb;

    memset(&cb, 0, sizeof(cb));
    cb.reason = cbStartOfSimulation;
    cb.cb_rtn = cb_start_of_sim;
    vpi_register_cb(&cb);
}

void (*vlog_startup_routines[])(void) = {
    entry_point,
    0
};
