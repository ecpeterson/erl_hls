// axismsg_sg_probe.c
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/uaccess.h>
#include <linux/dmaengine.h>
#include <linux/dma-mapping.h>
#include <linux/of.h>
#include <linux/of_dma.h>
#include <linux/poll.h>
#include <linux/mutex.h>
#include <linux/spinlock.h>
#include <linux/wait.h>
#include <linux/scatterlist.h>
#include <linux/mm.h>
#include <linux/slab.h>
#include <linux/workqueue.h>
#include <linux/dma/xilinx_dma.h>

#include "axismsg_proto.h"

#define DEVNAME "axismsg0"
#define BUF_BYTES AXISMSG_MAX_MSG_BYTES

#define RX_RING_DEPTH 8
#define TX_RING_DEPTH 8

enum rx_state {
    RX_FREE = 0,
    RX_POSTED,
    RX_DONE,
};

enum tx_state {
    TX_FREE = 0,
    TX_QUEUED,
    TX_ACTIVE,
    TX_DONE,
};

struct axismsg_dev;

struct cb_ctx {
    struct axismsg_dev *d;
    bool is_rx;
    int slot;
};

struct rx_slot {
    void *virt;
    dma_addr_t dma;
    struct scatterlist sg;
    dma_cookie_t cookie;
    u32 hw_len;
    u32 msg_len;
    enum rx_state state;
    u32 gen;
    struct cb_ctx cb;
};

struct tx_slot {
    void *virt;
    dma_addr_t dma;
    struct scatterlist sg;
    dma_cookie_t cookie;
    u32 len;
    enum tx_state state;
    u32 gen;
    struct cb_ctx cb;
};

struct axismsg_dev {
    struct device *dev;
    struct dma_chan *tx_chan;
    struct dma_chan *rx_chan;

    struct rx_slot rx[RX_RING_DEPTH];
    u32 rx_post_cursor;

    u8 rx_done_q[RX_RING_DEPTH];
    u8 rx_done_head;
    u8 rx_done_tail;
    u8 rx_done_count;

    struct tx_slot tx[TX_RING_DEPTH];
    u32 tx_enqueue_cursor;
    u32 tx_pick_cursor;
    int tx_active;

    u8 tx_done_q[TX_RING_DEPTH];
    u8 tx_done_head;
    u8 tx_done_tail;
    u8 tx_done_count;

    spinlock_t lock;
    struct mutex tx_mutex;
    struct mutex rx_mutex;
    wait_queue_head_t tx_wq;
    wait_queue_head_t rx_wq;
    struct work_struct tx_work;

    dev_t devt;
    struct cdev cdev;
    struct class *class;
};

struct axismsg_file {
    struct axismsg_dev *d;
    int pending_rx_slot;
    u32 pending_rx_off;
    u32 pending_rx_len;
};

static u32 logical_len_from_header(void *buf)
{
    u32 hdr = ((u32 *)buf)[0];
    u32 opcode = AXISMSG_HDR_OPCODE(hdr);
    u32 payload_words = AXISMSG_HDR_PAYLOAD_WORDS(hdr);
    u32 n = 4 * (1 + payload_words);

    if (opcode == 0)
        return 0;
    if (n > BUF_BYTES)
        return 0;

    return n;
}

// static void log_words(struct device *dev, const char *tag, u32 len, void *buf)
// {
//     u32 *w = buf;
//
//     if (len >= 12)
//         dev_info(dev, "%s len=%u w0=%08x w1=%08x w2=%08x\n",
//              tag, len, w[0], w[1], w[2]);
//     else if (len >= 8)
//         dev_info(dev, "%s len=%u w0=%08x w1=%08x\n",
//              tag, len, w[0], w[1]);
//     else if (len >= 4)
//         dev_info(dev, "%s len=%u w0=%08x\n", tag, len, w[0]);
//     else
//         dev_info(dev, "%s len=%u\n", tag, len);
// }

static void setup_sg_from_coherent(struct scatterlist *sg, void *virt,
                   dma_addr_t dma, u32 len)
{
    sg_init_table(sg, 1);
    sg_set_page(sg, virt_to_page(virt), len, offset_in_page(virt));
    sg_dma_address(sg) = dma;
    sg_dma_len(sg) = len;
}

static void axismsg_set_coalescing(struct axismsg_dev *d)
{
    struct xilinx_vdma_config cfg = {0};
    int ret;

    // consider tuning these if /proc/interrupts shows an interrupt storm.
    cfg.coalesc = 1;  // number of descriptors to wait on before interrupt
    cfg.delay = 0;    // when nonzero, max DMA clock cycles after completion to wait before interrupt

    ret = xilinx_vdma_channel_set_config(d->rx_chan, &cfg);
    if (ret)
        dev_warn(d->dev, "failed to set RX coalescing: %d\n", ret);

    ret = xilinx_vdma_channel_set_config(d->tx_chan, &cfg);
    if (ret)
        dev_warn(d->dev, "failed to set TX coalescing: %d\n", ret);
}

/* ---------------- RX helpers ---------------- */

static bool any_done_rx_locked(struct axismsg_dev *d)
{
    return d->rx_done_count > 0;
}

static bool enqueue_rx_done_locked(struct axismsg_dev *d, int slot)
{
    if (d->rx_done_count >= RX_RING_DEPTH)
        return false;

    d->rx_done_q[d->rx_done_head] = (u8)slot;
    d->rx_done_head = (d->rx_done_head + 1) % RX_RING_DEPTH;
    d->rx_done_count++;

    return true;
}

static int dequeue_rx_done_locked(struct axismsg_dev *d)
{
    int slot;

    if (d->rx_done_count == 0)
        return -1;

    slot = d->rx_done_q[d->rx_done_tail];
    d->rx_done_tail = (d->rx_done_tail + 1) % RX_RING_DEPTH;
    d->rx_done_count--;

    return slot;
}

static void rx_done_cb(void *arg)
{
    struct cb_ctx *cb = arg;
    struct axismsg_dev *d = cb->d;
    int slot = cb->slot;
    struct dma_tx_state st;
    enum dma_status status;
    unsigned long flags;
    u32 hw_len;
    u32 msg_len;
    bool queued = false;

    status = dmaengine_tx_status(d->rx_chan, d->rx[slot].cookie, &st);
    hw_len = (status == DMA_ERROR) ? 0 : (BUF_BYTES - st.residue);
    msg_len = logical_len_from_header(d->rx[slot].virt);

    spin_lock_irqsave(&d->lock, flags);

    d->rx[slot].hw_len = hw_len;
    d->rx[slot].msg_len = msg_len;
    d->rx[slot].gen++;

    if (msg_len > 0) {
        d->rx[slot].state = RX_DONE;
        queued = enqueue_rx_done_locked(d, slot);
        if (!queued) {
            dev_warn(d->dev, "RX done queue overflow slot=%d\n", slot);
            d->rx[slot].state = RX_FREE;
            d->rx[slot].msg_len = 0;
            d->rx[slot].hw_len = 0;
        }
    } else {
        d->rx[slot].state = RX_FREE;
    }

    spin_unlock_irqrestore(&d->lock, flags);

    // dev_info(d->dev,
    //      "RX-CB slot=%d status=%d residue=%u hw_len=%u msg_len=%u gen=%u queued=%d done_q=%u\n",
    //      slot, status, st.residue, hw_len, msg_len, d->rx[slot].gen,
    //      queued ? 1 : 0, d->rx_done_count);
    // log_words(d->dev, "RX-CB-DATA", BUF_BYTES, d->rx[slot].virt);

    wake_up_interruptible(&d->rx_wq);
}

static int post_rx_one_locked(struct axismsg_dev *d, int i)
{
    struct dma_async_tx_descriptor *desc;
    dma_cookie_t cookie;
    enum dma_ctrl_flags flags = DMA_CTRL_ACK | DMA_PREP_INTERRUPT;

    if (d->rx[i].state != RX_FREE)
        return 0;

    memset(d->rx[i].virt, 0, BUF_BYTES);

    setup_sg_from_coherent(&d->rx[i].sg,
                   d->rx[i].virt,
                   d->rx[i].dma,
                   BUF_BYTES);

    d->rx[i].hw_len = 0;
    d->rx[i].msg_len = 0;
    d->rx[i].state = RX_POSTED;

    desc = dmaengine_prep_slave_sg(d->rx_chan,
                       &d->rx[i].sg,
                       1,
                       DMA_DEV_TO_MEM,
                       flags);
    if (!desc) {
        d->rx[i].state = RX_FREE;
        dev_err(d->dev, "RX prep SG failed slot=%d\n", i);
        return -EIO;
    }

    desc->callback = rx_done_cb;
    desc->callback_param = &d->rx[i].cb;

    cookie = dmaengine_submit(desc);
    if (dma_submit_error(cookie)) {
        d->rx[i].state = RX_FREE;
        dev_err(d->dev, "RX submit SG failed slot=%d\n", i);
        return -EIO;
    }

    d->rx[i].cookie = cookie;

    // dev_info(d->dev, "RX-SUBMIT slot=%d dma=%pad len=%u cookie=%d\n",
    //      i, &d->rx[i].dma, BUF_BYTES, d->rx[i].cookie);

    // if we batch the issue up in post_rx_locked, we only get the interrupt
    // after the whole batch completes
    dma_async_issue_pending(d->rx_chan);

    return 1;
}

static int post_rx_locked(struct axismsg_dev *d)
{
    int n;
    int submitted = 0;

    for (n = 0; n < RX_RING_DEPTH; n++) {
        int i = (d->rx_post_cursor + n) % RX_RING_DEPTH;
        int ret = post_rx_one_locked(d, i);

        if (ret < 0)
            continue;

        if (ret > 0) {
            submitted++;
            d->rx_post_cursor = (i + 1) % RX_RING_DEPTH;
        }
    }

    return submitted;
}

/* ---------------- TX helpers ---------------- */

static bool any_free_tx_locked(struct axismsg_dev *d)
{
    int i;

    for (i = 0; i < TX_RING_DEPTH; i++)
        if (d->tx[i].state == TX_FREE)
            return true;

    return false;
}

static int find_free_tx_locked(struct axismsg_dev *d)
{
    int n;

    for (n = 0; n < TX_RING_DEPTH; n++) {
        int i = (d->tx_enqueue_cursor + n) % TX_RING_DEPTH;

        if (d->tx[i].state == TX_FREE) {
            d->tx_enqueue_cursor = (i + 1) % TX_RING_DEPTH;
            return i;
        }
    }

    return -1;
}

static int find_queued_tx_locked(struct axismsg_dev *d)
{
    int n;

    for (n = 0; n < TX_RING_DEPTH; n++) {
        int i = (d->tx_pick_cursor + n) % TX_RING_DEPTH;

        if (d->tx[i].state == TX_QUEUED) {
            d->tx_pick_cursor = (i + 1) % TX_RING_DEPTH;
            return i;
        }
    }

    return -1;
}

static bool enqueue_tx_done_locked(struct axismsg_dev *d, int slot)
{
    if (d->tx_done_count >= TX_RING_DEPTH)
        return false;

    d->tx_done_q[d->tx_done_head] = (u8)slot;
    d->tx_done_head = (d->tx_done_head + 1) % TX_RING_DEPTH;
    d->tx_done_count++;

    return true;
}

static int dequeue_tx_done_locked(struct axismsg_dev *d)
{
    int slot;

    if (d->tx_done_count == 0)
        return -1;

    slot = d->tx_done_q[d->tx_done_tail];
    d->tx_done_tail = (d->tx_done_tail + 1) % TX_RING_DEPTH;
    d->tx_done_count--;

    return slot;
}

static void reap_tx_done_locked(struct axismsg_dev *d)
{
    int slot;

    while ((slot = dequeue_tx_done_locked(d)) >= 0) {
        // dev_info(d->dev, "TX-REAP slot=%d gen=%u\n",
        //      slot, d->tx[slot].gen);
        d->tx[slot].state = TX_FREE;
        d->tx[slot].len = 0;
    }
}

static void tx_done_cb(void *arg);

static bool kick_one_tx_locked(struct axismsg_dev *d)
{
    int slot;
    struct dma_async_tx_descriptor *desc;
    dma_cookie_t cookie;
    enum dma_ctrl_flags flags = DMA_CTRL_ACK | DMA_PREP_INTERRUPT;

    if (d->tx_active >= 0)
        return false;

    slot = find_queued_tx_locked(d);
    if (slot < 0)
        return false;

    setup_sg_from_coherent(&d->tx[slot].sg,
                   d->tx[slot].virt,
                   d->tx[slot].dma,
                   d->tx[slot].len);

    desc = dmaengine_prep_slave_sg(d->tx_chan,
                       &d->tx[slot].sg,
                       1,
                       DMA_MEM_TO_DEV,
                       flags);
    if (!desc) {
        dev_err(d->dev, "TX prep SG failed slot=%d\n", slot);
        return false;
    }

    desc->callback = NULL;
    desc->callback_param = &d->tx[slot].cb;

    desc->callback = tx_done_cb;

    d->tx[slot].state = TX_ACTIVE;
    d->tx_active = slot;

    cookie = dmaengine_submit(desc);
    if (dma_submit_error(cookie)) {
        dev_err(d->dev, "TX submit SG failed slot=%d\n", slot);
        d->tx[slot].state = TX_QUEUED;
        d->tx_active = -1;
        return false;
    }

    d->tx[slot].cookie = cookie;
    // dev_info(d->dev, "TX-SUBMIT slot=%d dma=%pad len=%u cookie=%d gen=%u\n",
    //      slot, &d->tx[slot].dma, d->tx[slot].len,
    //      d->tx[slot].cookie, d->tx[slot].gen);
    // log_words(d->dev, "TX-DATA", d->tx[slot].len, d->tx[slot].virt);

    dma_async_issue_pending(d->tx_chan);
    return true;
}

static void tx_done_cb(void *arg)
{
    struct cb_ctx *cb = arg;
    struct axismsg_dev *d = cb->d;
    int slot = cb->slot;
    unsigned long flags;
    bool queued;

    spin_lock_irqsave(&d->lock, flags);

    d->tx[slot].state = TX_DONE;
    d->tx_active = -1;
    queued = enqueue_tx_done_locked(d, slot);
    if (!queued) {
        dev_warn(d->dev, "TX done queue overflow slot=%d\n", slot);
        d->tx[slot].state = TX_FREE;
        d->tx[slot].len = 0;
    }

    spin_unlock_irqrestore(&d->lock, flags);

    // dev_info(d->dev, "TX-CB slot=%d cookie=%d len=%u gen=%u queued=%d done_q=%u\n",
    //      slot, d->tx[slot].cookie, d->tx[slot].len,
    //      d->tx[slot].gen, queued ? 1 : 0, d->tx_done_count);

    wake_up_interruptible(&d->tx_wq);
    schedule_work(&d->tx_work);
}

static void tx_workfn(struct work_struct *work)
{
    struct axismsg_dev *d = container_of(work, struct axismsg_dev, tx_work);
    unsigned long flags;
    bool kicked;

    spin_lock_irqsave(&d->lock, flags);
    reap_tx_done_locked(d);
    kicked = kick_one_tx_locked(d);
    spin_unlock_irqrestore(&d->lock, flags);

    // if (kicked)
    //     dev_info(d->dev, "TX-WORK kicked one queued TX\n");

    wake_up_interruptible(&d->tx_wq);
}

/* ---------------- file ops ---------------- */

static int axismsg_open(struct inode *inode, struct file *f)
{
    struct axismsg_dev *d = container_of(inode->i_cdev,
                        struct axismsg_dev,
                        cdev);
    struct axismsg_file *af;

    af = kzalloc(sizeof(*af), GFP_KERNEL);
    if (!af)
        return -ENOMEM;

    af->d = d;
    af->pending_rx_slot = -1;
    af->pending_rx_off = 0;
    af->pending_rx_len = 0;

    f->private_data = af;

    return 0;
}

static int axismsg_release(struct inode *inode, struct file *f)
{
    struct axismsg_file *af = f->private_data;
    struct axismsg_dev *d;
    unsigned long flags;

    if (!af)
        return 0;

    d = af->d;

    if (af->pending_rx_slot >= 0) {
        mutex_lock(&d->rx_mutex);

        spin_lock_irqsave(&d->lock, flags);
        d->rx[af->pending_rx_slot].state = RX_FREE;
        d->rx[af->pending_rx_slot].msg_len = 0;
        d->rx[af->pending_rx_slot].hw_len = 0;
        spin_unlock_irqrestore(&d->lock, flags);

        post_rx_locked(d);
        mutex_unlock(&d->rx_mutex);
    }

    kfree(af);
    f->private_data = NULL;
    return 0;
}

static ssize_t axismsg_write(struct file *f, const char __user *buf,
                size_t len, loff_t *ppos)
{
    struct axismsg_file *af = f->private_data;
    struct axismsg_dev *d = af->d;
    unsigned long flags;
    int slot;
    int ret = 0;

    if (len == 0 || len > BUF_BYTES || (len & 3))
        return -EINVAL;

    if (mutex_lock_interruptible(&d->tx_mutex))
        return -ERESTARTSYS;

    for (;;) {
        spin_lock_irqsave(&d->lock, flags);
        reap_tx_done_locked(d);
        slot = find_free_tx_locked(d);
        spin_unlock_irqrestore(&d->lock, flags);

        if (slot >= 0)
            break;

        mutex_unlock(&d->tx_mutex);
        if (f->f_flags & O_NONBLOCK)
            return -EAGAIN;

        if (wait_event_interruptible(d->tx_wq, ({
            int ready;
            unsigned long f2;

            spin_lock_irqsave(&d->lock, f2);
            ready = any_free_tx_locked(d);
            spin_unlock_irqrestore(&d->lock, f2);

            ready;
        })))
            return -ERESTARTSYS;

        if (mutex_lock_interruptible(&d->tx_mutex))
            return -ERESTARTSYS;
    }

    memset(d->tx[slot].virt, 0, BUF_BYTES);
    if (copy_from_user(d->tx[slot].virt, buf, len)) {
        ret = -EFAULT;
        goto out_unlock;
    }

    spin_lock_irqsave(&d->lock, flags);
    d->tx[slot].len = len;
    d->tx[slot].gen++;
    d->tx[slot].state = TX_QUEUED;
    spin_unlock_irqrestore(&d->lock, flags);

    // dev_info(d->dev, "TX-QUEUE slot=%d len=%zu gen=%u\n",
    //      slot, len, d->tx[slot].gen);

    schedule_work(&d->tx_work);

    ret = (int)len;

out_unlock:
    mutex_unlock(&d->tx_mutex);
    return ret;
}

static ssize_t axismsg_read(struct file *f, char __user *buf,
                size_t len, loff_t *ppos)
{
    struct axismsg_file *af = f->private_data;
    struct axismsg_dev *d = af->d;
    unsigned long flags;
    u32 msg_len;
    u32 gen;
    int slot;
    int ret;
    size_t avail;
    size_t ncopy;

    if (len == 0)
        return 0;

    if (mutex_lock_interruptible(&d->rx_mutex))
        return -ERESTARTSYS;

    // if this fd already owns a partially-read packet, continue from it.
    if (af->pending_rx_slot >= 0) {
        slot = af->pending_rx_slot;
        msg_len = af->pending_rx_len;
        gen = d->rx[slot].gen;
        goto have_packet;
    }

    for (;;) {
        spin_lock_irqsave(&d->lock, flags);
        slot = dequeue_rx_done_locked(d);
        if (slot >= 0) {
            msg_len = d->rx[slot].msg_len;
            gen = d->rx[slot].gen;
        } else {
            msg_len = 0;
            gen = 0;
        }
        spin_unlock_irqrestore(&d->lock, flags);

        if (slot >= 0)
            break;

        mutex_unlock(&d->rx_mutex);
        if (f->f_flags & O_NONBLOCK)
            return -EAGAIN;

        if (wait_event_interruptible(d->rx_wq, ({
            int ready;
            unsigned long f2;

            spin_lock_irqsave(&d->lock, f2);
            ready = any_done_rx_locked(d);
            spin_unlock_irqrestore(&d->lock, f2);

            ready;
        })))
            return -ERESTARTSYS;

        if (mutex_lock_interruptible(&d->rx_mutex))
            return -ERESTARTSYS;
    }

    af->pending_rx_slot = slot;
    af->pending_rx_off = 0;
    af->pending_rx_len = msg_len;

have_packet:
    avail = af->pending_rx_len - af->pending_rx_off;
    ncopy = min_t(size_t, len, avail);

    if (copy_to_user(buf,
             ((u8 *)d->rx[slot].virt) + af->pending_rx_off,
             ncopy)) {
        ret = -EFAULT;
        goto out_unlock;
    }

    // dev_info(d->dev,
    //     "RX-READ slot=%d gen=%u off=%u ncopy=%zu msg_len=%u done_q=%u\n",
    //     slot, gen, af->pending_rx_off, ncopy,
    //     af->pending_rx_len, d->rx_done_count);

    af->pending_rx_off += ncopy;

    if (af->pending_rx_off >= af->pending_rx_len) {
        spin_lock_irqsave(&d->lock, flags);
        d->rx[slot].state = RX_FREE;
        d->rx[slot].msg_len = 0;
        d->rx[slot].hw_len = 0;
        spin_unlock_irqrestore(&d->lock, flags);

        af->pending_rx_slot = -1;
        af->pending_rx_off = 0;
        af->pending_rx_len = 0;

        post_rx_locked(d);
    }

    ret = ncopy;

out_unlock:
    mutex_unlock(&d->rx_mutex);
    return ret;
}

static __poll_t axismsg_poll(struct file *f, poll_table *wait)
{
    struct axismsg_file *af = f->private_data;
    struct axismsg_dev *d = af->d;
    __poll_t mask = 0;
    unsigned long flags;
    int rx_ready;
    int tx_ready;

    poll_wait(f, &d->rx_wq, wait);
    poll_wait(f, &d->tx_wq, wait);

    spin_lock_irqsave(&d->lock, flags);
    rx_ready = (af->pending_rx_slot >= 0) || any_done_rx_locked(d);
    tx_ready = any_free_tx_locked(d);
    spin_unlock_irqrestore(&d->lock, flags);

    if (rx_ready)
        mask |= EPOLLIN | EPOLLRDNORM;
    if (tx_ready)
        mask |= EPOLLOUT | EPOLLWRNORM;

    return mask;
}

static const struct file_operations axismsg_fops = {
    .owner = THIS_MODULE,
    .open = axismsg_open,
    .release = axismsg_release,
    .read = axismsg_read,
    .write = axismsg_write,
    .poll = axismsg_poll,
    .llseek = no_llseek,
};

/* ---------------- platform driver ---------------- */

static int axismsg_probe(struct platform_device *pdev)
{
    struct axismsg_dev *d;
    struct dma_slave_config txcfg = {0};
    struct dma_slave_config rxcfg = {0};
    int ret;
    int i;

    d = devm_kzalloc(&pdev->dev, sizeof(*d), GFP_KERNEL);
    if (!d)
        return -ENOMEM;

    d->dev = &pdev->dev;
    spin_lock_init(&d->lock);
    mutex_init(&d->tx_mutex);
    mutex_init(&d->rx_mutex);
    init_waitqueue_head(&d->tx_wq);
    init_waitqueue_head(&d->rx_wq);
    INIT_WORK(&d->tx_work, tx_workfn);

    d->rx_post_cursor = 0;
    d->rx_done_head = 0;
    d->rx_done_tail = 0;
    d->rx_done_count = 0;

    d->tx_enqueue_cursor = 0;
    d->tx_pick_cursor = 0;
    d->tx_active = -1;
    d->tx_done_head = 0;
    d->tx_done_tail = 0;
    d->tx_done_count = 0;

    d->tx_chan = dma_request_chan(&pdev->dev, "tx");
    if (IS_ERR(d->tx_chan))
        return PTR_ERR(d->tx_chan);

    d->rx_chan = dma_request_chan(&pdev->dev, "rx");
    if (IS_ERR(d->rx_chan)) {
        ret = PTR_ERR(d->rx_chan);
        dma_release_channel(d->tx_chan);
        return ret;
    }

    // dev_info(d->dev, "channels: tx=%s rx=%s\n",
    //      dma_chan_name(d->tx_chan), dma_chan_name(d->rx_chan));

    txcfg.direction = DMA_MEM_TO_DEV;
    txcfg.src_addr_width = DMA_SLAVE_BUSWIDTH_4_BYTES;
    txcfg.dst_addr_width = DMA_SLAVE_BUSWIDTH_4_BYTES;
    txcfg.src_maxburst = 1;
    txcfg.dst_maxburst = 1;
    ret = dmaengine_slave_config(d->tx_chan, &txcfg);
    if (ret)
        goto err_dma;

    rxcfg.direction = DMA_DEV_TO_MEM;
    rxcfg.src_addr_width = DMA_SLAVE_BUSWIDTH_4_BYTES;
    rxcfg.dst_addr_width = DMA_SLAVE_BUSWIDTH_4_BYTES;
    rxcfg.src_maxburst = 1;
    rxcfg.dst_maxburst = 1;
    ret = dmaengine_slave_config(d->rx_chan, &rxcfg);
    if (ret)
        goto err_dma;

    axismsg_set_coalescing(d);

    for (i = 0; i < TX_RING_DEPTH; i++) {
        d->tx[i].virt = dma_alloc_coherent(d->dev, BUF_BYTES,
                           &d->tx[i].dma,
                           GFP_KERNEL);
        if (!d->tx[i].virt) {
            ret = -ENOMEM;
            goto err_mem;
        }

        d->tx[i].state = TX_FREE;
        d->tx[i].len = 0;
        d->tx[i].cookie = 0;
        d->tx[i].gen = 0;
        d->tx[i].cb.d = d;
        d->tx[i].cb.is_rx = false;
        d->tx[i].cb.slot = i;
    }

    for (i = 0; i < RX_RING_DEPTH; i++) {
        d->rx[i].virt = dma_alloc_coherent(d->dev, BUF_BYTES,
                           &d->rx[i].dma,
                           GFP_KERNEL);
        if (!d->rx[i].virt) {
            ret = -ENOMEM;
            goto err_mem;
        }

        d->rx[i].state = RX_FREE;
        d->rx[i].hw_len = 0;
        d->rx[i].msg_len = 0;
        d->rx[i].cookie = 0;
        d->rx[i].gen = 0;
        d->rx[i].cb.d = d;
        d->rx[i].cb.is_rx = true;
        d->rx[i].cb.slot = i;
    }

    ret = alloc_chrdev_region(&d->devt, 0, 1, DEVNAME);
    if (ret)
        goto err_mem;

    cdev_init(&d->cdev, &axismsg_fops);
    ret = cdev_add(&d->cdev, d->devt, 1);
    if (ret)
        goto err_chrdev;

    d->class = class_create(DEVNAME);
    if (IS_ERR(d->class)) {
        ret = PTR_ERR(d->class);
        goto err_cdev;
    }

    device_create(d->class, NULL, d->devt, NULL, DEVNAME);
    platform_set_drvdata(pdev, d);

    mutex_lock(&d->rx_mutex);
    post_rx_locked(d);
    mutex_unlock(&d->rx_mutex);

    // dev_info(d->dev,
    //      "axismsg SG RX/TX rings ready rx_depth=%d tx_depth=%d\n",
    //      RX_RING_DEPTH, TX_RING_DEPTH);
    return 0;

err_cdev:
    cdev_del(&d->cdev);
err_chrdev:
    unregister_chrdev_region(d->devt, 1);
err_mem:
    for (i = 0; i < TX_RING_DEPTH; i++) {
        if (d->tx[i].virt)
            dma_free_coherent(d->dev, BUF_BYTES,
                      d->tx[i].virt, d->tx[i].dma);
    }

    for (i = 0; i < RX_RING_DEPTH; i++) {
        if (d->rx[i].virt)
            dma_free_coherent(d->dev, BUF_BYTES,
                      d->rx[i].virt, d->rx[i].dma);
    }
err_dma:
    dma_release_channel(d->rx_chan);
    dma_release_channel(d->tx_chan);
    return ret;
}

static int axismsg_remove(struct platform_device *pdev)
{
    struct axismsg_dev *d = platform_get_drvdata(pdev);
    int i;

    cancel_work_sync(&d->tx_work);

    device_destroy(d->class, d->devt);
    class_destroy(d->class);
    cdev_del(&d->cdev);
    unregister_chrdev_region(d->devt, 1);

    for (i = 0; i < TX_RING_DEPTH; i++) {
        if (d->tx[i].virt)
            dma_free_coherent(d->dev, BUF_BYTES,
                      d->tx[i].virt, d->tx[i].dma);
    }

    for (i = 0; i < RX_RING_DEPTH; i++) {
        if (d->rx[i].virt)
            dma_free_coherent(d->dev, BUF_BYTES,
                      d->rx[i].virt, d->rx[i].dma);
    }

    dma_release_channel(d->rx_chan);
    dma_release_channel(d->tx_chan);
    return 0;
}

static const struct of_device_id axismsg_of_match[] = {
    { .compatible = "demo,axismsg-test" },
    {}
};
MODULE_DEVICE_TABLE(of, axismsg_of_match);

static struct platform_driver axismsg_driver = {
    .probe  = axismsg_probe,
    .remove = axismsg_remove,
    .driver = {
        .name = "axismsg_shim",
        .of_match_table = axismsg_of_match,
    },
};

module_platform_driver(axismsg_driver);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("SG AXI message probe with RX and TX rings");
