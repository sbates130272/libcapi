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
//     Build version register code
//
////////////////////////////////////////////////////////////////////////

#ifndef LIBCAPI_BUILD_VERSION_H
#define LIBCAPI_BUILD_VERSION_H

#include <stdint.h>
#include <stdio.h>

#define BUILD_VERSION_LEN 25

struct build_version_mmio {
    char version[24];
    uint64_t timestamp;
    uint64_t reserved[28];
};

struct cxl_afu_h;

void build_version_get(struct cxl_afu_h *afu_h, struct build_version_mmio *mmio,
                       uint64_t *timestamp, char *version);
void build_version_print(FILE *out, struct cxl_afu_h *afu_h,
                         struct build_version_mmio *mmio);

void build_version_emul_init(const char *version);
int build_version_mmio_read(struct build_version_mmio *mmio,
                            void *offset, void *data, size_t data_size);


#endif
