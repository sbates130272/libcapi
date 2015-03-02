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
//     Software emulation processor function prototypes
//
////////////////////////////////////////////////////////////////////////

#ifndef LIBCAPI_PROC_H
#define LIBCAPI_PROC_H

#include <stdint.h>
#include <stdlib.h>

struct proc *proc_init(void);
int proc_mmio_write64(struct proc *proc, void *offset, uint64_t data);
int proc_mmio_write32(struct proc *proc, void *offset, uint32_t data);

int proc_mmio_read64(struct proc *proc, void *offset, uint64_t *data);
int proc_mmio_read32(struct proc *proc, void *offset, uint32_t *data);
int proc_run(struct proc *proc, int flags, const void *src, void *dst,
             size_t len, int always_write, int *dirty, size_t *dst_len);

#endif
