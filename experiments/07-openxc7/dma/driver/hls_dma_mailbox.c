// SPDX-License-Identifier: GPL-2.0-only
/* Routed frame character device backed by PL330 copies to/from PL packet RAM. */
#include <linux/clk.h>
#include <linux/fs.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/kref.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/poll.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include "hls_dma_copy.h"

#define REG_ID 0
#define REG_ABI 4
#define REG_STATUS 8
#define REG_TX_LENGTH 12
#define REG_RX_LENGTH 16
#define REG_ACK 20
#define REG_MASK 24
#define REG_EVENTS 28
#define TX_RAM 0x1000
#define RX_RAM 0x2000
#define TX_BUSY BIT(0)
#define TX_DONE BIT(0)
#define RX_FULL BIT(1)
#define FAULT BIT(2)
#define RX_ACTIVE BIT(3)

/* Open files keep this object alive after unbind; dead gates all hardware access. */
struct hls_mailbox {
	struct miscdevice misc;
	char name[32];
	struct kref refs;
	struct mutex life_lock, tx_lock, rx_lock;
	spinlock_t irq_lock;
	wait_queue_head_t tx_wait, rx_wait;
	void __iomem *regs;
	struct hls_dma_copy tx, rx;
	dma_addr_t tx_ram, rx_ram;
	size_t rx_bytes, rx_offset;
	fmode_t opened;
	bool dead, failed;
	u32 mask;
	int irq;
};

/* Final file/device reference: all DMA resources were already released on unbind. */
static void hls_free(struct kref *ref)
{
	kfree(container_of(ref, struct hls_mailbox, refs));
}

/* Return the transport error before considering whether a queue is ready. */
static int hls_error(struct hls_mailbox *box)
{
	if (READ_ONCE(box->dead))
		return -ENODEV;
	return READ_ONCE(box->failed) ? -EIO : 0;
}

/* A failed transfer freezes the endpoint until driver rebind, waking both users. */
static void hls_failed(struct hls_mailbox *box)
{
	WRITE_ONCE(box->failed, true);
	wake_up_interruptible(&box->tx_wait);
	wake_up_interruptible(&box->rx_wait);
}

/* Acknowledge completion; mask RX until its owner has copied/released the slot. */
static irqreturn_t hls_interrupt(int irq, void *data)
{
	struct hls_mailbox *box = data;
	u32 events;
	unsigned long flags;

	spin_lock_irqsave(&box->irq_lock, flags);
	events = readl(box->regs + REG_EVENTS) & box->mask;
	if (events & RX_FULL)
		box->mask &= ~RX_FULL;
	if (events & FAULT)
		box->mask = 0;
	writel(box->mask, box->regs + REG_MASK);
	writel(events & (TX_DONE | FAULT), box->regs + REG_ACK);
	spin_unlock_irqrestore(&box->irq_lock, flags);
	if (!events)
		return IRQ_NONE;
	if (events & FAULT)
		hls_failed(box);
	wake_up_interruptible(&box->tx_wait);
	wake_up_interruptible(&box->rx_wait);
	return IRQ_HANDLED;
}

/* Allow one reader and one writer (or one combined open), as raw BEAM I/O uses. */
static int hls_open(struct inode *inode, struct file *file)
{
	struct hls_mailbox *box = container_of(file->private_data, struct hls_mailbox, misc);
	fmode_t mode = file->f_mode & (FMODE_READ | FMODE_WRITE);
	int error;

	mutex_lock(&box->life_lock);
	error = hls_error(box);
	if (!error && (box->opened & mode))
		error = -EBUSY;
	if (!error) {
		box->opened |= mode;
		kref_get(&box->refs);
		file->private_data = box;
	}
	mutex_unlock(&box->life_lock);
	return error ?: nonseekable_open(inode, file);
}

/* Closing releases ownership only; it never cancels another direction's work. */
static int hls_release(struct inode *inode, struct file *file)
{
	struct hls_mailbox *box = file->private_data;

	/* A replacement reader must start at a frame boundary, never a partial tail. */
	if (file->f_mode & FMODE_READ) {
		mutex_lock(&box->rx_lock);
		box->rx_bytes = 0;
		box->rx_offset = 0;
		mutex_unlock(&box->rx_lock);
	}
	mutex_lock(&box->life_lock);
	box->opened &= ~(file->f_mode & (FMODE_READ | FMODE_WRITE));
	mutex_unlock(&box->life_lock);
	kref_put(&box->refs, hls_free);
	return 0;
}

/* Submit one complete frame; successful return means published, not yet consumed. */
static ssize_t hls_write(struct file *file, const char __user *data, size_t bytes,
			 loff_t *position)
{
	struct hls_mailbox *box = file->private_data;
	int error;

	if (bytes < 8 || bytes > HLS_FRAME_BYTES || (bytes & 3))
		return -EMSGSIZE;
	if (mutex_lock_interruptible(&box->tx_lock))
		return -ERESTARTSYS;
	error = hls_error(box);
	if (error)
		goto out;
	if (copy_from_user(box->tx.buffer, data, bytes)) {
		error = -EFAULT;
		goto out;
	}
	if (bytes != 8 + 4 * ((u8 *)box->tx.buffer)[4]) {
		error = -EPROTO;
		goto out;
	}
	if ((file->f_flags & O_NONBLOCK) && (readl(box->regs + REG_STATUS) & TX_BUSY)) {
		error = -EAGAIN;
		goto out;
	}
	error = wait_event_interruptible(box->tx_wait,
		hls_error(box) || !(readl(box->regs + REG_STATUS) & TX_BUSY));
	if (!error)
		error = hls_error(box);
	if (error)
		goto out;
	error = hls_dma_transfer(&box->tx, box->tx_ram, box->tx.address, bytes);
	if (error) {
		hls_failed(box);
		goto out;
	}
	if (!(error = hls_error(box)))
		writel(bytes, box->regs + REG_TX_LENGTH);
out:
	mutex_unlock(&box->tx_lock);
	return error ?: bytes;
}

/* Release RX after a coherent copy, then rearm its level interrupt. */
static void hls_rx_ack(struct hls_mailbox *box)
{
	unsigned long flags;

	spin_lock_irqsave(&box->irq_lock, flags);
	writel(RX_FULL, box->regs + REG_ACK);
	box->mask |= RX_FULL;
	writel(box->mask, box->regs + REG_MASK);
	spin_unlock_irqrestore(&box->irq_lock, flags);
}

/* Return bytes from one frame; partial reads retain the rest for the same reader. */
static ssize_t hls_read(struct file *file, char __user *data, size_t bytes, loff_t *position)
{
	struct hls_mailbox *box = file->private_data;
	int error;

	if (!bytes)
		return 0;
	if (mutex_lock_interruptible(&box->rx_lock))
		return -ERESTARTSYS;
	error = hls_error(box);
	if (error)
		goto out;
	if (box->rx_offset == box->rx_bytes) {
		if ((file->f_flags & O_NONBLOCK) && !(readl(box->regs + REG_STATUS) & RX_FULL)) {
			error = -EAGAIN;
			goto out;
		}
		error = wait_event_interruptible(box->rx_wait,
			hls_error(box) || (readl(box->regs + REG_STATUS) & RX_FULL));
		if (!error)
			error = hls_error(box);
		if (error)
			goto out;
		box->rx_bytes = readl(box->regs + REG_RX_LENGTH);
		box->rx_offset = 0;
		if (box->rx_bytes < 8 || box->rx_bytes > HLS_FRAME_BYTES || (box->rx_bytes & 3)) {
			error = -EPROTO;
			goto fail;
		}
		error = hls_dma_transfer(&box->rx, box->rx.address, box->rx_ram, box->rx_bytes);
		if (error)
			goto fail;
		if (box->rx_bytes != 8 + 4 * ((u8 *)box->rx.buffer)[4]) {
			error = -EPROTO;
			goto fail;
		}
		hls_rx_ack(box);
	}
	bytes = min(bytes, box->rx_bytes - box->rx_offset);
	if (copy_to_user(data, box->rx.buffer + box->rx_offset, bytes)) {
		error = -EFAULT;
		goto out;
	}
	box->rx_offset += bytes;
	goto out;
fail:
	hls_failed(box);
out:
	mutex_unlock(&box->rx_lock);
	return error ?: bytes;
}

/* Report queue readiness; lifetime locking prevents MMIO after platform unbind. */
static __poll_t hls_poll(struct file *file, poll_table *wait)
{
	struct hls_mailbox *box = file->private_data;
	__poll_t result = 0;
	u32 status;

	poll_wait(file, &box->rx_wait, wait);
	poll_wait(file, &box->tx_wait, wait);
	mutex_lock(&box->life_lock);
	if (hls_error(box)) {
		result = EPOLLERR | EPOLLHUP;
	} else {
		status = readl(box->regs + REG_STATUS);
		if ((file->f_mode & FMODE_READ) &&
		    ((status & RX_FULL) || READ_ONCE(box->rx_bytes) != READ_ONCE(box->rx_offset)))
			result |= EPOLLIN | EPOLLRDNORM;
		if ((file->f_mode & FMODE_WRITE) && !(status & TX_BUSY))
			result |= EPOLLOUT | EPOLLWRNORM;
	}
	mutex_unlock(&box->life_lock);
	return result;
}

static const struct file_operations hls_fops = {
	.owner = THIS_MODULE, .open = hls_open, .release = hls_release,
	.read = hls_read, .write = hls_write, .poll = hls_poll, .llseek = no_llseek,
};

/* Claim only the matching PL ABI, two DT-selected DMA channels and one interrupt. */
static int hls_probe(struct platform_device *pdev)
{
	struct hls_mailbox *box;
	struct resource *resource;
	struct clk *clock;
	int error, index;

	/* DT aliases keep application/debug names stable across probe and rebind. */
	index = of_alias_get_id(pdev->dev.of_node, "hlsdma");
	if (index < 0)
		return dev_err_probe(&pdev->dev, index, "missing hlsdma alias\n");

	box = kzalloc(sizeof(*box), GFP_KERNEL);
	if (!box)
		return -ENOMEM;
	kref_init(&box->refs);
	mutex_init(&box->life_lock); mutex_init(&box->tx_lock); mutex_init(&box->rx_lock);
	spin_lock_init(&box->irq_lock);
	init_waitqueue_head(&box->tx_wait); init_waitqueue_head(&box->rx_wait);
	resource = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!resource || resource_size(resource) < 0x3000) {
		error = -EINVAL;
		goto free;
	}
	clock = devm_clk_get_enabled(&pdev->dev, NULL);
	if (IS_ERR(clock)) {
		error = PTR_ERR(clock);
		goto free;
	}
	box->regs = devm_ioremap_resource(&pdev->dev, resource);
	if (IS_ERR(box->regs)) {
		error = PTR_ERR(box->regs);
		goto free;
	}
	if (readl(box->regs + REG_ID) != 0x484c444d || readl(box->regs + REG_ABI) != 1) {
		error = -ENODEV;
		goto free;
	}
	/* Rebind requires quiescent hardware; it must not publish stale buffered data. */
	if (readl(box->regs + REG_STATUS)) {
		error = -EBUSY;
		goto free;
	}
	writel(0, box->regs + REG_MASK);
	writel(TX_DONE, box->regs + REG_ACK);
	error = hls_dma_acquire(&pdev->dev, "tx", &box->tx);
	if (error)
		goto free;
	error = hls_dma_acquire(&pdev->dev, "rx", &box->rx);
	if (error)
		goto release_tx;
	box->tx_ram = dma_map_resource(box->tx.device, resource->start + TX_RAM,
				       HLS_FRAME_BYTES, DMA_FROM_DEVICE, 0);
	if (dma_mapping_error(box->tx.device, box->tx_ram)) {
		error = -EIO;
		goto release_rx;
	}
	box->rx_ram = dma_map_resource(box->rx.device, resource->start + RX_RAM,
				       HLS_FRAME_BYTES, DMA_TO_DEVICE, 0);
	if (dma_mapping_error(box->rx.device, box->rx_ram)) {
		error = -EIO;
		goto unmap_tx;
	}
	box->irq = platform_get_irq(pdev, 0);
	if (box->irq < 0) {
		error = box->irq;
		goto unmap_rx;
	}
	error = request_irq(box->irq, hls_interrupt, 0, dev_name(&pdev->dev), box);
	if (error)
		goto unmap_rx;
	box->misc.minor = MISC_DYNAMIC_MINOR;
	snprintf(box->name, sizeof(box->name), "hls-dma%d", index);
	box->misc.name = box->name;
	box->misc.fops = &hls_fops;
	box->misc.parent = &pdev->dev;
	box->misc.mode = 0600;
	error = misc_register(&box->misc);
	if (error)
		goto free_irq;
	platform_set_drvdata(pdev, box);
	box->mask = TX_DONE | RX_FULL | FAULT;
	writel(box->mask, box->regs + REG_MASK);
	return 0;
free_irq:
	free_irq(box->irq, box);
unmap_rx:
	dma_unmap_resource(box->rx.device, box->rx_ram, HLS_FRAME_BYTES, DMA_TO_DEVICE, 0);
unmap_tx:
	dma_unmap_resource(box->tx.device, box->tx_ram, HLS_FRAME_BYTES, DMA_FROM_DEVICE, 0);
release_rx:
	hls_dma_release(&box->rx);
release_tx:
	hls_dma_release(&box->tx);
free:
	kref_put(&box->refs, hls_free);
	return dev_err_probe(&pdev->dev, error, "DMA mailbox unavailable\n");
}

/* Wake sleepers, join active copies, then detach hardware; existing FDs stay inert. */
static int hls_remove(struct platform_device *pdev)
{
	struct hls_mailbox *box = platform_get_drvdata(pdev);
	unsigned long flags;

	mutex_lock(&box->life_lock);
	WRITE_ONCE(box->dead, true);
	mutex_unlock(&box->life_lock);
	misc_deregister(&box->misc);
	wake_up_interruptible(&box->tx_wait); wake_up_interruptible(&box->rx_wait);
	mutex_lock(&box->tx_lock); mutex_lock(&box->rx_lock);
	spin_lock_irqsave(&box->irq_lock, flags);
	box->mask = 0;
	writel(0, box->regs + REG_MASK);
	spin_unlock_irqrestore(&box->irq_lock, flags);
	free_irq(box->irq, box);
	dma_unmap_resource(box->rx.device, box->rx_ram, HLS_FRAME_BYTES, DMA_TO_DEVICE, 0);
	dma_unmap_resource(box->tx.device, box->tx_ram, HLS_FRAME_BYTES, DMA_FROM_DEVICE, 0);
	hls_dma_release(&box->rx); hls_dma_release(&box->tx);
	mutex_unlock(&box->rx_lock); mutex_unlock(&box->tx_lock);
	kref_put(&box->refs, hls_free);
	return 0;
}

/* Observe queue/interrupt state without consuming a frame; fields may span cycles. */
static ssize_t status_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	struct hls_mailbox *box = dev_get_drvdata(dev);
	u32 state;
	ssize_t bytes;

	mutex_lock(&box->life_lock);
	if (box->dead) {
		bytes = -ENODEV;
	} else {
		state = readl(box->regs + REG_STATUS);
		bytes = sysfs_emit(buf,
			"tx_busy=%u rx_full=%u rx_active=%u fault=%u failed=%u rx_bytes=%u events=%x mask=%x\n",
			!!(state & TX_BUSY), !!(state & RX_FULL), !!(state & RX_ACTIVE), !!(state & FAULT),
			READ_ONCE(box->failed), readl(box->regs + REG_RX_LENGTH),
			readl(box->regs + REG_EVENTS), readl(box->regs + REG_MASK));
	}
	mutex_unlock(&box->life_lock);
	return bytes;
}
static DEVICE_ATTR_RO(status);
static struct attribute *hls_attrs[] = { &dev_attr_status.attr, NULL };
ATTRIBUTE_GROUPS(hls);

static const struct of_device_id hls_match[] = {
	{ .compatible = "erl-hls,dma-mailbox-v1" }, {}
};
MODULE_DEVICE_TABLE(of, hls_match);
static struct platform_driver hls_driver = {
	.probe = hls_probe, .remove = hls_remove,
	.driver = { .name = "hls-dma-mailbox", .of_match_table = hls_match, .dev_groups = hls_groups },
};
module_platform_driver(hls_driver);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("PL330-backed routed frame mailbox for Zynq bring-up");
