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
//     Code to read and decode data from the snooper which records
//     transactions on the bus between the AFU and PSL.
//
////////////////////////////////////////////////////////////////////////

#include "snooper.h"
#include "wqueue_emul.h"

#include <inttypes.h>
#include <stdio.h>

struct cmd_lut {
    int value;
    const char *str;
} cmd_lut[] = {
    {0x0A00, "READ CL NA "},
    {0x0A50, "READ CL S  "},
    {0x0A60, "READ CL M  "},
    {0x0A6B, "READ CL LCK"},
    {0x0A67, "READ CL RES"},
    {0x0A52, "READ PE    "},
    {0x0E00, "READ PNA   "},

    {0x0240, "TOUCH I    "},
    {0x0250, "TOUCH S    "},
    {0x0260, "TOUCH M    "},

    {0x0D60, "WRITE MI   "},
    {0x0D70, "WRITE MS   "},
    {0x0D6B, "WRITE UNLK "},
    {0x0D67, "WRITE C    "},
    {0x0D00, "WRITE NA   "},
    {0x0D10, "WRITE INJ  "},

    {0x0140, "PUSH I     "},
    {0x0150, "PUSH I     "},
    {0x1140, "EVICT I    "},
    {0x016B, "LOCK       "},
    {0x017B, "UNLOCK     "},

    {0x0100, "FLUSH      "},
    {0x0000, "INTREQ     "},
    {0x0001, "RESTART    "},
    {-1,     "UNKNOWN    "},
};

static const char *cmd_str(unsigned cmd)
{
    struct cmd_lut *l;
    for (l = cmd_lut; l->value != cmd && l->value != -1; l++);
    return l->str;
}

struct resp_lut {
    int value;
    const char *str;
} resp_lut[] = {
    {0,  "Success"},
    {1,  "Addr Error"},
    {3,  "Data Error"},
    {4,  "NLOCK Error"},
    {5,  "NRES Error"},
    {6,  "Flushed Error"},
    {7,  "Fault"},
    {8,  "Failed"},
    {10, "Paged Error"},
    {11, "Context Error"},
    {-1, "Unknown"},
};

static const char *resp_str(unsigned resp)
{
    struct resp_lut *l;
    for (l = resp_lut; l->value != resp && l->value != -1; l++);
    return l->str;
}

static struct snooper_mmio *mmio = NULL;

void snooper_init(struct snooper_mmio *mmio_)
{
    mmio = mmio_;
}

struct snooper_bitfield {
    unsigned cvalid:1;
    unsigned rvalid:1;
    unsigned csize:12;
    unsigned ccom:13;
    unsigned ctag:8;
    unsigned caddr:12;
    unsigned rresp:8;
    unsigned rtag:8;
    unsigned valid:1;
} __attribute__((packed));

void snooper_dump(struct cxl_afu_h *afu)
{
    if (mmio == NULL)
        return;

    while(1) {
        uint64_t data;
        struct snooper_bitfield *bdata = (void*) &data;
        cxl->mmio_read64(afu, &mmio->data, (uint64_t *)&data);

        if (!bdata->valid)
            break;

        if (bdata->cvalid)
            fprintf(stderr, "SNP: %016"PRIx64" C - M=%-3x A=%-5x T=%-2x S=%-2x - %s\n", data,
                    bdata->ccom, bdata->caddr << 7, bdata->ctag, bdata->csize,
                    cmd_str(bdata->ccom));

        if (bdata->rvalid)
            fprintf(stderr, "SNP: %016"PRIx64" R - T=%-2x R=%-2x               - %s\n", data,
                    bdata->rtag, bdata->rresp, resp_str(bdata->rresp));

    }
}

uint64_t snooper_xor_sum(struct cxl_afu_h *afu)
{
    uint64_t ret;
    cxl->mmio_read64(afu, &mmio->xor_sum, (uint64_t *)&ret);

    return ret;
}

uint64_t snooper_tag_alert(struct cxl_afu_h *afu)
{
    uint64_t ret;
    cxl->mmio_read64(afu, &mmio->tag_alert, (uint64_t *)&ret);

    return ret;
}

void snooper_tag_usage(struct cxl_afu_h *afu)
{
    uint32_t tag_count, acc_count;
    cxl->mmio_read32(afu, &mmio->tag_count, &tag_count);
    cxl->mmio_read32(afu, &mmio->acc_count, &acc_count);

    printf("Tag Usage:          %.3e\n", (double)tag_count/
        acc_count);
}

void snooper_tag_stats(struct cxl_afu_h *afu, int dump)
{
    uint32_t tag_min, tag_max, count = 0;
    uint64_t tag_avg = 0, tag_std = 0;
    cxl->mmio_read32(afu, &mmio->tag_min, &tag_min);
    cxl->mmio_read32(afu, &mmio->tag_max, &tag_max);

    if (mmio == NULL)
        return;

    while(1) {
        uint64_t tag_data;
        cxl->mmio_read64(afu, &mmio->tag_data, (uint64_t *)&tag_data);
        if (!tag_data)
            break;

	if (dump)
	  fprintf(stderr, "TAG: %-4d\t%8d\n", count,
		  (uint32_t)tag_data);

        tag_avg += tag_data;
        tag_std += (tag_data*tag_data);
        count++;
    }
    if (!count)
        printf("Tag Time (min/max): %d/%d\n", tag_min,
               tag_max);
    else{
        printf("Tag Time (avg/std/min/max/count): %2.2f/%2.2f/%d/%d/%d\n", (double)tag_avg/count,
               (double)tag_std/count, tag_min, tag_max, count);
    }
}
