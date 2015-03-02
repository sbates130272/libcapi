////////////////////////////////////////////////////////////////////////
//
// Copyright 2015 PMC-Sierra, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License"); you
// may not use this file except in compliance with the License. You may
// obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0 Unless required by
// applicable law or agreed to in writing, software distributed under the
// License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for
// the specific language governing permissions and limitations under the
// License.
//
////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////
//
//   Author: Logan Gunthorpe
//
//   Description:
//     Wqueue software emulation
//
////////////////////////////////////////////////////////////////////////

#include "wqueue.h"
#include "wqueue_emul.h"
#include "capi.h"

#include "wed.h"
#include "proc.h"

#include <libcxl.h>

#include <pthread.h>
#include <sys/time.h>

#include <stddef.h>
#include <string.h>
#include <stdio.h>

int wrap_mmio_write64(struct cxl_afu_h *afu, void *offset, uint64_t data) {
    return cxl_mmio_write64(afu, (uint64_t) offset, data);
}

int wrap_mmio_write32(struct cxl_afu_h *afu, void *offset, uint32_t data) {
    return cxl_mmio_write32(afu, (uint64_t) offset, data);
}

int wrap_mmio_read64(struct cxl_afu_h *afu, void *offset, uint64_t *data) {
    return cxl_mmio_read64(afu, (uint64_t) offset, data);
}

int wrap_mmio_read32(struct cxl_afu_h *afu, void *offset, uint32_t *data) {
    return cxl_mmio_read32(afu, (uint64_t) offset, data);
}

static const struct cxl cxl_proper = {
    .afu_open_dev = cxl_afu_open_dev,
    .afu_free = cxl_afu_free,
    .afu_attach = cxl_afu_attach,
    .mmio_map = cxl_mmio_map,
    .mmio_write64 = wrap_mmio_write64,
    .mmio_write32 = wrap_mmio_write32,
    .mmio_read64 = wrap_mmio_read64,
    .mmio_read32 = wrap_mmio_read32,
};

const struct cxl *cxl = &cxl_proper;

struct cxl_afu_h {
    pthread_t thrd;
    struct wed *wed;
    struct wqueue_mmio *mmio;
    struct proc *proc;
    unsigned queue_len;
    int stop;
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    int item_count;
};

static uint64_t get_timer(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);

    double seconds = tv.tv_usec;
    seconds *= 1e-6;
    seconds += tv.tv_sec;

    return seconds * CAPI_TIMER_FREQ;
}

static void *afu_thread(void *arg)
{
    struct cxl_afu_h *afu = arg;
    int idx = 0;

    while (!afu->stop) {
        pthread_mutex_lock(&afu->mutex);
        if (afu->stop) {
            pthread_mutex_unlock(&afu->mutex);
            goto end_thread;
        }

        while (!(afu->wed[idx].flags & WQ_READY_FLAG) ||
               afu->wed[idx].flags & WQ_DONE_FLAG)
        {
            pthread_cond_wait(&afu->cond, &afu->mutex);
            if (afu->stop) {
                pthread_mutex_unlock(&afu->mutex);
                goto end_thread;
            }
        }
        pthread_mutex_unlock(&afu->mutex);


        afu->wed[idx].start_time = get_timer();

        int dirty = 0;
        int error_code;
        size_t dst_len;

        if ((afu->wed[idx].src != NULL || (afu->wed[idx].flags & WQ_WRITE_ONLY_FLAG))
            && afu->wed[idx].dst != NULL)
        {
            error_code = proc_run(afu->proc,
                                  afu->wed[idx].flags,
                                  afu->wed[idx].src,
                                  afu->wed[idx].dst,
                                  afu->wed[idx].chunk_length * CAPI_CACHELINE_BYTES,
                                  afu->wed[idx].flags & WQ_ALWAYS_WRITE_FLAG,
                                  &dirty, &dst_len);
        } else {
            error_code = 0x0011;
        }

        afu->wed[idx].error_code = error_code;
        afu->wed[idx].chunk_length = (dst_len+CAPI_CACHELINE_BYTES-1) /
            CAPI_CACHELINE_BYTES;

        int flags = afu->wed[idx].flags;
        flags &= ~WQ_READY_FLAG;
        flags |= WQ_DONE_FLAG;

        if (dirty) flags |= WQ_DIRTY_FLAG;

        afu->wed[idx].end_time = get_timer();

        __sync_synchronize ();
        afu->wed[idx].flags = flags;

        afu->item_count++;

        idx++;
        if (idx == afu->queue_len)
            idx = 0;
    }

end_thread:
    return NULL;
}

struct cxl_afu_h *emul_afu_open_dev(char *path)
{
    struct cxl_afu_h *afu = malloc(sizeof(*afu));
    if (afu == NULL)
        return NULL;

    afu->stop = -1;
    afu->mmio = (void*)-1;
    afu->item_count = 0;

    if (pthread_mutex_init(&afu->mutex, NULL))
        goto error_free_out;

    if (pthread_cond_init(&afu->cond, NULL))
        goto error_mutex_out;

    return afu;

error_mutex_out:
    pthread_mutex_destroy(&afu->mutex);
error_free_out:
    free(afu);
    return NULL;
}

void emul_afu_free(struct cxl_afu_h *afu)
{
    if (afu->stop != -1)
        pthread_join(afu->thrd, NULL);

    pthread_mutex_destroy(&afu->mutex);
    pthread_cond_destroy(&afu->cond);
    free(afu);
}

int emul_afu_attach(struct cxl_afu_h *afu, __u64 wed)
{
    afu->wed = (struct wed *) wed;
    afu->proc = proc_init();
    afu->stop = 0;

    return pthread_create(&afu->thrd, NULL, afu_thread, afu);
}

int emul_mmio_map(struct cxl_afu_h *afu, __u32 flags)
{
    return 0;
}

int emul_mmio_write64(struct cxl_afu_h *afu, void *offset, uint64_t data)
{
    if (afu->mmio == (void*)-1) {
        // Assume the first write64 is to the queue_len register
        // so we can discretely transfer the wqueue_mmio offset.
        afu->mmio = offset - offsetof(struct wqueue_mmio, queue_len);
    }

    if (offset < (void *) afu->mmio || offset >= (void *) &afu->mmio[1])
        return proc_mmio_write64(afu->proc, offset, data);

    if (offset == &afu->mmio->queue_len) {
        afu->queue_len = data + 1;
    } else if (offset == &afu->mmio->trigger) {
        pthread_mutex_lock(&afu->mutex);
        pthread_cond_signal(&afu->cond);
        pthread_mutex_unlock(&afu->mutex);
    } else if (offset == &afu->mmio->force_stop) {
        pthread_mutex_lock(&afu->mutex);
        afu->stop = 1;
        pthread_cond_signal(&afu->cond);
        pthread_mutex_unlock(&afu->mutex);
    }

    return 0;
}

int emul_mmio_write32(struct cxl_afu_h *afu, void *offset, uint32_t data)
{
    if (offset < (void *) afu->mmio || offset >= (void *) &afu->mmio[1])
        return proc_mmio_write32(afu->proc, offset, data);

    emul_mmio_write64(afu, offset, data);

    return 0;
}

int emul_mmio_read64(struct cxl_afu_h *afu, void *offset, uint64_t *data)
{
    if (offset < (void *) afu->mmio || offset >= (void *) &afu->mmio[1])
        return proc_mmio_read64(afu->proc, offset, data);

    void *offsetp = (void*) offset;
    if (offsetp == &afu->mmio->queue_len) {
        *data = afu->queue_len;
    } else if (offsetp == &afu->mmio->debug) {
        *data = afu->item_count;
    } else if (offsetp == &afu->mmio->read_count) {
        *data = 0;
    }

    return 0;
}

int emul_mmio_read32(struct cxl_afu_h *afu, void *offset, uint32_t *data)
{
    if (offset < (void *) afu->mmio || offset >= (void *) &afu->mmio[1])
        return proc_mmio_read32(afu->proc, offset, data);

    uint64_t data64;
    emul_mmio_read64(afu, (void*) ((intptr_t)offset & ~7), &data64);
    if ((intptr_t) offset & 4)
        *data = data64 >> 32;
    else
        *data = data64;


    return 0;
}

__attribute__((weak))
struct proc *proc_init(void)
{
    return NULL;
}

__attribute__((weak))
int proc_mmio_write64(struct proc *proc, void *offset, uint64_t data)
{
    return 0;
}

__attribute__((weak))
int proc_mmio_write32(struct proc *proc, void *offset, uint32_t data)
{
    return 0;
}

__attribute__((weak))
int proc_mmio_read64(struct proc *proc, void *offset, uint64_t *data)
{
    *data = 0;
    return 0;
}

__attribute__((weak))
int proc_mmio_read32(struct proc *proc, void *offset, uint32_t *data)
{
    *data = 0;
    return 0;
}

__attribute__((weak))
int proc_run(struct proc *proc, int flags, const void *src, void *dst,
             size_t len, int always_write, int *dirty, size_t *dst_len)
{
    if (always_write) {
        memcpy(dst, src, len);
        *dirty = 1;
    }

    *dst_len = len;

    return 0;
}

static const struct cxl cxl_emul = {
    .afu_open_dev = emul_afu_open_dev,
    .afu_free = emul_afu_free,
    .afu_attach = emul_afu_attach,
    .mmio_map = emul_mmio_map,
    .mmio_write64 = emul_mmio_write64,
    .mmio_write32 = emul_mmio_write32,
    .mmio_read64 = emul_mmio_read64,
    .mmio_read32 = emul_mmio_read32,
};

void wqueue_emul_init(void)
{
    cxl = &cxl_emul;
}
