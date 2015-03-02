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
//     CAPI Common Code
//
////////////////////////////////////////////////////////////////////////

#ifndef LIBCAPI_CAPI_H
#define LIBCAPI_CAPI_H

#include <stdlib.h>

#define CAPI_CACHELINE_BYTES    128
#define CAPI_TIMER_FREQ         250000000

void *capi_alloc(size_t size);

#endif
