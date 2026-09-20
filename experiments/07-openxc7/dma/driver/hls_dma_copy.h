/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef HLS_DMA_COPY_H
#define HLS_DMA_COPY_H

#include <linux/completion.h>
#include <linux/dmaengine.h>
#include <linux/dma-mapping.h>

#define HLS_FRAME_BYTES 1028

/* A serialized DMA channel and its coherent host packet slot. */
struct hls_dma_copy {
	struct dma_chan *channel;
	struct device *device;
	void *buffer;
	dma_addr_t address;
	struct completion done;
};

/* Complete exactly the submitted copy; callers retain storage until synchronized. */
static inline void hls_dma_done(void *arg)
{
	complete(arg);
}

/* Acquire the named DT channel and allocate one maximum-size routed frame. */
static inline int hls_dma_acquire(struct device *dev, const char *name,
				struct hls_dma_copy *copy)
{
	copy->channel = dma_request_chan(dev, name);
	if (IS_ERR(copy->channel))
		return PTR_ERR(copy->channel);
	if (!dma_has_cap(DMA_MEMCPY, copy->channel->device->cap_mask)) {
		dma_release_channel(copy->channel);
		return -EOPNOTSUPP;
	}
	copy->device = dmaengine_get_dma_device(copy->channel);
	copy->buffer = dma_alloc_coherent(copy->device, HLS_FRAME_BYTES,
					&copy->address, GFP_KERNEL);
	if (!copy->buffer) {
		dma_release_channel(copy->channel);
		return -ENOMEM;
	}
	init_completion(&copy->done);
	return 0;
}

/* Cancel outstanding work before releasing the callback and coherent storage. */
static inline void hls_dma_release(struct hls_dma_copy *copy)
{
	dmaengine_terminate_sync(copy->channel);
	dma_free_coherent(copy->device, HLS_FRAME_BYTES, copy->buffer, copy->address);
	dma_release_channel(copy->channel);
}

/* Copy bytes and wait at most five seconds; errors leave no running descriptor. */
static inline int hls_dma_transfer(struct hls_dma_copy *copy, dma_addr_t dst,
				 dma_addr_t src, size_t bytes)
{
	struct dma_async_tx_descriptor *desc;
	dma_cookie_t cookie;
	long waited;
	int error;

	reinit_completion(&copy->done);
	desc = dmaengine_prep_dma_memcpy(copy->channel, dst, src, bytes,
				       DMA_PREP_INTERRUPT | DMA_CTRL_ACK);
	if (!desc)
		return -EIO;
	desc->callback = hls_dma_done;
	desc->callback_param = &copy->done;
	cookie = dmaengine_submit(desc);
	error = dma_submit_error(cookie);
	if (error)
		goto stop;
	dma_async_issue_pending(copy->channel);
	waited = wait_for_completion_interruptible_timeout(&copy->done, 5 * HZ);
	if (waited <= 0) {
		error = waited ? (int)waited : -ETIMEDOUT;
		goto stop;
	}
	if (dma_async_is_tx_complete(copy->channel, cookie, NULL, NULL) != DMA_COMPLETE) {
		error = -EIO;
		goto stop;
	}
	dmaengine_synchronize(copy->channel);
	return 0;
stop:
	dmaengine_terminate_sync(copy->channel);
	return error;
}
#endif
