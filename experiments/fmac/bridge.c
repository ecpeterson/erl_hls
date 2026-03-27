#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <stdlib.h>
#include <unistd.h>

#include "vpi_user.h"

/* ===================== Shared memory ===================== */
// these probably ought to be __attribute__((packed)) but i didn't work to sort
// out how to make it compatible with the copy op further down.
typedef struct {
  uint64_t b;
  uint64_t a;
  uint64_t op;  // only uses lowest bit, but may as well stay aligned
} req_t;

typedef struct {
  // these are only ever read by the bridge
  volatile uint64_t seq_in;
  volatile req_t req;

  // these are only ever written by the bridge
  volatile uint64_t seq_out;
  volatile uint64_t out;
  volatile uint64_t state;  // cloned from the bridge's `st` variable
} shm_regs_t;

static const char *SHM_NAME = "/xls_fmac_shm";
static shm_regs_t *g_shm = NULL;

/* ===================== VPI handles ===================== */
static vpiHandle h_clk = NULL, h_reset = NULL;
static vpiHandle h_req = NULL, h_req_vld = NULL, h_req_rdy = NULL;
static vpiHandle h_out = NULL, h_out_vld = NULL, h_out_rdy = NULL;

/* ===================== Helpers ===================== */
static uint32_t get_u32(vpiHandle sig) {
  s_vpi_value v;
  v.format = vpiIntVal;
  vpi_get_value(sig, &v);
  return (uint32_t)v.value.integer;
}

/* Robust for 1-bit nets */
static int get_bit(vpiHandle sig) {
  s_vpi_value v;
  v.format = vpiIntVal;
  vpi_get_value(sig, &v);
  return (v.value.integer & 1) ? 1 : 0;
}

static uint64_t get_u64(vpiHandle sig) {
  // vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
  // vpiHandle arg = vpi_iterate(vpiArgument, systf);
  // vpiHandle sig = vpi_scan(arg);

  s_vpi_value v;
  v.format = vpiVectorVal;
  vpi_get_value(sig, &v);

  uint64_t high = v.value.vector[1].aval; // Bits 63:32
  uint64_t low = v.value.vector[0].aval;  // Bits 31:0
  uint64_t total_val = (high << 32) | (low & 0xFFFFFFFF);

  return total_val;
}

static void put_u32(vpiHandle sig, uint32_t x) {
  s_vpi_value v;
  v.format = vpiIntVal;
  v.value.integer = (PLI_INT32)x;
  vpi_put_value(sig, &v, NULL, vpiNoDelay);
}

static void put_bit(vpiHandle sig, int bit) {
  s_vpi_value v;
  v.format = vpiScalarVal;
  v.value.scalar = bit ? vpi1 : vpi0;
  vpi_put_value(sig, &v, NULL, vpiNoDelay);
}

static void put_u64(vpiHandle sig, uint64_t x) {
  s_vpi_value v;
  s_vpi_vecval vec[2];

  vec[0].aval = (uint32_t)(x & 0xFFFFFFFF); // Lower 32 bits
  vec[0].bval = 0; // No X/Z
  vec[1].aval = (uint32_t)((x >> 32) & 0xFFFFFFFF); // Upper 32 bits
  vec[1].bval = 0; // No X/Z

  v.format = vpiVectorVal;
  v.value.vector = vec;

  vpi_put_value(sig, &v, NULL, vpiNoDelay);
}

static void put_req_t(vpiHandle sig, req_t* x) {
  s_vpi_value v;
  v.format = vpiVectorVal;

  int bytes_upper_bound = sizeof(req_t) + sizeof(uint32_t) - 1;
  int dwords_round_up = bytes_upper_bound / sizeof(uint32_t);
  s_vpi_vecval *vec = malloc(dwords_round_up * sizeof(s_vpi_vecval));

  volatile uint32_t *raw = (volatile uint32_t *)x;

  for (int i = 0; i < dwords_round_up; i++) {
    vec[i].aval = raw[i];
    vec[i].bval = 0;
  }

  v.value.vector = vec;
  vpi_put_value(sig, &v, NULL, vpiNoDelay);

  free(vec);
  return;
}

// Source - https://stackoverflow.com/a/54965696
volatile void *memcpy_v(volatile void *restrict dest,
            const volatile void *restrict src, size_t n) {
    const volatile unsigned char *src_c = src;
    volatile unsigned char *dest_c      = dest;

    while (n > 0) {
        n--;
        dest_c[n] = src_c[n];
    }
    return  dest;
}

/* ===================== SHM init ===================== */
static void init_shm(void) {
  int fd = shm_open(SHM_NAME, O_CREAT | O_RDWR, 0600);
  if (fd < 0) { perror("shm_open"); return; }
  if (ftruncate(fd, (off_t)sizeof(shm_regs_t)) != 0) { perror("ftruncate"); close(fd); return; }

  void *p = mmap(NULL, sizeof(shm_regs_t), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  close(fd);
  if (p == MAP_FAILED) { perror("mmap"); return; }

  g_shm = (shm_regs_t*)p;
  g_shm->seq_in = 0;
  g_shm->req.op = 0;
  g_shm->req.a = 0;
  g_shm->req.b = 0;
  g_shm->seq_out = 0;
  g_shm->out = 0;
  g_shm->state = 0;
}

/* ===================== Handle lookup ===================== */
static void find_signals(void) {
  h_clk   = vpi_handle_by_name((PLI_BYTE8*)"tb.clk", NULL);
  h_reset = vpi_handle_by_name((PLI_BYTE8*)"tb.reset", NULL);

  h_req     = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__wire_req", NULL);
  h_req_vld = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__wire_req_vld", NULL);
  h_req_rdy = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__wire_req_rdy", NULL);

  h_out     = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__output", NULL);
  h_out_vld = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__output_vld", NULL);
  h_out_rdy = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__output_rdy", NULL);

  if (!h_clk || !h_reset ||
      !h_req || !h_req_vld || !h_req_rdy ||
      !h_out || !h_out_vld || !h_out_rdy) {
    vpi_printf("VPI bridge: ERROR: failed to find one or more signals. Check tb.* names.\n");
  }
}

/* ===================== Drive bundle ===================== */
typedef struct {
  req_t req;
  int req_vld;
  int out_rdy;
} drives_t;

static drives_t drv;

/* ===================== Bridge FSM ===================== */
typedef enum {
  ST_IDLE = 2,
  ST_SEND = 3,
  ST_WAIT = 4,
  ST_COOL = 5
} st_t;

static st_t st = ST_IDLE;
static uint32_t cur_seq = 0;
static int cool_count = 0;

/* ===================== Sync callback scheduler ===================== */
static void schedule_sync_cb(PLI_INT32 reason, PLI_INT32 (*fn)(p_cb_data)) {
  static s_vpi_time t;
  t.type = vpiSimTime;
  t.high = 0;
  t.low  = 0;

  s_cb_data cb;
  memset(&cb, 0, sizeof(cb));
  cb.reason = reason;
  cb.cb_rtn = fn;
  cb.time   = &t;             // REQUIRED by Icarus for sync callbacks
  vpi_register_cb(&cb);
}

/* ===================== RW: apply drives ===================== */
static PLI_INT32 cb_readwrite(p_cb_data cb) {
  (void)cb;

  put_req_t(h_req, &drv.req);
  put_bit(h_req_vld, drv.req_vld);

  put_bit(h_out_rdy, drv.out_rdy);

  return 0;
}

/* ===================== RO: sample + update state and drv ===================== */
static PLI_INT32 cb_readonly(p_cb_data cb) {
  (void)cb;

  /* Only run on posedge */
  if (!get_bit(h_clk)) return 0;

  /* Only run if we passed init */
  if (!g_shm) return 0;

  /* Defaults every cycle */
  drv.out_rdy = 1;

  /* If global reset, reinitialize deterministically */
  if (get_bit(h_reset)) {
    st = ST_IDLE;
    cur_seq = 0;
    cool_count = 0;

    drv.req.a = 0;
    drv.req.b = 0;
    drv.req.op = 0;
    drv.req_vld = 0;

    g_shm->state = st;
    return 0;
  }

  switch (st) {
    case ST_IDLE: {
      // not yet ready to transmit
      drv.req_vld = 0;

      // do we have a new message?
      uint32_t seq_in = g_shm->seq_in;
      if (
        seq_in != cur_seq  // input not yet ingested
        && cur_seq == g_shm->seq_out  // previous request completed
      ) {
        // then get ready to send
        cur_seq = seq_in;
        memcpy_v(&drv.req, &g_shm->req, sizeof(req_t));
        drv.req_vld = 1;

        st = ST_SEND;
      }
      break;
    }

    case ST_SEND: {
      /* Keep valids asserted together until BOTH rdys are 1 at a posedge */

      int req_rdy = get_bit(h_req_rdy);

      if (req_rdy) {
        /* Request accepted this cycle; drop valid for next cycle */
        drv.req_vld = 0;
        st = ST_WAIT;
      }
      break;
    }

    case ST_WAIT: {
      if (get_bit(h_out_vld)) {
        g_shm->out = get_u64(h_out);
        g_shm->seq_out = cur_seq;

        /* Cooldown: keep valids low for 2 cycles to clear DUT’s internal valid_regs */
        cool_count = 2;
        st = ST_COOL;
      }
      break;
    }

    case ST_COOL: {
      if (cool_count-- == 0)
        st = ST_IDLE;
      break;
    }

    default:
      st = ST_IDLE;
      break;
  }

  g_shm->state = st;
  return 0;
}

/* ===================== clk change callback: schedule RO then RW ===================== */
static PLI_INT32 cb_clk_change(p_cb_data cb) {
  (void)cb;
  schedule_sync_cb(cbReadOnlySynch,  cb_readonly);
  schedule_sync_cb(cbReadWriteSynch, cb_readwrite);
  return 0;
}

/* ===================== Start-of-sim ===================== */
static PLI_INT32 cb_start_of_sim(p_cb_data cb) {
  (void)cb;

  init_shm();
  find_signals();

  memset(&drv, 0, sizeof(drv));
  drv.out_rdy = 1;

  /* Apply initial drives once */
  schedule_sync_cb(cbReadWriteSynch, cb_readwrite);

  /* Register clk change callback */
  s_cb_data cbc;
  memset(&cbc, 0, sizeof(cbc));
  cbc.reason = cbValueChange;
  cbc.cb_rtn = cb_clk_change;
  cbc.obj    = h_clk;

  if (!vpi_register_cb(&cbc)) {
    vpi_printf("VPI bridge: ERROR: failed to register clk callback\n");
  } else {
    vpi_printf("VPI bridge: active. shm name = %s\n", SHM_NAME);
  }
  return 0;
}

static void entry_point(void) {
  /* Don’t touch design during registration; just register start-of-sim callback */
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
