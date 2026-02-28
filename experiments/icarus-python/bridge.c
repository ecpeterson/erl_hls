#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

#include "vpi_user.h"

/* ===================== Shared memory ===================== */
typedef struct __attribute__((packed)) {
  volatile uint32_t seq_in;
  volatile uint64_t a;
  volatile uint64_t b;

  volatile uint32_t seq_out;
  volatile uint64_t out;

  // NOTE: this describes the state of the bridge, not of anything in icarus
  // 0 idle, 1 send, 2 wait out, 3 cooldown, 9 init, 10 init done
  volatile uint32_t state;
} shm_regs_t;

static const char *SHM_NAME = "/xls_fmac_shm";
static shm_regs_t *g_shm = NULL;

/* ===================== VPI handles ===================== */
static vpiHandle h_clk = NULL;
static vpiHandle h_reset = NULL;

static vpiHandle h_a = NULL, h_a_vld = NULL, h_a_rdy = NULL;
static vpiHandle h_b = NULL, h_b_vld = NULL, h_b_rdy = NULL;

static vpiHandle h_out = NULL, h_out_vld = NULL, h_out_rdy = NULL;

static vpiHandle h_srst = NULL, h_srst_vld = NULL, h_srst_rdy = NULL; /* rdy not used */

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
  g_shm->a = 0;
  g_shm->b = 0;
  g_shm->seq_out = 0;
  g_shm->out = 0;
  g_shm->state = 0;
}

/* ===================== Handle lookup ===================== */
static void find_signals(void) {
  h_clk   = vpi_handle_by_name((PLI_BYTE8*)"tb.clk", NULL);
  h_reset = vpi_handle_by_name((PLI_BYTE8*)"tb.reset", NULL);

  h_a     = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__input_a", NULL);
  h_a_vld = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__input_a_vld", NULL);
  h_a_rdy = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__input_a_rdy", NULL);

  h_b     = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__input_b", NULL);
  h_b_vld = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__input_b_vld", NULL);
  h_b_rdy = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__input_b_rdy", NULL);

  h_out     = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__output", NULL);
  h_out_vld = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__output_vld", NULL);
  h_out_rdy = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__output_rdy", NULL);

  h_srst     = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__reset", NULL);
  h_srst_vld = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__reset_vld", NULL);
  h_srst_rdy = vpi_handle_by_name((PLI_BYTE8*)"tb.fp64_fmac__reset_rdy", NULL);

  if (!h_clk || !h_reset ||
      !h_a || !h_a_vld || !h_a_rdy ||
      !h_b || !h_b_vld || !h_b_rdy ||
      !h_out || !h_out_vld || !h_out_rdy ||
      !h_srst || !h_srst_vld || !h_srst_rdy) {
    vpi_printf("VPI bridge: ERROR: failed to find one or more signals. Check tb.* names.\n");
  }
}

/* ===================== Drive bundle ===================== */
typedef struct {
  uint64_t a;
  uint64_t b;
  int a_vld;
  int b_vld;
  int out_rdy;
  uint64_t srst;
  int srst_vld;
} drives_t;

static drives_t drv;

/* ===================== Bridge FSM ===================== */
typedef enum {
  ST_INIT0 = 0,
  ST_INIT1 = 1,
  ST_IDLE  = 2,
  ST_SEND  = 3,
  ST_WAITO = 4,
  ST_COOL  = 5
} st_t;

static st_t st = ST_INIT0;
static uint32_t cur_seq = 0;
static uint64_t pending_a = 0, pending_b = 0;
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

  put_u64(h_a, drv.a);
  put_u64(h_b, drv.b);
  put_bit(h_a_vld, drv.a_vld);
  put_bit(h_b_vld, drv.b_vld);

  put_bit(h_out_rdy, drv.out_rdy);

  put_bit(h_srst, drv.srst);
  put_bit(h_srst_vld, drv.srst_vld);

  return 0;
}

/* ===================== RO: sample + update state and drv ===================== */
static PLI_INT32 cb_readonly(p_cb_data cb) {
  (void)cb;

  /* Only run on posedge */
  if (!get_bit(h_clk)) return 0;

  /* Defaults every cycle */
  drv.out_rdy = 1;
  drv.srst = 0;      /* IMPORTANT: 1 forces output masked to 0 in this RTL */
  drv.srst_vld = 1;

  /* If global reset, reinitialize deterministically */
  if (get_bit(h_reset)) {
    st = ST_INIT0;
    cur_seq = 0;
    pending_a = pending_b = 0;
    cool_count = 0;

    drv.a = 0;
    drv.b = 0;
    drv.a_vld = 0;
    drv.b_vld = 0;
    drv.srst = 0;
    drv.srst_vld = 1;

    if (g_shm) g_shm->state = 0;
    return 0;
  }

  if (!g_shm) return 0;

  switch (st) {
    case ST_INIT0:
      /* Assert reset channel valid for a full cycle (don’t wait for rdy) */
      /*
      drv.srst = 0;
      drv.srst_vld = 1;
      drv.a_vld = 0;
      drv.b_vld = 0;
      g_shm->state = 9;
      st = ST_INIT1;
      break;
      */

    case ST_INIT1:
      /* Drop reset_vld; now design should be enabled */
      /*
      drv.srst = 0;
      drv.srst_vld = 1;
      drv.a_vld = 0;
      drv.b_vld = 0;
      g_shm->state = 10;
      st = ST_IDLE;
      break;
      */

    case ST_IDLE: {
      g_shm->state = 0;
      drv.a_vld = 0;
      drv.b_vld = 0;

      uint32_t seq_in = g_shm->seq_in;
      if (seq_in != g_shm->seq_out && seq_in != cur_seq) {
        cur_seq = seq_in;
        pending_a = g_shm->a;
        pending_b = g_shm->b;

        drv.a = pending_a;
        drv.b = pending_b;
        drv.a_vld = 1;
        drv.b_vld = 1;

        g_shm->state = 1;
        st = ST_SEND;
      }
      break;
    }

    case ST_SEND: {
      g_shm->state = 1;

      /* Keep valids asserted together until BOTH rdys are 1 at a posedge */
      drv.a = pending_a;
      drv.b = pending_b;
      drv.a_vld = 1;
      drv.b_vld = 1;

      int a_rdy = get_bit(h_a_rdy);
      int b_rdy = get_bit(h_b_rdy);

      if (a_rdy && b_rdy) {
        /* Pair accepted this cycle; drop valids for next cycle */
        drv.a_vld = 0;
        drv.b_vld = 0;
        st = ST_WAITO;
        g_shm->state = 2;
      }
      break;
    }

    case ST_WAITO: {
      g_shm->state = 2;

      /* Keep valids low while waiting for output */
      drv.a_vld = 0;
      drv.b_vld = 0;

      if (get_bit(h_out_vld)) {
        g_shm->out = get_u64(h_out);
        g_shm->seq_out = cur_seq;

        /* Cooldown: keep valids low for 2 cycles to clear DUT’s internal valid_regs */
        cool_count = 2;
        st = ST_COOL;
        g_shm->state = 3;
      }
      break;
    }

    case ST_COOL: {
      g_shm->state = 3;
      drv.a_vld = 0;
      drv.b_vld = 0;

      if (cool_count > 0) cool_count--;
      if (cool_count == 0) {
        st = ST_IDLE;
        g_shm->state = 0;
      }
      break;
    }

    default:
      st = ST_IDLE;
      break;
  }

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
  drv.a_vld = 0;
  drv.b_vld = 0;
  drv.srst = 0;
  drv.srst_vld = 0;

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

