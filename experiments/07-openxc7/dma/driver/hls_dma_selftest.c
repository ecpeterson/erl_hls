// SPDX-License-Identifier: GPL-2.0-only
/* Optional QEMU/board test of the real PL330 provider, without accessing PL MMIO. */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include "hls_dma_copy.h"

/* Copy across both DT-selected channels, checking routed-frame sizes and guards. */
static int __init hls_test_init(void)
{
	struct device_node *node;
	struct platform_device *pdev;
	struct hls_dma_copy tx, rx;
	static const size_t lengths[] = {8, 12, 64, 1024, 1028};
	unsigned int i, j;
	int error;

	node = of_find_compatible_node(NULL, NULL, "erl-hls,dma-mailbox-v1");
	if (!node)
		return -ENODEV;
	pdev = of_find_device_by_node(node);
	of_node_put(node);
	if (!pdev)
		return -ENODEV;
	error = hls_dma_acquire(&pdev->dev, "tx", &tx);
	if (error)
		goto put;
	error = hls_dma_acquire(&pdev->dev, "rx", &rx);
	if (error)
		goto release_tx;
	if (tx.device != rx.device) {
		error = -EINVAL;
		goto release_rx;
	}
	for (i = 0; i < ARRAY_SIZE(lengths); i++) {
		for (j = 0; j < HLS_FRAME_BYTES; j++)
			((u8 *)tx.buffer)[j] = (j * 37 + i) & 255;
		memset(rx.buffer, 0xa5, HLS_FRAME_BYTES);
		error = hls_dma_transfer(&tx, rx.address, tx.address, lengths[i]);
		if (error || memcmp(tx.buffer, rx.buffer, lengths[i])) {
			error = error ?: -EILSEQ;
			goto release_rx;
		}
		for (j = lengths[i]; j < HLS_FRAME_BYTES; j++)
			if (((u8 *)rx.buffer)[j] != 0xa5) {
				error = -EOVERFLOW;
				goto release_rx;
			}
		memset(tx.buffer, 0x5a, HLS_FRAME_BYTES);
		error = hls_dma_transfer(&rx, tx.address, rx.address, lengths[i]);
		if (error || memcmp(tx.buffer, rx.buffer, lengths[i])) {
			error = error ?: -EILSEQ;
			goto release_rx;
		}
		for (j = lengths[i]; j < HLS_FRAME_BYTES; j++)
			if (((u8 *)tx.buffer)[j] != 0x5a) {
				error = -EOVERFLOW;
				goto release_rx;
			}
	}
	pr_info("PASS: PL330 DMAengine copied five frame sizes on both channels\n");
release_rx:
	hls_dma_release(&rx);
release_tx:
	hls_dma_release(&tx);
put:
	put_device(&pdev->dev);
	return error;
}

/* Tests release their resources before init returns, so unloading has no work. */
static void __exit hls_test_exit(void)
{
}
module_init(hls_test_init);
module_exit(hls_test_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Explicit PL330 DDR-copy acceptance test for Zynq bring-up");
