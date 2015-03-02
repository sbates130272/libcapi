////////////////////////////////////////////////////////////////////////
//
// Copyright 2014 PMC-Sierra, Inc.
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
//   Date:   Oct 23 2014
//
//   Description:
//     Common Worker Thread Code
//
////////////////////////////////////////////////////////////////////////


#include "worker.h"
#include "utils.h"

#include <sys/time.h>
#include <sys/resource.h>

#include <stdlib.h>
#include <stdio.h>

int worker_start(struct worker *w, int num_threads,
                 void *(*start_routine) (void *))
{
    w->num_threads = num_threads;

    w->threads = malloc(sizeof(*w->threads) * num_threads);
    if (w->threads == NULL)
        return 1;

    w->rusage = malloc(sizeof(*w->rusage) * num_threads);
    if (w->rusage == NULL)
        goto free_threads_and_exit;

    int threads;
    for (threads = 0; threads < num_threads; threads++)
        if (pthread_create(&w->threads[threads], NULL, start_routine, w) != 0)
            goto cancel_threads;

    return 0;

cancel_threads:
    threads--;
    for (; threads >= 0; threads--)
        pthread_cancel(w->threads[threads]);

    free(w->rusage);

free_threads_and_exit:
    free(w->threads);

    return 1;
}

void worker_print_cputime(struct worker *w, struct rusage *ru, const char *x)
{
    double user_total = 0;
    double sys_total = 0;

    if (ru != NULL) {
        double user = utils_timeval_to_secs(&ru->ru_utime);
        double sys = utils_timeval_to_secs(&ru->ru_stime);

        user_total += user;
        sys_total += sys;

        fprintf(stderr, "   %3s    %.1fs user, %.1fs system\n",
                x, user, sys);
    }


    for (int i = 0; i < w->num_threads; i++) {
        double user = utils_timeval_to_secs(&w->rusage[i].ru_utime);
        double sys = utils_timeval_to_secs(&w->rusage[i].ru_stime);

        user_total += user;
        sys_total += sys;

        fprintf(stderr, "   %3d    %.1fs user, %.1fs system\n",
                i, user, sys);
    }

    fprintf(stderr, "   Tot    %.1fs user, %.1fs system\n",
            user_total, sys_total);
}


void worker_join(struct worker *w)
{
    for (int i = 0; i < w->num_threads; i++)
        pthread_join(w->threads[i], NULL);
}

void worker_free(struct worker *w)
{
    free(w->rusage);
    free(w->threads);
}

void worker_finish_thread(struct worker *w)
{
    pthread_t self = pthread_self();

    int i;
    for (i = 0; i < w->num_threads; i++)
        if (w->threads[i] == self)
            break;

    getrusage(RUSAGE_THREAD, &w->rusage[i]);
}
