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

#ifndef LIBCAPI_WQUEUE_H
#define LIBCAPI_WQUEUE_H

#include <stdlib.h>
#include <stdint.h>

struct wqueue_mmio {
    uint64_t queue_len;
    uint64_t trigger;
    uint64_t force_stop;
    uint64_t debug;
    uint32_t read_count;
    uint32_t write_count;
    uint64_t croom;
    uint64_t timer;
    uint64_t reserved[25];
};

enum {
    WQ_DIRTY_FLAG        = (1 << 2),
    WQ_ALWAYS_WRITE_FLAG = (1 << 3),
    WQ_LAST_ITEM_FLAG    = (1 << 4),
    WQ_WRITE_ONLY_FLAG   = (1 << 5),
};

struct wqueue_item {
    int flags;
    const void *src;
    void *dst;
    size_t src_len;
    size_t dst_len;
    unsigned start_time, end_time;
    void *opaque;
};

int wqueue_init(char *cxl_dev, struct wqueue_mmio *_mmio, size_t queue_len);
void wqueue_cleanup(void);

void wqueue_push(const struct wqueue_item *qitem);
int wqueue_pop(struct wqueue_item *qitem);

struct cxl_afu_h *wqueue_afu(void);

uint64_t wqueue_xor_sum(void);

double wqueue_calc_duration(struct wqueue_item *it);

void wqueue_set_croom(int croom);

#endif
