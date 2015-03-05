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

#ifndef LIBCAPI_SNOOPER_H
#define LIBCAPI_SNOOPER_H

#include <libcxl.h>
#include <stdint.h>

struct snooper_mmio {
    uint64_t data;

    uint64_t xor_sum;
    uint64_t tag_alert;
    uint32_t acc_count;
    uint32_t tag_count;
    uint32_t tag_min;
    uint32_t tag_max;
    uint64_t tag_data;
    uint64_t reserved[10];
};

void snooper_init(struct snooper_mmio *mmio);
void snooper_dump(struct cxl_afu_h *afu);
uint64_t snooper_xor_sum(struct cxl_afu_h *afu);
uint64_t snooper_tag_alert(struct cxl_afu_h *afu);
void snooper_tag_usage(struct cxl_afu_h *afu);
void snooper_tag_stats(struct cxl_afu_h *afu, int dump);

#endif
