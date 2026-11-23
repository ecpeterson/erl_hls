/* Unix-socket RPC for a bus-driving testbench; never access DUT internals. */
#define _POSIX_C_SOURCE 200809L
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/un.h>
#include "vpi_user.h"
#include "protocol.h"

/* One request/reply pair owns the connection until the testbench completes it. */
static int connection = -1, pending;
static uint32_t sequence, operation;

/* A broken bridge must fail the run instead of fabricating successful transfers. */
static void failed(const char *reason)
{
    fprintf(stderr, "Icarus co-simulation: %s (%s)\n", reason, strerror(errno));
    exit(1);
}

/* Accept one QEMU instance at a new private path; never unlink an existing socket. */
static void connect_qemu(void)
{
    const char *path = getenv("HLS_COSIM_SOCKET");
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    int listener = socket(AF_UNIX, SOCK_STREAM, 0);
    if (!path || strlen(path) >= sizeof(address.sun_path) || listener < 0) {
        errno = EINVAL; failed("socket configuration");
    }
    strcpy(address.sun_path, path);
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) ||
        chmod(path, 0600) || listen(listener, 1)) failed("listen");
    struct pollfd wait = {.fd = listener, .events = POLLIN};
    if (poll(&wait, 1, 20000) != 1) { errno = ETIMEDOUT; failed("accept timeout"); }
    connection = accept(listener, NULL, NULL);
    close(listener);
    if (connection < 0) failed("accept");
#ifdef SO_NOSIGPIPE
    int yes = 1;
    if (setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes))) failed("SIGPIPE option");
#endif
}

/* Resolve exactly four testbench arguments, rejecting malformed system-task calls. */
static void arguments(vpiHandle call, vpiHandle args[4])
{
    vpiHandle iterator = vpi_iterate(vpiArgument, call);
    for (unsigned i = 0; i < 4; i++) {
        if (!iterator || !(args[i] = vpi_scan(iterator))) {
            errno = EINVAL; failed("expected four arguments");
        }
    }
    if (vpi_scan(iterator)) { errno = EINVAL; failed("extra argument"); }
}

/* Assign one known u32 to an output argument or function result. */
static void put_value(vpiHandle handle, uint32_t word)
{
    s_vpi_value value = {.format = vpiIntVal};
    value.value.integer = (PLI_INT32)word;
    vpi_put_value(handle, &value, NULL, vpiNoDelay);
}

/* Receive a command at a quiescent testbench boundary; EOF ends the simulation. */
static PLI_INT32 next_request(PLI_BYTE8 *unused)
{
    (void)unused;
    vpiHandle call = vpi_handle(vpiSysTfCall, NULL), args[4];
    uint8_t packet[COSIM_BYTES];
    arguments(call, args);
    if (connection < 0) connect_qemu();
    if (pending) { errno = EPROTO; failed("missing reply"); }
    int result = cosim_transfer(connection, packet, 0);
    if (result < 0) failed("receive");
    if (!result) { put_value(call, 0); return 0; }
    operation = cosim_get(packet + 8);
    uint32_t amount = cosim_get(packet + 24);
    if (cosim_get(packet) != COSIM_MAGIC || cosim_get(packet + 4) != COSIM_VERSION ||
        cosim_get(packet + 12) != sequence + 1 || cosim_get(packet + 28) ||
        operation < COSIM_READ || operation > COSIM_RESET ||
        ((operation == COSIM_READ || operation == COSIM_WRITE) && amount != 4) ||
        (operation == COSIM_STEP && (!amount || amount > 4096))) {
        errno = EPROTO; failed("invalid request");
    }
    sequence++;
    pending = 1;
    /* Arguments are operation, address, write data, amount. */
    put_value(args[0], operation);
    put_value(args[1], cosim_get(packet + 16));
    put_value(args[2], cosim_get(packet + 20));
    put_value(args[3], amount);
    put_value(call, 1);
    return 0;
}

/* Send the bus response, sampled IRQ level and cycles; reject unknown RTL values. */
static PLI_INT32 send_reply(PLI_BYTE8 *unused)
{
    (void)unused;
    vpiHandle args[4];
    uint8_t packet[COSIM_BYTES] = {0};
    arguments(vpi_handle(vpiSysTfCall, NULL), args);
    if (!pending) { errno = EPROTO; failed("unsolicited reply"); }
    cosim_put(packet, COSIM_MAGIC); cosim_put(packet + 4, COSIM_VERSION);
    cosim_put(packet + 8, operation | COSIM_REPLY); cosim_put(packet + 12, sequence);
    for (unsigned i = 0; i < 4; i++) {
        s_vpi_value value = {.format = vpiVectorVal};
        vpi_get_value(args[i], &value);
        if (value.value.vector[0].bval) { errno = EPROTO; failed("unknown RTL response"); }
        cosim_put(packet + 16 + 4*i, value.value.vector[0].aval);
    }
    if (cosim_transfer(connection, packet, 1) != 1) failed("send");
    pending = 0;
    return 0;
}

/* Register the only two simulator entry points used by the bus driver. */
static void register_bridge(void)
{
    s_vpi_systf_data next = {.type = vpiSysFunc, .sysfunctype = vpiIntFunc,
        .tfname = "$cosim_next", .calltf = next_request};
    s_vpi_systf_data reply = {.type = vpiSysTask, .tfname = "$cosim_reply", .calltf = send_reply};
    vpi_register_systf(&next); vpi_register_systf(&reply);
}

void (*vlog_startup_routines[])(void) = {register_bridge, NULL};
