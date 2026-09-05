#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "vpi_user.h"

#define BUFFER_SIZE 65536
#define PATH_SIZE 4096
#define MAX_SCHEDULERS 32
#define MAX_SCHEDULER_INPUTS 8
#define MAX_SCHEDULER_ACTORS 32

typedef struct {
    uint8_t bytes[BUFFER_SIZE];
    size_t head;
    size_t count;
} byte_ring_t;

typedef enum {
    INPUT_ROUTE_HEADER,
    INPUT_FRAME_HEADER,
    INPUT_FRAME_PAYLOAD
} input_phase_t;

typedef struct {
    const char *name;
    int enabled;
    vpiHandle h_s_data;
    vpiHandle h_s_valid;
    vpiHandle h_s_ready;
    vpiHandle h_s_last;
    vpiHandle h_m_data;
    vpiHandle h_m_valid;
    vpiHandle h_m_ready;
    int fd_host_to_sim;
    int fd_sim_to_host;
    byte_ring_t input_bytes;
    byte_ring_t output_bytes;
    uint32_t s_data;
    int s_valid;
    int s_last;
    int s_ready_sample;
    uint32_t m_data_sample;
    int m_valid_sample;
    int m_ready;
    /* Remaining payload words after the inner four-byte frame header. */
    unsigned input_payload_words;
    /* Which word comes next in the routed packet read from the byte FIFO. */
    input_phase_t input_phase;
    /* Diagnostic counters used only to make VPI logs easier to correlate. */
    unsigned input_beat_number;
    unsigned output_beat_number;
    /* Suppress reset-time output until the host begins its first request. */
    int output_armed;
} axis_endpoint_t;

typedef struct {
    uint64_t state_reads;
    uint64_t state_writes;
    uint64_t state_request_stalls;
    uint64_t state_responses;
    uint64_t state_write_completions;
    uint64_t mailbox_reads;
    uint64_t mailbox_writes;
    uint64_t mailbox_request_stalls;
    uint64_t mailbox_responses;
    uint64_t mailbox_write_completions;
    uint64_t requests;
    uint64_t request_stalls;
    uint64_t startup_requests;
    uint64_t egresses;
    uint64_t egress_stalls;
    uint64_t active_cycles;
    uint64_t issue_cycles;
    uint64_t no_issue_state_port_blocked;
    uint64_t no_issue_egress_backpressured;
    uint64_t no_issue_request_backpressured;
    uint64_t no_issue_without_visible_backpressure;
    uint64_t selection_activations;
    uint64_t selection_cycles_any_ready;
    uint64_t selection_cycles_selectable;
    uint64_t selection_cycles_executor_blocked;
    uint64_t selection_cycles_same_actor_only;
    uint64_t selection_cycles_waiting_egress_credit;
    uint64_t selection_cycles_no_actor_work;
    uint64_t selection_cycles_internal_other;
    uint64_t same_actor_observed_mailbox;
    uint64_t same_actor_observed_entry;
    uint64_t same_actor_observed_egress;
    uint64_t same_actor_observed_internal_other;
    uint64_t same_actor_phase_boundaries;
    uint64_t same_actor_followups;
    uint64_t same_actor_followup_mailbox;
    uint64_t same_actor_followup_entry;
    uint64_t same_actor_followup_egress;
    uint64_t same_actor_followup_waiting_egress_credit;
    uint64_t same_actor_followup_no_work;
    uint64_t same_actor_followup_direct_mailbox;
    uint64_t ready_slot_samples;
    uint64_t mail_candidate_slot_samples;
    uint64_t entry_probe_slot_samples;
    uint64_t egress_waiter_slot_samples;
    uint64_t pending_command_slot_samples;
    uint64_t pending_credit_slot_samples;
    uint64_t pending_command_activations;
    uint64_t pending_credit_activations;
    uint64_t mailbox_occupancy_samples;
    uint64_t mailbox_occupied_message_samples;
    uint64_t mailbox_nonempty_actor_samples;
    uint64_t mailbox_peak_occupied_messages;
    uint64_t mailbox_peak_nonempty_actors;
    uint64_t egress_busy_cycles;
    uint64_t mailbox_visit_count;
    uint64_t mailbox_visit_cycles;
    uint64_t mailbox_visit_min;
    uint64_t mailbox_visit_max;
    uint64_t entry_visit_count;
    uint64_t entry_visit_cycles;
    uint64_t entry_visit_min;
    uint64_t entry_visit_max;
    uint64_t intervisit_count;
    uint64_t intervisit_cycles;
    uint64_t intervisit_min;
    uint64_t intervisit_max;
    uint64_t state_read_interval_count;
    uint64_t state_read_interval_cycles;
    uint64_t state_read_interval_min;
    uint64_t state_read_interval_max;
    uint64_t state_read_write_overlaps;
    uint64_t state_same_address_overlaps;
    uint64_t mailbox_read_write_overlaps;
    uint64_t mailbox_same_address_overlaps;
    uint64_t actor_state_reads[MAX_SCHEDULER_ACTORS];
    uint64_t actor_ready_samples[MAX_SCHEDULER_ACTORS];
    uint64_t actor_same_actor_only[MAX_SCHEDULER_ACTORS];
    uint64_t actor_direct_mailbox_followups[MAX_SCHEDULER_ACTORS];
    uint64_t visit_start;
    uint64_t previous_write;
    uint64_t previous_state_read;
    int visit_open;
    int visit_has_mailbox;
    int previous_write_valid;
    int previous_state_read_valid;
} scheduler_counts_t;

typedef struct {
    char name[32];
    char hierarchy[PATH_SIZE];
    vpiHandle h_ram_read_request;
    vpiHandle h_ram_read_request_valid;
    vpiHandle h_ram_read_request_ready;
    vpiHandle h_ram_read_response_valid;
    vpiHandle h_ram_read_response_ready;
    vpiHandle h_ram_write_request_valid;
    vpiHandle h_ram_write_request_ready;
    vpiHandle h_ram_write_request;
    vpiHandle h_ram_write_response_valid;
    vpiHandle h_ram_write_response_ready;
    vpiHandle h_mailbox_read_request_valid;
    vpiHandle h_mailbox_read_request_ready;
    vpiHandle h_mailbox_read_request;
    vpiHandle h_mailbox_read_response_valid;
    vpiHandle h_mailbox_read_response_ready;
    vpiHandle h_mailbox_write_request_valid;
    vpiHandle h_mailbox_write_request_ready;
    vpiHandle h_mailbox_write_request;
    vpiHandle h_mailbox_write_response_valid;
    vpiHandle h_mailbox_write_response_ready;
    vpiHandle h_request_valid[MAX_SCHEDULER_INPUTS];
    vpiHandle h_request_ready[MAX_SCHEDULER_INPUTS];
    vpiHandle h_pending_valid[MAX_SCHEDULER_INPUTS];
    vpiHandle h_pending_credit[MAX_SCHEDULER_INPUTS];
    unsigned request_input_count;
    vpiHandle h_startup_valid;
    vpiHandle h_startup_ready;
    vpiHandle h_egress_valid;
    vpiHandle h_egress_ready;
    vpiHandle h_ready[MAX_SCHEDULER_ACTORS];
    vpiHandle h_selectable[MAX_SCHEDULER_ACTORS];
    vpiHandle h_mail_candidate[MAX_SCHEDULER_ACTORS];
    vpiHandle h_entry_probe[MAX_SCHEDULER_ACTORS];
    vpiHandle h_egress_waiter[MAX_SCHEDULER_ACTORS];
    vpiHandle h_occupied[MAX_SCHEDULER_ACTORS];
    vpiHandle h_egress_busy;
    vpiHandle h_selection_activation;
    vpiHandle h_phase_boundary;
    vpiHandle h_completed_valid;
    vpiHandle h_completed_effects_valid;
    unsigned actor_count;
    int activation_has_state_read;
    uint32_t activation_state_read_slot;
    int same_actor_followup_pending;
    uint32_t same_actor_followup_slot;
    int same_actor_followup_phase_boundary;
    scheduler_counts_t counts;
    scheduler_counts_t checkpoint;
} scheduler_profile_t;

static vpiHandle h_clk;
static vpiHandle h_resetn;
static const char *hierarchy_root;
static uint64_t cycle_number;
static axis_endpoint_t app_endpoint;
static axis_endpoint_t debug_endpoint;
static scheduler_profile_t scheduler_profiles[MAX_SCHEDULERS];
static unsigned scheduler_profile_count;
static char scheduler_profile_path[PATH_SIZE];
static int scheduler_profile_enabled;
static int scheduler_profile_started;
static int scheduler_profile_checkpoint_valid;
static int scheduler_profile_only;
static uint64_t scheduler_profile_start_cycle;
static uint64_t scheduler_profile_checkpoint_cycle;

static size_t ring_free(const byte_ring_t *ring) {
    return BUFFER_SIZE - ring->count;
}

static int ring_push(byte_ring_t *ring, uint8_t byte) {
    size_t tail;
    if (ring->count == BUFFER_SIZE)
        return 0;
    tail = (ring->head + ring->count) % BUFFER_SIZE;
    ring->bytes[tail] = byte;
    ring->count++;
    return 1;
}

static int ring_pop(byte_ring_t *ring, uint8_t *byte) {
    if (ring->count == 0)
        return 0;
    *byte = ring->bytes[ring->head];
    ring->head = (ring->head + 1) % BUFFER_SIZE;
    ring->count--;
    return 1;
}

static void ring_push_word(byte_ring_t *ring, uint32_t word) {
    unsigned shift;
    for (shift = 0; shift < 32; shift += 8)
        ring_push(ring, (uint8_t)(word >> shift));
}

static uint32_t ring_pop_word(byte_ring_t *ring) {
    uint32_t word = 0;
    uint8_t byte = 0;
    unsigned shift;
    for (shift = 0; shift < 32; shift += 8) {
        ring_pop(ring, &byte);
        word |= (uint32_t)byte << shift;
    }
    return word;
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

static uint32_t get_high_u32(vpiHandle signal) {
    int size = vpi_get(vpiSize, signal);
    return get_vector_u32(signal, (unsigned)(size - 32));
}

static void reset_latency_minima(scheduler_counts_t *counts) {
    counts->mailbox_visit_min = UINT64_MAX;
    counts->entry_visit_min = UINT64_MAX;
    counts->intervisit_min = UINT64_MAX;
    counts->state_read_interval_min = UINT64_MAX;
}

static void reset_scheduler_profile_counts(void) {
    unsigned index;
    for (index = 0; index < scheduler_profile_count; index++) {
        memset(&scheduler_profiles[index].counts, 0,
               sizeof(scheduler_profiles[index].counts));
        memset(&scheduler_profiles[index].checkpoint, 0,
               sizeof(scheduler_profiles[index].checkpoint));
        reset_latency_minima(&scheduler_profiles[index].counts);
        reset_latency_minima(&scheduler_profiles[index].checkpoint);
        scheduler_profiles[index].activation_has_state_read = 0;
        scheduler_profiles[index].activation_state_read_slot = 0;
        scheduler_profiles[index].same_actor_followup_pending = 0;
        scheduler_profiles[index].same_actor_followup_slot = 0;
        scheduler_profiles[index].same_actor_followup_phase_boundary = 0;
    }
    scheduler_profile_checkpoint_valid = 0;
    scheduler_profile_checkpoint_cycle = 0;
}

static void update_latency(
    uint64_t latency,
    uint64_t *count,
    uint64_t *total,
    uint64_t *minimum,
    uint64_t *maximum
) {
    (*count)++;
    *total += latency;
    if (latency < *minimum)
        *minimum = latency;
    if (latency > *maximum)
        *maximum = latency;
}

static uint64_t printable_minimum(uint64_t count, uint64_t minimum) {
    return count == 0 ? 0 : minimum;
}

static void write_scheduler_profile(void) {
    char temporary_path[PATH_SIZE + sizeof(".tmp")];
    int profile_fd;
    unsigned index;
    uint64_t observed_cycle;
    const scheduler_counts_t *counts;

    if (!scheduler_profile_enabled || !scheduler_profile_started)
        return;

    observed_cycle = scheduler_profile_checkpoint_valid ?
        scheduler_profile_checkpoint_cycle : cycle_number;
    snprintf(temporary_path, sizeof(temporary_path), "%s.tmp",
             scheduler_profile_path);
    profile_fd = open(
        temporary_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (profile_fd < 0)
        return;
    dprintf(profile_fd, "profile_start_cycle=%llu\n",
            (unsigned long long)scheduler_profile_start_cycle);
    dprintf(profile_fd, "profile_observed_cycle=%llu\n",
            (unsigned long long)observed_cycle);
    dprintf(profile_fd, "profile_observed_cycles=%llu\n",
            (unsigned long long)(observed_cycle -
                scheduler_profile_start_cycle + 1));
    dprintf(profile_fd, "profile_snapshot=%s\n",
            scheduler_profile_checkpoint_valid ?
                "last_application_output" : "current");

    for (index = 0; index < scheduler_profile_count; index++) {
        scheduler_profile_t *profile = &scheduler_profiles[index];
        counts = scheduler_profile_checkpoint_valid ?
            &profile->checkpoint : &profile->counts;
#define PROFILE_VALUE(key, value) \
        dprintf(profile_fd, "%s_%s=%llu\n", profile->name, key, \
                (unsigned long long)(value))
        PROFILE_VALUE("state_reads", counts->state_reads);
        PROFILE_VALUE("state_writes", counts->state_writes);
        PROFILE_VALUE("state_request_stalls", counts->state_request_stalls);
        PROFILE_VALUE("state_responses", counts->state_responses);
        PROFILE_VALUE("state_write_completions",
                      counts->state_write_completions);
        PROFILE_VALUE("mailbox_reads", counts->mailbox_reads);
        PROFILE_VALUE("mailbox_writes", counts->mailbox_writes);
        PROFILE_VALUE("mailbox_request_stalls",
                      counts->mailbox_request_stalls);
        PROFILE_VALUE("mailbox_responses", counts->mailbox_responses);
        PROFILE_VALUE("mailbox_write_completions",
                      counts->mailbox_write_completions);
        PROFILE_VALUE("requests", counts->requests);
        PROFILE_VALUE("request_stalls", counts->request_stalls);
        PROFILE_VALUE("startup_requests", counts->startup_requests);
        PROFILE_VALUE("egresses", counts->egresses);
        PROFILE_VALUE("egress_stalls", counts->egress_stalls);
        PROFILE_VALUE("active_cycles", counts->active_cycles);
        PROFILE_VALUE("executor_decoupled",
                      profile->h_completed_valid != NULL);
        PROFILE_VALUE("issue_cycles", counts->issue_cycles);
        PROFILE_VALUE("no_issue_state_port_blocked",
                      counts->no_issue_state_port_blocked);
        PROFILE_VALUE("no_issue_egress_backpressured",
                      counts->no_issue_egress_backpressured);
        PROFILE_VALUE("no_issue_request_backpressured",
                      counts->no_issue_request_backpressured);
        PROFILE_VALUE("no_issue_without_visible_backpressure",
                      counts->no_issue_without_visible_backpressure);
        PROFILE_VALUE("selection_activations",
                      counts->selection_activations);
        PROFILE_VALUE("selection_cycles_any_ready",
                      counts->selection_cycles_any_ready);
        PROFILE_VALUE("selection_cycles_selectable",
                      counts->selection_cycles_selectable);
        PROFILE_VALUE("selection_cycles_executor_blocked",
                      counts->selection_cycles_executor_blocked);
        PROFILE_VALUE("selection_cycles_same_actor_only",
                      counts->selection_cycles_same_actor_only);
        PROFILE_VALUE("selection_cycles_waiting_egress_credit",
                      counts->selection_cycles_waiting_egress_credit);
        PROFILE_VALUE("selection_cycles_no_actor_work",
                      counts->selection_cycles_no_actor_work);
        PROFILE_VALUE("selection_cycles_internal_other",
                      counts->selection_cycles_internal_other);
        PROFILE_VALUE("same_actor_observed_mailbox",
                      counts->same_actor_observed_mailbox);
        PROFILE_VALUE("same_actor_observed_entry",
                      counts->same_actor_observed_entry);
        PROFILE_VALUE("same_actor_observed_egress",
                      counts->same_actor_observed_egress);
        PROFILE_VALUE("same_actor_observed_internal_other",
                      counts->same_actor_observed_internal_other);
        PROFILE_VALUE("same_actor_phase_boundaries",
                      counts->same_actor_phase_boundaries);
        PROFILE_VALUE("same_actor_followups",
                      counts->same_actor_followups);
        PROFILE_VALUE("same_actor_followup_mailbox",
                      counts->same_actor_followup_mailbox);
        PROFILE_VALUE("same_actor_followup_entry",
                      counts->same_actor_followup_entry);
        PROFILE_VALUE("same_actor_followup_egress",
                      counts->same_actor_followup_egress);
        PROFILE_VALUE("same_actor_followup_waiting_egress_credit",
                      counts->same_actor_followup_waiting_egress_credit);
        PROFILE_VALUE("same_actor_followup_no_work",
                      counts->same_actor_followup_no_work);
        PROFILE_VALUE("same_actor_followup_direct_mailbox",
                      counts->same_actor_followup_direct_mailbox);
        PROFILE_VALUE("ready_slot_samples", counts->ready_slot_samples);
        PROFILE_VALUE("mail_candidate_slot_samples",
                      counts->mail_candidate_slot_samples);
        PROFILE_VALUE("entry_probe_slot_samples",
                      counts->entry_probe_slot_samples);
        PROFILE_VALUE("egress_waiter_slot_samples",
                      counts->egress_waiter_slot_samples);
        PROFILE_VALUE("pending_command_slot_samples",
                      counts->pending_command_slot_samples);
        PROFILE_VALUE("pending_credit_slot_samples",
                      counts->pending_credit_slot_samples);
        PROFILE_VALUE("pending_command_activations",
                      counts->pending_command_activations);
        PROFILE_VALUE("pending_credit_activations",
                      counts->pending_credit_activations);
        PROFILE_VALUE("mailbox_occupancy_samples",
                      counts->mailbox_occupancy_samples);
        PROFILE_VALUE("mailbox_occupied_message_samples",
                      counts->mailbox_occupied_message_samples);
        PROFILE_VALUE("mailbox_nonempty_actor_samples",
                      counts->mailbox_nonempty_actor_samples);
        PROFILE_VALUE("mailbox_peak_occupied_messages",
                      counts->mailbox_peak_occupied_messages);
        PROFILE_VALUE("mailbox_peak_nonempty_actors",
                      counts->mailbox_peak_nonempty_actors);
        PROFILE_VALUE("egress_busy_cycles", counts->egress_busy_cycles);
        PROFILE_VALUE("mailbox_visits", counts->mailbox_visit_count);
        PROFILE_VALUE("mailbox_visit_cycles", counts->mailbox_visit_cycles);
        PROFILE_VALUE("mailbox_visit_min", printable_minimum(
            counts->mailbox_visit_count, counts->mailbox_visit_min));
        PROFILE_VALUE("mailbox_visit_max", counts->mailbox_visit_max);
        PROFILE_VALUE("entry_visits", counts->entry_visit_count);
        PROFILE_VALUE("entry_visit_cycles", counts->entry_visit_cycles);
        PROFILE_VALUE("entry_visit_min", printable_minimum(
            counts->entry_visit_count, counts->entry_visit_min));
        PROFILE_VALUE("entry_visit_max", counts->entry_visit_max);
        PROFILE_VALUE("intervisits", counts->intervisit_count);
        PROFILE_VALUE("intervisit_cycles", counts->intervisit_cycles);
        PROFILE_VALUE("intervisit_min", printable_minimum(
            counts->intervisit_count, counts->intervisit_min));
        PROFILE_VALUE("intervisit_max", counts->intervisit_max);
        PROFILE_VALUE("state_read_intervals",
                      counts->state_read_interval_count);
        PROFILE_VALUE("state_read_interval_cycles",
                      counts->state_read_interval_cycles);
        PROFILE_VALUE("state_read_interval_min", printable_minimum(
            counts->state_read_interval_count,
            counts->state_read_interval_min));
        PROFILE_VALUE("state_read_interval_max",
                      counts->state_read_interval_max);
        PROFILE_VALUE("state_read_write_overlaps",
                      counts->state_read_write_overlaps);
        PROFILE_VALUE("state_same_address_overlaps",
                      counts->state_same_address_overlaps);
        PROFILE_VALUE("mailbox_read_write_overlaps",
                      counts->mailbox_read_write_overlaps);
        PROFILE_VALUE("mailbox_same_address_overlaps",
                      counts->mailbox_same_address_overlaps);
        {
            unsigned actor;
            for (actor = 0; actor < profile->actor_count; actor++) {
                char key[64];
                snprintf(key, sizeof(key), "actor_%u_state_reads", actor);
                PROFILE_VALUE(key, counts->actor_state_reads[actor]);
                snprintf(key, sizeof(key), "actor_%u_ready_samples", actor);
                PROFILE_VALUE(key, counts->actor_ready_samples[actor]);
                snprintf(key, sizeof(key), "actor_%u_same_actor_only", actor);
                PROFILE_VALUE(key, counts->actor_same_actor_only[actor]);
                snprintf(key, sizeof(key),
                         "actor_%u_direct_mailbox_followups", actor);
                PROFILE_VALUE(
                    key, counts->actor_direct_mailbox_followups[actor]);
            }
        }
#undef PROFILE_VALUE
    }
    dprintf(profile_fd, "profile_complete=1\n");
    if (close(profile_fd) != 0 ||
        rename(temporary_path, scheduler_profile_path) != 0) {
        unlink(temporary_path);
    }
}

static void put_u32(vpiHandle signal, uint32_t word) {
    s_vpi_value value;
    value.format = vpiIntVal;
    value.value.integer = (PLI_INT32)word;
    vpi_put_value(signal, &value, NULL, vpiNoDelay);
}

static void put_bit(vpiHandle signal, int bit) {
    s_vpi_value value;
    value.format = vpiScalarVal;
    value.value.scalar = bit ? vpi1 : vpi0;
    vpi_put_value(signal, &value, NULL, vpiNoDelay);
}

static void pump_input(axis_endpoint_t *endpoint) {
    uint8_t buffer[4096];
    ssize_t count;
    size_t index;

    if (!endpoint->enabled)
        return;

    while (ring_free(&endpoint->input_bytes) >= sizeof(buffer)) {
        count = read(endpoint->fd_host_to_sim, buffer, sizeof(buffer));
        if (count > 0) {
            vpi_printf("xls_sim_bridge[%s]: read %ld host byte(s)\n",
                       endpoint->name, (long)count);
            for (index = 0; index < (size_t)count; index++)
                ring_push(&endpoint->input_bytes, buffer[index]);
        } else if (count == 0 || errno == EAGAIN || errno == EWOULDBLOCK) {
            return;
        } else if (errno != EINTR) {
            vpi_printf("xls_sim_bridge[%s]: input FIFO read failed: %s\n",
                       endpoint->name, strerror(errno));
            return;
        }
    }
}

static void pump_output(axis_endpoint_t *endpoint) {
    uint8_t buffer[4096];
    size_t count = endpoint->output_bytes.count;
    size_t index;
    ssize_t written;

    if (!endpoint->enabled)
        return;

    if (count > sizeof(buffer))
        count = sizeof(buffer);
    for (index = 0; index < count; index++)
        buffer[index] = endpoint->output_bytes.bytes[
            (endpoint->output_bytes.head + index) % BUFFER_SIZE
        ];

    if (count == 0)
        return;
    written = write(endpoint->fd_sim_to_host, buffer, count);
    if (written > 0) {
        endpoint->output_bytes.head =
            (endpoint->output_bytes.head + (size_t)written) % BUFFER_SIZE;
        endpoint->output_bytes.count -= (size_t)written;
    } else if (written < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
        vpi_printf("xls_sim_bridge[%s]: output FIFO write failed: %s\n",
                   endpoint->name, strerror(errno));
    }
}

static void load_input_beat(axis_endpoint_t *endpoint) {
    uint32_t word;

    if (!endpoint->enabled || endpoint->s_valid ||
        endpoint->input_bytes.count < 4)
        return;

    word = ring_pop_word(&endpoint->input_bytes);
    endpoint->s_data = word;
    endpoint->s_valid = 1;
    if (endpoint->input_phase == INPUT_ROUTE_HEADER) {
        endpoint->s_last = 0;
        endpoint->input_phase = INPUT_FRAME_HEADER;
    } else if (endpoint->input_phase == INPUT_FRAME_HEADER) {
        endpoint->input_payload_words = word & 0xffU;
        endpoint->s_last = endpoint->input_payload_words == 0;
        endpoint->input_phase = endpoint->s_last ?
            INPUT_ROUTE_HEADER : INPUT_FRAME_PAYLOAD;
    } else {
        endpoint->s_last = endpoint->input_payload_words == 1;
        endpoint->input_payload_words--;
        if (endpoint->s_last)
            endpoint->input_phase = INPUT_ROUTE_HEADER;
    }
    vpi_printf("xls_sim_bridge[%s]: input beat %u data=%08x last=%d\n",
               endpoint->name, ++endpoint->input_beat_number, word, endpoint->s_last);
}

static void reset_endpoint(axis_endpoint_t *endpoint) {
    if (!endpoint->enabled)
        return;
    endpoint->s_data = 0;
    endpoint->s_valid = 0;
    endpoint->s_last = 0;
    endpoint->m_data_sample = 0;
    endpoint->m_valid_sample = 0;
    endpoint->m_ready = 1;
    endpoint->input_payload_words = 0;
    endpoint->input_phase = INPUT_ROUTE_HEADER;
    endpoint->output_armed = 0;
}

static void step_endpoint(axis_endpoint_t *endpoint) {
    if (!endpoint->enabled)
        return;

    if (endpoint->s_valid && endpoint->s_ready_sample) {
        vpi_printf("xls_sim_bridge[%s]: cycle=%llu accepted input beat %u\n",
                   endpoint->name, (unsigned long long)cycle_number,
                   endpoint->input_beat_number);
        endpoint->output_armed = 1;
        endpoint->s_valid = 0;
        endpoint->s_last = 0;
    }

    if (endpoint->m_valid_sample && endpoint->m_ready) {
        if (endpoint->output_armed) {
            vpi_printf(
                "xls_sim_bridge[%s]: cycle=%llu output beat %u data=%08x\n",
                endpoint->name, (unsigned long long)cycle_number,
                ++endpoint->output_beat_number, endpoint->m_data_sample);
            if (ring_free(&endpoint->output_bytes) >= 4)
                ring_push_word(&endpoint->output_bytes, endpoint->m_data_sample);
            else
                vpi_printf("xls_sim_bridge[%s]: internal output buffer overflow\n",
                           endpoint->name);
        } else {
            vpi_printf("xls_sim_bridge[%s]: discarded pre-request output %08x\n",
                       endpoint->name, endpoint->m_data_sample);
        }
    }

    pump_output(endpoint);
    endpoint->m_ready = ring_free(&endpoint->output_bytes) >= 4;
    load_input_beat(endpoint);
}

static void apply_drives(axis_endpoint_t *endpoint) {
    if (!endpoint->enabled)
        return;
    put_u32(endpoint->h_s_data, endpoint->s_data);
    put_bit(endpoint->h_s_valid, endpoint->s_valid);
    put_bit(endpoint->h_s_last, endpoint->s_last);
    put_bit(endpoint->h_m_ready, endpoint->m_ready);
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

static vpiHandle module_signal(vpiHandle module, const char *name) {
    char path[PATH_SIZE + 128];
    const char *full_name = vpi_get_str(vpiFullName, module);
    snprintf(path, sizeof(path), "%s.%s", full_name, name);
    return vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
}

static int populate_scheduler_profile(
    scheduler_profile_t *profile,
    vpiHandle module
) {
    char definition[256];
    const char *full_name;
    unsigned index;
    char signal_name[64];

    snprintf(definition, sizeof(definition), "%s",
             vpi_get_str(vpiDefName, module));
    full_name = vpi_get_str(vpiFullName, module);

    if (strstr(definition, "phenom_data_cell"))
        snprintf(profile->name, sizeof(profile->name), "data");
    else if (strstr(definition, "phi_halo_cell"))
        snprintf(profile->name, sizeof(profile->name), "phi");
    else if (strstr(definition, "phenom_syndrome_cell"))
        snprintf(profile->name, sizeof(profile->name), "syndrome");
    else if (strstr(definition, "phi_syndrome_replay_cell"))
        snprintf(profile->name, sizeof(profile->name), "source");
    else
        snprintf(profile->name, sizeof(profile->name), "scheduler_%u",
                 scheduler_profile_count);
    snprintf(profile->hierarchy, sizeof(profile->hierarchy), "%s", full_name);

#define MODULE_SIGNAL(field, name) \
    profile->field = module_signal(module, name)
    MODULE_SIGNAL(h_ram_read_request, "_ram_read_req_out");
    MODULE_SIGNAL(h_ram_read_request_valid, "_ram_read_req_out_vld");
    MODULE_SIGNAL(h_ram_read_request_ready, "_ram_read_req_out_rdy");
    MODULE_SIGNAL(h_ram_read_response_valid, "_ram_read_resp_in_vld");
    MODULE_SIGNAL(h_ram_read_response_ready, "_ram_read_resp_in_rdy");
    MODULE_SIGNAL(h_ram_write_request_valid, "_ram_write_req_out_vld");
    MODULE_SIGNAL(h_ram_write_request_ready, "_ram_write_req_out_rdy");
    MODULE_SIGNAL(h_ram_write_request, "_ram_write_req_out");
    MODULE_SIGNAL(h_ram_write_response_valid, "_ram_write_resp_in_vld");
    MODULE_SIGNAL(h_ram_write_response_ready, "_ram_write_resp_in_rdy");
    MODULE_SIGNAL(h_mailbox_read_request_valid,
                  "_mailbox_read_req_out_vld");
    MODULE_SIGNAL(h_mailbox_read_request_ready,
                  "_mailbox_read_req_out_rdy");
    MODULE_SIGNAL(h_mailbox_read_request, "_mailbox_read_req_out");
    MODULE_SIGNAL(h_mailbox_read_response_valid,
                  "_mailbox_read_resp_in_vld");
    MODULE_SIGNAL(h_mailbox_read_response_ready,
                  "_mailbox_read_resp_in_rdy");
    MODULE_SIGNAL(h_mailbox_write_request_valid,
                  "_mailbox_write_req_out_vld");
    MODULE_SIGNAL(h_mailbox_write_request_ready,
                  "_mailbox_write_req_out_rdy");
    MODULE_SIGNAL(h_mailbox_write_request, "_mailbox_write_req_out");
    MODULE_SIGNAL(h_mailbox_write_response_valid,
                  "_mailbox_write_resp_in_vld");
    MODULE_SIGNAL(h_mailbox_write_response_ready,
                  "_mailbox_write_resp_in_rdy");
    MODULE_SIGNAL(h_startup_valid, "_startup_in_vld");
    MODULE_SIGNAL(h_startup_ready, "_startup_in_rdy");
    MODULE_SIGNAL(h_egress_valid, "_egress_out_vld");
    MODULE_SIGNAL(h_egress_ready, "_egress_out_rdy");
    MODULE_SIGNAL(h_egress_busy, "admitted_egress_busy");
    if (!profile->h_egress_busy)
        profile->h_egress_busy = module_signal(module, "retired_egress_busy");
    MODULE_SIGNAL(h_selection_activation, "p0_stage_done");
    MODULE_SIGNAL(h_phase_boundary, "phase_boundary");
    if (!profile->h_phase_boundary)
        profile->h_phase_boundary = module_signal(module, "result_phase_boundary");
    MODULE_SIGNAL(h_completed_valid, "completed_valid");
    MODULE_SIGNAL(h_completed_effects_valid, "completed_effects_valid");
#undef MODULE_SIGNAL

    for (index = 0; index < MAX_SCHEDULER_INPUTS; index++) {
        snprintf(signal_name, sizeof(signal_name), "_request_in__%u_vld", index);
        profile->h_request_valid[index] = module_signal(module, signal_name);
        snprintf(signal_name, sizeof(signal_name), "_request_in__%u_rdy", index);
        profile->h_request_ready[index] = module_signal(module, signal_name);
        if (!profile->h_request_valid[index] ||
            !profile->h_request_ready[index])
            break;
        snprintf(signal_name, sizeof(signal_name),
                 "captured_pending_valid[%u]", index);
        profile->h_pending_valid[index] =
            module_signal(module, signal_name);
        snprintf(signal_name, sizeof(signal_name),
                 "captured_pending_tuple_idx_2[%u]", index);
        profile->h_pending_credit[index] =
            module_signal(module, signal_name);
        if (!profile->h_pending_valid[index] ||
            !profile->h_pending_credit[index])
            break;
        profile->request_input_count++;
    }

    /* XLS retains these source-level names in the generated SharedService
     * next-state module. They describe the post-retirement, post-admission
     * state on which ready_selection operates, so sampling them adds no
     * ports or state to the synthesized circuit. */
    for (index = 0; index < MAX_SCHEDULER_ACTORS; index++) {
        snprintf(signal_name, sizeof(signal_name), "ready__%u", index + 1);
        profile->h_ready[index] = module_signal(module, signal_name);
        if (!profile->h_ready[index])
            break;
        if (index == 0)
            snprintf(signal_name, sizeof(signal_name), "selectable");
        else
            snprintf(signal_name, sizeof(signal_name),
                     "selectable__%u", index);
        profile->h_selectable[index] =
            module_signal(module, signal_name);
        snprintf(signal_name, sizeof(signal_name),
                 "mail_candidates__4[%u]", index);
        profile->h_mail_candidate[index] =
            module_signal(module, signal_name);
        snprintf(signal_name, sizeof(signal_name),
                 "entry_probes__2[%u]", index);
        profile->h_entry_probe[index] = module_signal(module, signal_name);
        snprintf(signal_name, sizeof(signal_name), "egress_waiters[%u]", index);
        profile->h_egress_waiter[index] = module_signal(module, signal_name);
        snprintf(signal_name, sizeof(signal_name), "occupied__4[%u]", index);
        profile->h_occupied[index] = module_signal(module, signal_name);
        if (!profile->h_mail_candidate[index] ||
            !profile->h_entry_probe[index] ||
            !profile->h_egress_waiter[index] ||
            !profile->h_occupied[index])
            break;
        profile->actor_count++;
    }

    reset_latency_minima(&profile->counts);
    reset_latency_minima(&profile->checkpoint);
    return profile->h_ram_read_request &&
        profile->h_ram_read_request_valid &&
        profile->h_ram_read_request_ready &&
        profile->h_ram_read_response_valid &&
        profile->h_ram_read_response_ready &&
        profile->h_ram_write_request &&
        profile->h_ram_write_request_valid &&
        profile->h_ram_write_request_ready &&
        profile->h_ram_write_response_valid &&
        profile->h_ram_write_response_ready &&
        profile->h_mailbox_read_request &&
        profile->h_mailbox_read_request_valid &&
        profile->h_mailbox_read_request_ready &&
        profile->h_mailbox_read_response_valid &&
        profile->h_mailbox_read_response_ready &&
        profile->h_mailbox_write_request &&
        profile->h_mailbox_write_request_valid &&
        profile->h_mailbox_write_request_ready &&
        profile->h_mailbox_write_response_valid &&
        profile->h_mailbox_write_response_ready &&
        profile->h_startup_valid && profile->h_startup_ready &&
        profile->h_egress_valid && profile->h_egress_ready &&
        profile->h_egress_busy && profile->h_selection_activation &&
        profile->h_phase_boundary &&
        profile->actor_count > 0 &&
        profile->request_input_count > 0;
}

static void discover_scheduler_profiles(vpiHandle scope) {
    vpiHandle iterator = vpi_iterate(vpiModule, scope);
    vpiHandle module;

    if (!iterator)
        return;
    while ((module = vpi_scan(iterator)) != NULL) {
        const char *definition = vpi_get_str(vpiDefName, module);
        if (strstr(definition, "SharedService") &&
            scheduler_profile_count < MAX_SCHEDULERS) {
            scheduler_profile_t candidate;
            memset(&candidate, 0, sizeof(candidate));
            if (populate_scheduler_profile(&candidate, module)) {
                scheduler_profiles[scheduler_profile_count++] = candidate;
            } else {
                vpi_printf(
                    "xls_sim_bridge[profile]: incomplete scheduler at %s\n",
                    candidate.hierarchy);
            }
        }
        discover_scheduler_profiles(module);
    }
}

static void name_scheduler_profiles(void) {
    char base_names[MAX_SCHEDULERS][32];
    unsigned index;
    unsigned candidate;

    for (index = 0; index < scheduler_profile_count; index++) {
        memcpy(base_names[index], scheduler_profiles[index].name,
               sizeof(base_names[index]) - 1);
        base_names[index][sizeof(base_names[index]) - 1] = '\0';
    }

    for (index = 0; index < scheduler_profile_count; index++) {
        unsigned matching = 0;
        unsigned rank = 0;
        for (candidate = 0; candidate < scheduler_profile_count; candidate++) {
            if (strcmp(base_names[index], base_names[candidate]) != 0)
                continue;
            if (candidate < index)
                rank++;
            matching++;
        }
        if (matching > 1)
            snprintf(scheduler_profiles[index].name,
                     sizeof(scheduler_profiles[index].name), "%.27s_%u",
                     base_names[index], rank);
        vpi_printf("xls_sim_bridge[profile]: found %s scheduler at %s\n",
                   scheduler_profiles[index].name,
                   scheduler_profiles[index].hierarchy);
    }
}

static void step_scheduler_profile(scheduler_profile_t *profile) {
    scheduler_counts_t *counts = &profile->counts;
    int active = 0;
    int state_read_valid;
    int valid;
    int ready;
    int state_write_accepted;
    int state_read_accepted;
    int mailbox_write_accepted;
    int mailbox_read_accepted;
    int state_port_blocked = 0;
    int request_backpressured = 0;
    int egress_backpressured = 0;
    int any_ready = 0;
    int any_selectable = 0;
    int same_actor_only;
    int waiting_egress_credit;
    int no_actor_work;
    int egress_busy;
    int selection_activation;
    int executor_completion_blocked;
    int phase_boundary;
    uint32_t read_slot;
    unsigned mail_candidates = 0;
    unsigned entry_probes = 0;
    unsigned egress_waiters = 0;
    unsigned pending_commands = 0;
    unsigned pending_credits = 0;
    unsigned occupied_messages = 0;
    unsigned nonempty_actors = 0;
    unsigned index;

    state_read_valid = get_bit(profile->h_ram_read_request_valid);
    read_slot = get_u32(profile->h_ram_read_request);
    if (state_read_valid) {
        profile->activation_has_state_read = 1;
        profile->activation_state_read_slot = read_slot;
    }
    egress_busy = get_bit(profile->h_egress_busy);
    executor_completion_blocked =
        profile->h_completed_valid && profile->h_completed_effects_valid &&
        get_bit(profile->h_completed_valid) &&
        get_bit(profile->h_completed_effects_valid) && egress_busy;
    selection_activation = get_bit(profile->h_selection_activation);
    if (selection_activation) {
        /* In the legacy two-stage scheduler, the previous same-actor sample
         * named the one actor then in flight. These signals contain that
         * actor's post-retirement readiness and support the forwarding
         * diagnostic below. A decoupled executor can have several actors in
         * flight, so its profile deliberately skips that legacy follow-up. */
        if (profile->same_actor_followup_pending) {
            unsigned slot = profile->same_actor_followup_slot;
            int mail_candidate = get_bit(profile->h_mail_candidate[slot]);
            int entry_probe = get_bit(profile->h_entry_probe[slot]);
            int egress_waiter = get_bit(profile->h_egress_waiter[slot]);

            counts->same_actor_followups++;
            if (entry_probe) {
                counts->same_actor_followup_entry++;
            } else if (egress_waiter && !egress_busy) {
                counts->same_actor_followup_egress++;
            } else if (egress_waiter) {
                counts->same_actor_followup_waiting_egress_credit++;
            } else if (mail_candidate) {
                counts->same_actor_followup_mailbox++;
                if (!profile->same_actor_followup_phase_boundary) {
                    counts->same_actor_followup_direct_mailbox++;
                    counts->actor_direct_mailbox_followups[slot]++;
                }
            } else {
                counts->same_actor_followup_no_work++;
            }
            profile->same_actor_followup_pending = 0;
        }

        counts->selection_activations++;
        for (index = 0; index < profile->request_input_count; index++) {
            if (!get_bit(profile->h_pending_valid[index]))
                continue;
            if (get_bit(profile->h_pending_credit[index]))
                pending_credits++;
            else
                pending_commands++;
        }
        for (index = 0; index < profile->actor_count; index++) {
            int slot_ready = get_bit(profile->h_ready[index]);
            unsigned slot_occupied = get_u32(profile->h_occupied[index]);
            mail_candidates += get_bit(profile->h_mail_candidate[index]);
            entry_probes += get_bit(profile->h_entry_probe[index]);
            egress_waiters += get_bit(profile->h_egress_waiter[index]);
            occupied_messages += slot_occupied;
            if (slot_occupied != 0)
                nonempty_actors++;
            if (slot_ready) {
                any_ready = 1;
                if (profile->h_selectable[0] ?
                    get_bit(profile->h_selectable[index]) :
                    (!profile->activation_has_state_read ||
                     profile->activation_state_read_slot != index))
                    any_selectable = 1;
                counts->ready_slot_samples++;
                counts->actor_ready_samples[index]++;
            }
        }
        counts->mail_candidate_slot_samples += mail_candidates;
        counts->entry_probe_slot_samples += entry_probes;
        counts->egress_waiter_slot_samples += egress_waiters;
        counts->pending_command_slot_samples += pending_commands;
        counts->pending_credit_slot_samples += pending_credits;
        if (pending_commands != 0)
            counts->pending_command_activations++;
        if (pending_credits != 0)
            counts->pending_credit_activations++;
        counts->mailbox_occupancy_samples++;
        counts->mailbox_occupied_message_samples += occupied_messages;
        counts->mailbox_nonempty_actor_samples += nonempty_actors;
        if (occupied_messages > counts->mailbox_peak_occupied_messages)
            counts->mailbox_peak_occupied_messages = occupied_messages;
        if (nonempty_actors > counts->mailbox_peak_nonempty_actors)
            counts->mailbox_peak_nonempty_actors = nonempty_actors;
        if (egress_busy)
            counts->egress_busy_cycles++;
        if (any_ready)
            counts->selection_cycles_any_ready++;
        same_actor_only = any_ready && !any_selectable;
        waiting_egress_credit = !any_ready && egress_busy &&
            egress_waiters != 0;
        no_actor_work = !any_ready && mail_candidates == 0 &&
            entry_probes == 0 && egress_waiters == 0;
        if (executor_completion_blocked)
            counts->selection_cycles_executor_blocked++;
        else if (any_selectable)
            counts->selection_cycles_selectable++;
        else if (same_actor_only)
            counts->selection_cycles_same_actor_only++;
        else if (waiting_egress_credit)
            counts->selection_cycles_waiting_egress_credit++;
        else if (no_actor_work)
            counts->selection_cycles_no_actor_work++;
        else
            counts->selection_cycles_internal_other++;

        if (same_actor_only && !profile->h_selectable[0]) {
            unsigned slot = profile->activation_state_read_slot;
            int mail_candidate = get_bit(profile->h_mail_candidate[slot]);
            int entry_probe = get_bit(profile->h_entry_probe[slot]);
            int egress_waiter = get_bit(profile->h_egress_waiter[slot]);

            if (entry_probe)
                counts->same_actor_observed_entry++;
            else if (egress_waiter && !egress_busy)
                counts->same_actor_observed_egress++;
            else if (mail_candidate)
                counts->same_actor_observed_mailbox++;
            else
                counts->same_actor_observed_internal_other++;

            phase_boundary = get_bit(profile->h_phase_boundary);
            if (phase_boundary)
                counts->same_actor_phase_boundaries++;
            counts->actor_same_actor_only[slot]++;
            profile->same_actor_followup_pending = 1;
            profile->same_actor_followup_slot = slot;
            profile->same_actor_followup_phase_boundary = phase_boundary;
        }
        profile->activation_has_state_read = 0;
    }

    /* Commit the older visit before opening the younger one. In the 1R1W
     * pipeline both handshakes may occur on the same physical clock. */
    valid = get_bit(profile->h_ram_write_request_valid);
    ready = get_bit(profile->h_ram_write_request_ready);
    state_write_accepted = valid && ready;
    if (state_write_accepted) {
        uint64_t latency = counts->visit_open ?
            cycle_number - counts->visit_start : 0;
        counts->state_writes++;
        if (counts->visit_open && counts->visit_has_mailbox) {
            update_latency(
                latency,
                &counts->mailbox_visit_count,
                &counts->mailbox_visit_cycles,
                &counts->mailbox_visit_min,
                &counts->mailbox_visit_max);
        } else if (counts->visit_open) {
            update_latency(
                latency,
                &counts->entry_visit_count,
                &counts->entry_visit_cycles,
                &counts->entry_visit_min,
                &counts->entry_visit_max);
        }
        counts->visit_open = 0;
        counts->previous_write = cycle_number;
        counts->previous_write_valid = 1;
        active = 1;
    } else if (valid) {
        counts->state_request_stalls++;
        state_port_blocked = 1;
        active = 1;
    }

    valid = state_read_valid;
    ready = get_bit(profile->h_ram_read_request_ready);
    state_read_accepted = valid && ready;
    if (state_read_accepted) {
        counts->state_reads++;
        if (read_slot < profile->actor_count)
            counts->actor_state_reads[read_slot]++;
        if (counts->previous_state_read_valid) {
            update_latency(
                cycle_number - counts->previous_state_read,
                &counts->state_read_interval_count,
                &counts->state_read_interval_cycles,
                &counts->state_read_interval_min,
                &counts->state_read_interval_max);
        }
        counts->previous_state_read = cycle_number;
        counts->previous_state_read_valid = 1;
        if (counts->previous_write_valid) {
            update_latency(
                cycle_number - counts->previous_write,
                &counts->intervisit_count,
                &counts->intervisit_cycles,
                &counts->intervisit_min,
                &counts->intervisit_max);
        }
        counts->visit_start = cycle_number;
        counts->visit_open = 1;
        counts->visit_has_mailbox = 0;
        active = 1;
    } else if (valid) {
        counts->state_request_stalls++;
        state_port_blocked = 1;
        active = 1;
    }
    if (state_write_accepted && state_read_accepted) {
        counts->state_read_write_overlaps++;
        if (get_u32(profile->h_ram_read_request) ==
            get_high_u32(profile->h_ram_write_request))
            counts->state_same_address_overlaps++;
    }
    if (get_bit(profile->h_ram_read_response_valid) &&
        get_bit(profile->h_ram_read_response_ready)) {
        counts->state_responses++;
        active = 1;
    }
    if (get_bit(profile->h_ram_write_response_valid) &&
        get_bit(profile->h_ram_write_response_ready)) {
        counts->state_write_completions++;
        active = 1;
    }

    valid = get_bit(profile->h_mailbox_write_request_valid);
    ready = get_bit(profile->h_mailbox_write_request_ready);
    mailbox_write_accepted = valid && ready;
    if (mailbox_write_accepted) {
        counts->mailbox_writes++;
        active = 1;
    } else if (valid) {
        counts->mailbox_request_stalls++;
        active = 1;
    }

    valid = get_bit(profile->h_mailbox_read_request_valid);
    ready = get_bit(profile->h_mailbox_read_request_ready);
    mailbox_read_accepted = valid && ready;
    if (mailbox_read_accepted) {
        counts->mailbox_reads++;
        if (counts->visit_open)
            counts->visit_has_mailbox = 1;
        active = 1;
    } else if (valid) {
        counts->mailbox_request_stalls++;
        active = 1;
    }
    if (mailbox_write_accepted && mailbox_read_accepted) {
        counts->mailbox_read_write_overlaps++;
        if (get_u32(profile->h_mailbox_read_request) ==
            get_high_u32(profile->h_mailbox_write_request))
            counts->mailbox_same_address_overlaps++;
    }
    if (get_bit(profile->h_mailbox_read_response_valid) &&
        get_bit(profile->h_mailbox_read_response_ready)) {
        counts->mailbox_responses++;
        active = 1;
    }
    if (get_bit(profile->h_mailbox_write_response_valid) &&
        get_bit(profile->h_mailbox_write_response_ready)) {
        counts->mailbox_write_completions++;
        active = 1;
    }

    for (index = 0; index < profile->request_input_count; index++) {
        valid = get_bit(profile->h_request_valid[index]);
        ready = get_bit(profile->h_request_ready[index]);
        if (valid && ready) {
            counts->requests++;
            active = 1;
        } else if (valid) {
            counts->request_stalls++;
            request_backpressured = 1;
            active = 1;
        }
    }
    if (get_bit(profile->h_startup_valid) &&
        get_bit(profile->h_startup_ready)) {
        counts->startup_requests++;
        active = 1;
    }

    valid = get_bit(profile->h_egress_valid);
    ready = get_bit(profile->h_egress_ready);
    if (valid && ready) {
        counts->egresses++;
        active = 1;
    } else if (valid) {
        counts->egress_stalls++;
        egress_backpressured = 1;
        active = 1;
    }
    if (active)
        counts->active_cycles++;

    /* These buckets are deliberately mutually exclusive. They classify the
     * externally visible condition on clocks where the scheduler does not
     * launch a state read; they do not claim that backpressure is necessarily
     * the internal cause of the missing issue. */
    if (state_read_accepted)
        counts->issue_cycles++;
    else if (state_port_blocked)
        counts->no_issue_state_port_blocked++;
    else if (egress_backpressured)
        counts->no_issue_egress_backpressured++;
    else if (request_backpressured)
        counts->no_issue_request_backpressured++;
    else
        counts->no_issue_without_visible_backpressure++;

}

static void checkpoint_scheduler_profiles(void) {
    unsigned index;
    for (index = 0; index < scheduler_profile_count; index++)
        scheduler_profiles[index].checkpoint =
            scheduler_profiles[index].counts;
    scheduler_profile_checkpoint_cycle = cycle_number;
    scheduler_profile_checkpoint_valid = 1;
}

static PLI_INT32 cb_readwrite(p_cb_data cb) {
    (void)cb;
    apply_drives(&app_endpoint);
    apply_drives(&debug_endpoint);
    return 0;
}

static PLI_INT32 cb_readonly(p_cb_data cb) {
    unsigned profile_index;
    unsigned app_output_before;
    int app_armed_before;
    (void)cb;
    if (!get_bit(h_clk)) {
        if (app_endpoint.enabled) {
            app_endpoint.s_ready_sample = get_bit(app_endpoint.h_s_ready);
            app_endpoint.m_data_sample = get_u32(app_endpoint.h_m_data);
            app_endpoint.m_valid_sample = get_bit(app_endpoint.h_m_valid);
        }
        if (debug_endpoint.enabled) {
            debug_endpoint.s_ready_sample = get_bit(debug_endpoint.h_s_ready);
            debug_endpoint.m_data_sample = get_u32(debug_endpoint.h_m_data);
            debug_endpoint.m_valid_sample = get_bit(debug_endpoint.h_m_valid);
        }
        return 0;
    }

    pump_input(&app_endpoint);
    pump_input(&debug_endpoint);
    pump_output(&app_endpoint);
    pump_output(&debug_endpoint);

    if (!get_bit(h_resetn)) {
        cycle_number = 0;
        reset_endpoint(&app_endpoint);
        reset_endpoint(&debug_endpoint);
        scheduler_profile_started = 0;
        reset_scheduler_profile_counts();
        return 0;
    }

    cycle_number++;
    app_output_before = app_endpoint.output_beat_number;
    app_armed_before = app_endpoint.output_armed;
    step_endpoint(&app_endpoint);
    step_endpoint(&debug_endpoint);
    if (scheduler_profile_enabled && scheduler_profile_only &&
        !scheduler_profile_started) {
        reset_scheduler_profile_counts();
        scheduler_profile_start_cycle = cycle_number;
        scheduler_profile_started = 1;
    } else if (scheduler_profile_enabled &&
        !app_armed_before && app_endpoint.output_armed) {
        reset_scheduler_profile_counts();
        scheduler_profile_start_cycle = cycle_number;
        scheduler_profile_started = 1;
    }
    if (scheduler_profile_started) {
        for (profile_index = 0;
             profile_index < scheduler_profile_count;
             profile_index++)
            step_scheduler_profile(&scheduler_profiles[profile_index]);
        if (app_endpoint.output_beat_number != app_output_before) {
            checkpoint_scheduler_profiles();
            write_scheduler_profile();
        } else if ((cycle_number - scheduler_profile_start_cycle) % 1000 == 0) {
            write_scheduler_profile();
        }
    }
    return 0;
}

static PLI_INT32 cb_end_of_sim(p_cb_data cb) {
    (void)cb;
    if (scheduler_profile_started) {
        checkpoint_scheduler_profiles();
        write_scheduler_profile();
    }
    return 0;
}

static PLI_INT32 cb_clk_change(p_cb_data cb) {
    (void)cb;
    schedule_sync_cb(cbReadOnlySynch, cb_readonly);
    schedule_sync_cb(cbReadWriteSynch, cb_readwrite);
    return 0;
}

static vpiHandle find_signal(const char *name) {
    char path[PATH_SIZE];
    snprintf(path, sizeof(path), "%s.%s", hierarchy_root, name);
    return vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
}

static int find_endpoint_signals(
    axis_endpoint_t *endpoint,
    const char *s_prefix,
    const char *m_prefix
) {
    char name[128];
#define FIND(handle, prefix, suffix) do { \
    snprintf(name, sizeof(name), "%s_%s", prefix, suffix); \
    endpoint->handle = find_signal(name); \
} while (0)
    FIND(h_s_data, s_prefix, "tdata");
    FIND(h_s_valid, s_prefix, "tvalid");
    FIND(h_s_ready, s_prefix, "tready");
    FIND(h_s_last, s_prefix, "tlast");
    FIND(h_m_data, m_prefix, "tdata");
    FIND(h_m_valid, m_prefix, "tvalid");
    FIND(h_m_ready, m_prefix, "tready");
#undef FIND
    return endpoint->h_s_data && endpoint->h_s_valid && endpoint->h_s_ready &&
           endpoint->h_s_last && endpoint->h_m_data && endpoint->h_m_valid &&
           endpoint->h_m_ready;
}

static int open_fifo(const char *path) {
    int fd;
    if (unlink(path) != 0 && errno != ENOENT) {
        vpi_printf("xls_sim_bridge: cannot remove %s: %s\n", path, strerror(errno));
        return -1;
    }
    if (mkfifo(path, 0600) != 0) {
        vpi_printf("xls_sim_bridge: cannot create %s: %s\n", path, strerror(errno));
        return -1;
    }
    fd = open(path, O_RDWR | O_NONBLOCK);
    if (fd < 0)
        vpi_printf("xls_sim_bridge: cannot open %s: %s\n", path, strerror(errno));
    return fd;
}

static int open_endpoint_fifos(
    axis_endpoint_t *endpoint,
    const char *directory,
    const char *prefix
) {
    char host_to_sim[PATH_SIZE];
    char sim_to_host[PATH_SIZE];
    snprintf(host_to_sim, sizeof(host_to_sim), "%s/%s_tx", directory, prefix);
    snprintf(sim_to_host, sizeof(sim_to_host), "%s/%s_rx", directory, prefix);
    endpoint->fd_host_to_sim = open_fifo(host_to_sim);
    endpoint->fd_sim_to_host = open_fifo(sim_to_host);
    return endpoint->fd_host_to_sim >= 0 && endpoint->fd_sim_to_host >= 0;
}

static PLI_INT32 cb_start_of_sim(p_cb_data cb) {
    const char *directory = getenv("ERL_HLS_SIM_DIR");
    const char *configured_root = getenv("ERL_HLS_SIM_TOP");
    const char *app_only_value = getenv("ERL_HLS_SIM_APP_ONLY");
    const char *profile_only_value = getenv("ERL_HLS_SIM_PROFILE_ONLY");
    const char *configured_scheduler_profile_path =
        getenv("ERL_HLS_SIM_SCHEDULER_PROFILE");
    int app_only = app_only_value && strcmp(app_only_value, "1") == 0;
    s_cb_data clock_cb;
    s_cb_data end_cb;
    (void)cb;

    scheduler_profile_only = profile_only_value &&
        strcmp(profile_only_value, "1") == 0;
    if (!directory && !scheduler_profile_only) {
        vpi_printf("xls_sim_bridge: ERL_HLS_SIM_DIR is not set\n");
        return 0;
    }

    memset(&app_endpoint, 0, sizeof(app_endpoint));
    memset(&debug_endpoint, 0, sizeof(debug_endpoint));
    memset(scheduler_profiles, 0, sizeof(scheduler_profiles));
    scheduler_profile_count = 0;
    scheduler_profile_started = 0;
    scheduler_profile_checkpoint_valid = 0;
    scheduler_profile_enabled = 0;
    scheduler_profile_path[0] = '\0';
    hierarchy_root = configured_root && configured_root[0] != '\0' ?
        configured_root : "regsvc_bridge_tb";
    app_endpoint.name = "app";
    app_endpoint.enabled = !scheduler_profile_only;
    debug_endpoint.name = "debug";
    debug_endpoint.enabled = !scheduler_profile_only && !app_only;
    h_clk = find_signal("clk");
    h_resetn = find_signal("resetn");
    if (!h_clk || !h_resetn ||
        (app_endpoint.enabled &&
         !find_endpoint_signals(&app_endpoint, "s_axis", "m_axis")) ||
        (debug_endpoint.enabled &&
         !find_endpoint_signals(&debug_endpoint, "s_dbg", "m_dbg"))) {
        vpi_printf("xls_sim_bridge: failed to find %s AXIS signals\n",
                   hierarchy_root);
        return 0;
    }

    if (configured_scheduler_profile_path &&
        configured_scheduler_profile_path[0] != '\0') {
        int profile_fd;
        snprintf(scheduler_profile_path, sizeof(scheduler_profile_path),
                 "%s", configured_scheduler_profile_path);
        profile_fd = open(
            scheduler_profile_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (profile_fd < 0) {
            vpi_printf("xls_sim_bridge[profile]: cannot open %s: %s\n",
                       scheduler_profile_path, strerror(errno));
        } else {
            close(profile_fd);
            scheduler_profile_enabled = 1;
            discover_scheduler_profiles(NULL);
            name_scheduler_profiles();
            if (scheduler_profile_count == 0) {
                vpi_printf(
                    "xls_sim_bridge[profile]: no SharedService instances found\n");
                scheduler_profile_enabled = 0;
            }
        }
    }

    if ((app_endpoint.enabled &&
         !open_endpoint_fifos(&app_endpoint, directory, "app")) ||
        (debug_endpoint.enabled &&
         !open_endpoint_fifos(&debug_endpoint, directory, "debug"))) {
        vpi_printf("xls_sim_bridge: failed to open transport FIFOs\n");
        return 0;
    }

    reset_endpoint(&app_endpoint);
    reset_endpoint(&debug_endpoint);
    schedule_sync_cb(cbReadWriteSynch, cb_readwrite);

    memset(&clock_cb, 0, sizeof(clock_cb));
    clock_cb.reason = cbValueChange;
    clock_cb.cb_rtn = cb_clk_change;
    clock_cb.obj = h_clk;
    vpi_register_cb(&clock_cb);
    memset(&end_cb, 0, sizeof(end_cb));
    end_cb.reason = cbEndOfSimulation;
    end_cb.cb_rtn = cb_end_of_sim;
    vpi_register_cb(&end_cb);
    if (scheduler_profile_only) {
        vpi_printf("xls_sim_bridge: scheduler-only profiling enabled\n");
    } else {
        vpi_printf("xls_sim_bridge: application%s endpoint%s listening in %s\n",
                   debug_endpoint.enabled ? " and debug" : "",
                   debug_endpoint.enabled ? "s" : "", directory);
    }
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
