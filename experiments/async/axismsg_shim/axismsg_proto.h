#ifndef AXISMSG_PROTO_H
#define AXISMSG_PROTO_H

#ifdef __KERNEL__
#include <linux/types.h>
#else
#include <stdint.h>
#endif

/*
 * Word 0:
 *   [31:24] opcode
 *   [23:16] flags
 *   [15:8]  txid
 *   [7:0]   payload_words (number of words after header)
 */

#define AXISMSG_HDR(op, flags, txid, payload_words) \
    ((((uint32_t)(op) & 0xffu) << 24) | \
     (((uint32_t)(flags) & 0xffu) << 16) | \
     (((uint32_t)(txid) & 0xffu) << 8) | \
     ((uint32_t)(payload_words) & 0xffu))

#define AXISMSG_HDR_OPCODE(h)        (((h) >> 24) & 0xffu)
#define AXISMSG_HDR_FLAGS(h)         (((h) >> 16) & 0xffu)
#define AXISMSG_HDR_TXID(h)          (((h) >> 8)  & 0xffu)
#define AXISMSG_HDR_PAYLOAD_WORDS(h) (((h) >> 0)  & 0xffu)

enum axismsg_opcode {
    AXISMSG_OP_GET       = 0x01,
    AXISMSG_OP_SET       = 0x02,
    AXISMSG_OP_BULK_GET  = 0x03,
    AXISMSG_OP_PING      = 0x04,

    AXISMSG_OP_ACK       = 0x81,
    AXISMSG_OP_READ_RSP  = 0x82,
    AXISMSG_OP_BULK_RSP  = 0x83,
    AXISMSG_OP_ERROR     = 0xE0,
    AXISMSG_OP_EVENT     = 0xF0,
};

enum axismsg_error_code {
    AXISMSG_ERR_BAD_OPCODE   = 1,
    AXISMSG_ERR_BAD_LENGTH   = 2,
    AXISMSG_ERR_BAD_REGISTER = 3,
    AXISMSG_ERR_BUSY         = 4,
};

#define AXISMSG_MAX_MSG_BYTES   256u
#define AXISMSG_MAX_MSG_WORDS   (AXISMSG_MAX_MSG_BYTES / 4u)

struct axismsg_hdr_fields {
    uint8_t opcode;
    uint8_t flags;
    uint8_t txid;
    uint8_t payload_words;
};

static inline struct axismsg_hdr_fields axismsg_decode_hdr(uint32_t h)
{
    struct axismsg_hdr_fields f;
    f.opcode = (uint8_t)AXISMSG_HDR_OPCODE(h);
    f.flags = (uint8_t)AXISMSG_HDR_FLAGS(h);
    f.txid = (uint8_t)AXISMSG_HDR_TXID(h);
    f.payload_words = (uint8_t)AXISMSG_HDR_PAYLOAD_WORDS(h);
    return f;
}

#endif
