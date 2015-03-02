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
//     WED Structure Definition used by wqueue and wqueue_emul
//
////////////////////////////////////////////////////////////////////////

#ifndef WED_H
#define WED_H

#include <stdint.h>

enum {
    WQ_READY_FLAG        = (1 << 0),
    WQ_DONE_FLAG         = (1 << 1),
};

struct wed {
    uint16_t flags;
    uint16_t error_code;
    uint32_t chunk_length;
    uint32_t start_time;
    uint32_t end_time;
    const void *src;
    void *dst;
    uint64_t reserved[4];
    void *opaque;
    uint64_t src_len;
    uint64_t unused[6];
};

#endif
