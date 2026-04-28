// axisdma_shim.c

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/mm.h>
#include <linux/uaccess.h>
#include <linux/dmaengine.h>
#include <linux/dma-mapping.h>
#include <linux/completion.h>
#include <linux/of.h>
#include <linux/of_dma.h>

#define DEVNAME "axisdma0"
#define AXISDMA_IOC_MAGIC  'q'
#define AXISDMA_IOC_GET_BUFSZ _IOR(AXISDMA_IOC_MAGIC, 1, __u32)
#define AXISDMA_IOC_START     _IOW(AXISDMA_IOC_MAGIC, 2, __u32)
#define AXISDMA_IOC_GET_INFO  _IOR(AXISDMA_IOC_MAGIC, 3, struct axisdma_info)

#define BUF_SZ   (64 * 1024)

struct axisdma_dev {
    struct device *dev;
    struct dma_chan *tx_chan;
    struct dma_chan *rx_chan;

    void *tx_virt;
    dma_addr_t tx_dma;
    void *rx_virt;
    dma_addr_t rx_dma;

    struct completion tx_done;
    struct completion rx_done;

    dev_t devt;
    struct cdev cdev;
    struct class *class;
};

struct axisdma_info {
    __u32 bufsz;
    __u32 _pad;
    __u64 tx_dma;
    __u64 rx_dma;
};

static void axisdma_tx_cb(void *arg)
{
    complete(&((struct axisdma_dev *)arg)->tx_done);
}

static void axisdma_rx_cb(void *arg)
{
    complete(&((struct axisdma_dev *)arg)->rx_done);
}

static int axisdma_open(struct inode *inode, struct file *f)
{
    struct axisdma_dev *d = container_of(inode->i_cdev, struct axisdma_dev, cdev);
    f->private_data = d;
    return 0;
}

static int axisdma_mmap(struct file *f, struct vm_area_struct *vma)
{
    struct axisdma_dev *d = f->private_data;
    unsigned long size = vma->vm_end - vma->vm_start;
    unsigned long off = vma->vm_pgoff << PAGE_SHIFT;

    if (size > BUF_SZ)
        return -EINVAL;

    if (off == 0) {
        vma->vm_pgoff = 0;
        return dma_mmap_coherent(d->dev, vma, d->tx_virt, d->tx_dma, BUF_SZ);
    }

    if (off == BUF_SZ) {
        vma->vm_pgoff = 0;
        return dma_mmap_coherent(d->dev, vma, d->rx_virt, d->rx_dma, BUF_SZ);
    }

    return -EINVAL;
}

static long axisdma_ioctl(struct file *f, unsigned int cmd, unsigned long arg)
{
    struct axisdma_dev *d = f->private_data;
    struct dma_async_tx_descriptor *txd, *rxd;
    dma_cookie_t tx_cookie, rx_cookie;
    enum dma_ctrl_flags flags = DMA_CTRL_ACK | DMA_PREP_INTERRUPT;
    __u32 len;
    int ret;

    switch (cmd) {
    case AXISDMA_IOC_GET_BUFSZ:
        len = BUF_SZ;
        return copy_to_user((void __user *)arg, &len, sizeof(len)) ? -EFAULT : 0;

    case AXISDMA_IOC_GET_INFO:
        struct axisdma_info info = {
            .bufsz = BUF_SZ,
            .tx_dma = d->tx_dma,
            .rx_dma = d->rx_dma,
        };
        return copy_to_user((void __user *)arg, &info, sizeof(info)) ? -EFAULT : 0;

    case AXISDMA_IOC_START:
        if (copy_from_user(&len, (void __user *)arg, sizeof(len)))
            return -EFAULT;
        if (!len || len > BUF_SZ)
            return -EINVAL;

        // patch to encourage 32 bit width
        dev_info(d->dev, "START len=%u tx_dma=%pad rx_dma=%pad\n",
            len, &d->tx_dma, &d->rx_dma);
        // end patch to encourage 32 bit width

        reinit_completion(&d->tx_done);
        reinit_completion(&d->rx_done);

        rxd = dmaengine_prep_slave_single(d->rx_chan, d->rx_dma, len,
                                          DMA_DEV_TO_MEM, flags);
        if (!rxd)
            return -EIO;
        rxd->callback = axisdma_rx_cb;
        rxd->callback_param = d;
        rx_cookie = dmaengine_submit(rxd);
        ret = dma_submit_error(rx_cookie);
        if (ret)
            return ret;

        txd = dmaengine_prep_slave_single(d->tx_chan, d->tx_dma, len,
                                          DMA_MEM_TO_DEV, flags);
        if (!txd)
            return -EIO;
        txd->callback = axisdma_tx_cb;
        txd->callback_param = d;
        tx_cookie = dmaengine_submit(txd);
        ret = dma_submit_error(tx_cookie);
        if (ret)
            return ret;

        dma_async_issue_pending(d->rx_chan);
        dma_async_issue_pending(d->tx_chan);

        if (!wait_for_completion_timeout(&d->rx_done, msecs_to_jiffies(1000)))
            return -ETIMEDOUT;
        if (!wait_for_completion_timeout(&d->tx_done, msecs_to_jiffies(1000)))
            return -ETIMEDOUT;

        return 0;
    }

    return -ENOTTY;
}

static const struct file_operations axisdma_fops = {
    .owner          = THIS_MODULE,
    .open           = axisdma_open,
    .unlocked_ioctl = axisdma_ioctl,
    .mmap           = axisdma_mmap,
};

static int axisdma_probe(struct platform_device *pdev)
{
    struct axisdma_dev *d;
    int ret;

    d = devm_kzalloc(&pdev->dev, sizeof(*d), GFP_KERNEL);
    if (!d)
        return -ENOMEM;

    d->dev = &pdev->dev;
    init_completion(&d->tx_done);
    init_completion(&d->rx_done);

    d->tx_chan = dma_request_chan(&pdev->dev, "tx");
    if (IS_ERR(d->tx_chan))
        return PTR_ERR(d->tx_chan);

    d->rx_chan = dma_request_chan(&pdev->dev, "rx");
    if (IS_ERR(d->rx_chan)) {
        ret = PTR_ERR(d->rx_chan);
        dma_release_channel(d->tx_chan);
        return ret;
    }

    // patch to encourage 32 bit width
    struct dma_slave_config txcfg = {0};
    struct dma_slave_config rxcfg = {0};

    txcfg.direction = DMA_MEM_TO_DEV;
    txcfg.src_addr_width = DMA_SLAVE_BUSWIDTH_4_BYTES;
    txcfg.dst_addr_width = DMA_SLAVE_BUSWIDTH_4_BYTES;
    txcfg.src_maxburst = 1;
    txcfg.dst_maxburst = 1;

    ret = dmaengine_slave_config(d->tx_chan, &txcfg);
    if (ret) {
        dev_err(d->dev, "tx dmaengine_slave_config failed: %d\n", ret);
        goto err_dma;
    }

    rxcfg.direction = DMA_DEV_TO_MEM;
    rxcfg.src_addr_width = DMA_SLAVE_BUSWIDTH_4_BYTES;
    rxcfg.dst_addr_width = DMA_SLAVE_BUSWIDTH_4_BYTES;
    rxcfg.src_maxburst = 1;
    rxcfg.dst_maxburst = 1;

    ret = dmaengine_slave_config(d->rx_chan, &rxcfg);
    if (ret) {
        dev_err(d->dev, "rx dmaengine_slave_config failed: %d\n", ret);
        goto err_dma;
    }

    dev_info(d->dev, "tx_chan=%s rx_chan=%s configured for 4-byte width\n",
        dma_chan_name(d->tx_chan), dma_chan_name(d->rx_chan));
    // end patch to encourage 32 bit width

    d->tx_virt = dma_alloc_coherent(d->dev, BUF_SZ, &d->tx_dma, GFP_KERNEL);
    d->rx_virt = dma_alloc_coherent(d->dev, BUF_SZ, &d->rx_dma, GFP_KERNEL);
    if (!d->tx_virt || !d->rx_virt) {
        ret = -ENOMEM;
        goto err_dma;
    }

    ret = alloc_chrdev_region(&d->devt, 0, 1, DEVNAME);
    if (ret)
        goto err_mem;

    cdev_init(&d->cdev, &axisdma_fops);
    ret = cdev_add(&d->cdev, d->devt, 1);
    if (ret)
        goto err_chr;

    d->class = class_create(DEVNAME);
    if (IS_ERR(d->class)) {
        ret = PTR_ERR(d->class);
        goto err_cdev;
    }

    device_create(d->class, NULL, d->devt, NULL, DEVNAME);
    platform_set_drvdata(pdev, d);
    dev_info(&pdev->dev, "axisdma shim ready\n");
    return 0;

err_cdev:
    cdev_del(&d->cdev);
err_chr:
    unregister_chrdev_region(d->devt, 1);
err_mem:
    if (d->tx_virt)
        dma_free_coherent(d->dev, BUF_SZ, d->tx_virt, d->tx_dma);
    if (d->rx_virt)
        dma_free_coherent(d->dev, BUF_SZ, d->rx_virt, d->rx_dma);
err_dma:
    dma_release_channel(d->rx_chan);
    dma_release_channel(d->tx_chan);
    return ret;
}

static int axisdma_remove(struct platform_device *pdev)
{
    struct axisdma_dev *d = platform_get_drvdata(pdev);

    device_destroy(d->class, d->devt);
    class_destroy(d->class);
    cdev_del(&d->cdev);
    unregister_chrdev_region(d->devt, 1);
    dma_free_coherent(d->dev, BUF_SZ, d->tx_virt, d->tx_dma);
    dma_free_coherent(d->dev, BUF_SZ, d->rx_virt, d->rx_dma);
    dma_release_channel(d->rx_chan);
    dma_release_channel(d->tx_chan);
    return 0;
}

static const struct of_device_id axisdma_of_match[] = {
    { .compatible = "demo,axisdma-test" },
    {}
};
MODULE_DEVICE_TABLE(of, axisdma_of_match);

static struct platform_driver axisdma_driver = {
    .probe  = axisdma_probe,
    .remove = axisdma_remove,
    .driver = {
        .name = "axisdma_shim",
        .of_match_table = axisdma_of_match,
    },
};

module_platform_driver(axisdma_driver);
MODULE_LICENSE("GPL");
