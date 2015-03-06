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

#include "build_version.h"
#include "wqueue_emul.h"

#include <string.h>
#include <time.h>

void build_version_get(struct cxl_afu_h *afu_h, struct build_version_mmio *mmio,
                       uint64_t *timestamp, char *version)
{
    version[BUILD_VERSION_LEN-1] = 0;

    for (int i = 0; i < BUILD_VERSION_LEN-1; i+= 8) {
        cxl->mmio_read64(afu_h, &mmio->version[i], (uint64_t *) &version[i]);

    }

    cxl->mmio_read64(afu_h, &mmio->timestamp, timestamp);

    //Trim off trailing spaces that are required by quartus
    for (int i = BUILD_VERSION_LEN-2; i >= 0; i--) {
        if (version[i] == ' ')
            version[i] = 0;
        else
            break;
    }
}

void build_version_print(FILE *out, struct cxl_afu_h *afu_h,
                         struct build_version_mmio *mmio)
{
    char version[BUILD_VERSION_LEN];
    uint64_t timestamp;

    build_version_get(afu_h, mmio, &timestamp, version);

    time_t buildtime = timestamp;
    fprintf(out, "FPGA Build Version:\t%s\n", version);
    fprintf(out, "FPGA Build Time:   \t%s", asctime(localtime(&buildtime)));
}


static char build_version[24];
static uint64_t build_timestamp;

void build_version_emul_init(const char *version)
{
    build_timestamp = time(NULL);
    strncpy(build_version, version, sizeof(build_version));
}

int build_version_mmio_read(struct build_version_mmio *mmio,
                            void *offset, void *data, size_t data_size)
{
    if (offset < (void *)mmio || offset >= (void *)&mmio[1])
        return -1;

    if (offset >= (void *)&mmio->version &&
        offset < (void *)&mmio->timestamp)
    {
        memcpy(data, &build_version[(intptr_t) offset -
                                    (intptr_t) &mmio->version],
               data_size);
    } else if (offset >= (void *) &mmio->timestamp &&
               offset < (void *) &mmio->reserved[0])
    {
        memcpy(data, &build_timestamp, data_size);
    }

    return 0;
}
