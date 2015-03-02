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

#ifndef LIBCAPI_WQUEUE_EMUL_H
#define LIBCAPI_WQUEUE_EMUL_H

#include <libcxl.h>

struct cxl {
    struct cxl_afu_h *(*afu_open_dev)(char *path);
    void (*afu_free)(struct cxl_afu_h *afu);
    int (*afu_attach)(struct cxl_afu_h *afu, __u64 wed);
    int (*mmio_map)(struct cxl_afu_h *afu, __u32 flags);
    int (*mmio_write64)(struct cxl_afu_h *afu, void *offset,
                        uint64_t data);
    int (*mmio_write32)(struct cxl_afu_h *afu, void *offset,
                        uint32_t data);
    int (*mmio_read64)(struct cxl_afu_h *afu, void *offset,
                       uint64_t *data);
    int (*mmio_read32)(struct cxl_afu_h *afu, void *offset,
                       uint32_t *data);
};

extern const struct cxl *cxl;

void wqueue_emul_init(void);


#endif
