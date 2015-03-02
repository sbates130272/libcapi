# Work Queues

This document describes the work queue AFU block which is intended to provide an
efficient way to stream chunks of data through a processing block with minimal
overhead between blocks and with minimal CPU spinning to manage it (given the absence
of interrupts).

## Queue Elements

This block assumses the WED pointer points to an array of queue elements. The length
of the array is configurable through a MMIO register (wq_len). Each queue element
is one cache line long and consists of the following fields:

```
struct wqueue {
       volatile uint16_t flags;
       uint16_t error_code;
       uint32_t chunk_length;
       void *src;  //(64-bits)
       void *dst;  //(64-bits)
       uint64_t reserved1;
       uint64_t reserved2;
};
```

The remainder of the cache line may be used by software in anyway that it chooses.
The hardware is gauranteed not to modify that region.

The flags field is a bit field divided into the following bits:

0. WQ_READY_FLAG
1. WQ_DONE_FLAG
2. WQ_DIRTY_FLAG
3. WQ_ALWAYS_WRITE_FLAG
4. WQ_LAST_ITEM_FLAG

0. The ready flag is set by software to indicate the queue item is ready to
   be processed by the hardware.
1. The done flag will be set by the hardware once it is finished with the
   queue item.
2. The dirty flag will be set by the hardware if the data that *dst points to
   is changed.
3. The always write flag may be set by software to force the algorithm to always
   write. (If src==dst then you may not want the hardware overwriting data that
   doesn't change.)
4. The last item flag is for software use only to indicate the end of the
   queue.

When the ready flag is high and the done flag is low the hardware is deemed to
own the queue item and the software should not modify the queue item.


## Hardware function

The hardware starts by loading the first queue item and checking the flags
value. If the ready flag is set and the done flag is not set, it procedees to
load the data from the source address and feeds it through the processing block.
At the same time data from the processing block will be written back to the dst
address. Once chunk_length cache lines are read and all the data back from the
processing block is written, then the hardware will stop and write back the queue
item with the done bit set.

Once the hardware finishes with a queue item, it loads the next queue item offset
from the WED address and proceeds in the same fashion. When the hardware gets to
the end of the queue it simply wraps back to the first item.

If the hardware reads a queue item that either does not have the ready bit set
or the done bit is set then it stops in a waiting state. The hardware will resume and
reload the current queue item upon a write to a special MMIO trigger register.

## Software function

The software's task is to manage the queue. While this could be done with a single
well writen loop it is probably more flexible to use 2 or more threads. A producing
thread would follow the following psuedo code:

```
buffer = allocte_buffer(length)
read_buffer_from_disk(buffer)

acquire_lock() # If there are multiple producing threads

while (wq[push].flags & WQ_READY_FLAG)
   wait_for_condition()

wq[push].src = buffer
wq[push].dst = buffer
wq[push].chunk_length = length / CACHE_LINE_LENGTH;

full_memory_barrier()

wq[push].flags = WQ_READY_FLAG
mmio->trigger = 1 #start the hardware if it is the idle state

push = (push + 1) mod wq_len

release_lock()

```

A consuming thread would look like:

```
acquire_lock() # If there are multiple consuming threads

if !(wq[pop].flags & WQ_DONE_FLAG) {
    release_lock()
    sleep for 10 to 100ms depending on processing time of the entire buffer
    continue
}

buffer = wq[pop].dst
len = wq[pop].length
full_memory_barrier()

wq[pop].flags = 0;

broadcast_on_condition();
release_lock();

write_buffer_to_disk(buffer)
free(buffer)
```
