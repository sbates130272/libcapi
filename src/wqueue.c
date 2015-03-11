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
//     Wqueue code to queue and dequeue buffers in the wqueue block in
//     hardware.
//
////////////////////////////////////////////////////////////////////////

#include "wqueue.h"
#include "wed.h"
#include "wqueue_emul.h"
#include "capi.h"

#include <libcxl.h>

#include <pthread.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>


static struct wed *wed;
static unsigned wed_push = 0;
static unsigned wed_pop = 0;
static size_t queue_len;
static struct wqueue_mmio *mmio;
static struct cxl_afu_h *afu_h;

static pthread_mutex_t push_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t push_condition = PTHREAD_COND_INITIALIZER;
static pthread_mutex_t pop_mutex = PTHREAD_MUTEX_INITIALIZER;

static uint64_t xor_sum;

static int afu_init(char *cxl_dev)
{
    afu_h = cxl->afu_open_dev (cxl_dev);
    if (afu_h == NULL) {
        fprintf(stderr, "ERROR: cannot open AFU device '%s': %s\n",
                cxl_dev, strerror(errno));
        return -1;
    }

    if (cxl->afu_attach (afu_h, (uint64_t) wed)) {
        fprintf(stderr, "ERROR: could not attach to AFU device '%s': %s\n",
                cxl_dev, strerror(errno));
        goto close_afu;
    }

    if ((cxl->mmio_map(afu_h, CXL_MMIO_BIG_ENDIAN)) < 0) {
        fprintf(stderr, "ERROR: could not map the MMIO memory on  AFU device '%s': %s\n",
                cxl_dev, strerror(errno));
        goto close_afu;
    }

    return 0;

close_afu:
    cxl->afu_free(afu_h);
    return -1;
}

int wqueue_init(char *cxl_dev, struct wqueue_mmio *_mmio, size_t _queue_len)
{
    int ret = posix_memalign((void**) &wed, CAPI_CACHELINE_BYTES,
                             _queue_len * sizeof(*wed));
    if (ret || wed == NULL) {
        errno = ret;
        perror("allocating wed");
        return -1;
    }

    memset(wed, 0, _queue_len * sizeof(*wed));

    if (afu_init(cxl_dev))
        goto free_wed;

    xor_sum = 0;
    mmio = _mmio;
    wed_push = wed_pop = 0;
    queue_len = _queue_len;
    cxl->mmio_write64(afu_h, &mmio->queue_len, queue_len-1);

    return 0;

free_wed:
    free(wed);
    return -1;
}

void wqueue_cleanup(void)
{
    cxl->mmio_write64(afu_h, &mmio->force_stop, 1);
    cxl->afu_free(afu_h);
    free(wed);
}

static inline unsigned next_wed(unsigned x)
{
    x++;
    if (x == queue_len)
        return 0;
    return x;
}

static void calc_xor(uint64_t *x)
{
    for (int i = 0; i < sizeof(struct wed) / sizeof(uint64_t); i++)
        xor_sum ^= x[i];
}

void wqueue_push(const struct wqueue_item *qitem)
{
    int flags = qitem->flags;
    flags &= ~WQ_DONE_FLAG;
    flags |= WQ_READY_FLAG;

    if (qitem->src != qitem->dst)
        flags |= WQ_ALWAYS_WRITE_FLAG;

    pthread_mutex_lock(&push_mutex);

    while(wed[wed_push].flags)
        pthread_cond_wait(&push_condition, &push_mutex);

    wed[wed_push].error_code = 0;
    wed[wed_push].src = qitem->src;
    wed[wed_push].dst = qitem->dst;
    wed[wed_push].chunk_length = qitem->src_len / CAPI_CACHELINE_BYTES;
    wed[wed_push].src_len = qitem->src_len;
    wed[wed_push].opaque = qitem->opaque;

    calc_xor((uint64_t *) &wed[wed_push]);
    xor_sum ^= flags;

    __sync_synchronize ();
    wed[wed_push].flags = flags;
    __sync_synchronize ();

    cxl->mmio_write64(afu_h, &mmio->trigger, 1);

    wed_push = next_wed(wed_push);

    pthread_mutex_unlock(&push_mutex);
}

int wqueue_pop(struct wqueue_item *qitem)
{
    int ret = 0;
    int timeout_counter = 0;

    while (1) {
        pthread_mutex_lock(&pop_mutex);

        if (wed[wed_pop].flags & WQ_DONE_FLAG)
            break;

        pthread_mutex_unlock(&pop_mutex);
        timeout_counter++;
        if (timeout_counter >= 1000)
            return -1;
        usleep(10000);
    }

    timeout_counter = 0;
    qitem->src = wed[wed_pop].src;
    qitem->dst = wed[wed_pop].dst;
    qitem->src_len = wed[wed_pop].src_len;
    qitem->dst_len = wed[wed_pop].chunk_length * CAPI_CACHELINE_BYTES;
    qitem->flags = wed[wed_pop].flags;
    qitem->start_time = wed[wed_pop].start_time;
    qitem->end_time = wed[wed_pop].end_time;
    qitem->opaque = wed[wed_pop].opaque;
    ret = wed[wed_pop].error_code;

    __sync_synchronize ();

    wed[wed_pop].flags = 0;

    wed_pop = next_wed(wed_pop);

    pthread_mutex_unlock(&pop_mutex);

    pthread_mutex_lock(&push_mutex);
    pthread_cond_signal(&push_condition);
    pthread_mutex_unlock(&push_mutex);

    return ret;
}

struct cxl_afu_h *wqueue_afu(void)
{
    return afu_h;
}

uint64_t wqueue_xor_sum(void)
{
    return xor_sum;
}

double wqueue_calc_duration(struct wqueue_item *it)
{
    unsigned long cycles = it->end_time - it->start_time;

    return ((double)cycles) / CAPI_TIMER_FREQ;
}

void wqueue_set_croom(int croom)
{
    cxl->mmio_write64(afu_h, &mmio->croom, croom);
}
