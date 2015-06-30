#!/usr/bin/env python
########################################################################
##
## Copyright 2015 PMC-Sierra, Inc.
##
## Licensed under the Apache License, Version 2.0 (the "License"); you
## may not use this file except in compliance with the License. You may
## obtain a copy of the License at
## http://www.apache.org/licenses/LICENSE-2.0 Unless required by
## applicable law or agreed to in writing, software distributed under the
## License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
## CONDITIONS OF ANY KIND, either express or implied. See the License for
## the specific language governing permissions and limitations under the
## License.
##
########################################################################

########################################################################
##
##   Author: Logan Gunthorpe
##
##   Description:
##     HDL complier and simulation using Cadence IES
##
########################################################################

from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import colour as cl
import subprocess as sp
import threading
import pty
import re
import signal
import time
from distutils import spawn

import build
import version

ver = version.get_git_version()

NCVLOG_ARGS = ["-DEFINE", "BUILD_TIMESTAMP=32'd%d" % time.time(),
               "-DEFINE", 'BUILD_VERSION="%s"' % ver]
NCVHDL_ARGS = []
NCELAB_ARGS = ["-GPG", "BUILD_TIMESTAMP=>%d" % time.time(),
               "-GPG", 'BUILD_VERSION=>"%s"' % ver]
NCSIM_ARGS = []

def available():
    "Check if simulation environment is available"

    return (spawn.find_executable("ncvlog") and
            spawn.find_executable("ncvhdl") and
            spawn.find_executable("ncelab") and
            spawn.find_executable("ncsim"))

def make_libraries(*libs):
    f = open("cds.lib", "w")
    print("include $CDS_INST_DIR/tools/inca/files/cds.lib", file=f)

    libs += ("work",)
    for l in libs:
        if not os.path.exists(l):
            os.mkdir(l)
        print("define %s %s" % (l, l), file=f)

    f = open("hdl.var", "w")
    print("SOFTINCLUDE $CDS_INST_DIR/tools/inca/files/hdl.var", file=f)
    print("DEFINE WORK work", file=f)

def compile_verilog(sources, ncvlog_args=[], work=None, **kws):
    ncvlog_args += NCVLOG_ARGS

    work_str = ""
    work_args = []
    if work is not None:
        work_args = ["-WORK", work]
        work_str = " for " + work

    if not sources: return

    try:
        print(cl.cyan("Running ncvlog%s on:" % work_str))
        for s in sources:
            print(cl.cyan("    " + os.path.relpath(s, build.orig_dir)))

        sources = [build.orig_path(s) for s in sources]

        with open(os.devnull, "w") as log_file:
            sp.check_call(["ncvlog"] + ncvlog_args + work_args +  sources,
                          stdout=log_file,
                          stderr=log_file)
    except OSError as e:
        e.filename = "ncvlog"
        raise
    except sp.CalledProcessError:
        sys.stdout.write(open("ncvlog.log").read())
        print(cl.redb("ERROR: ncvlog failed!"))
        raise

def compile_vhdl(sources, ncvhdl_args=[], work=None, **kws):
    ncvhdl_args += NCVHDL_ARGS
    if not sources: return

    work_str = ""
    work_args = []
    if work is not None:
        work_args = ["-WORK", work]
        work_str = " for " + work

    try:
        print(cl.cyan("Running ncvhdl%s on:" % work_str))
        for s in sources:
            print(cl.cyan("    " + os.path.relpath(s, build.orig_dir)))

        sources = [build.orig_path(s) for s in sources]

        with open(os.devnull, "w") as log_file:
            sp.check_call(["ncvhdl"] + ncvhdl_args + work_args + sources,
                          stdout=log_file,
                          stderr=log_file)
    except OSError as e:
        e.filename = "ncvhdl"
        raise
    except sp.CalledProcessError:
        sys.stdout.write(open("ncvhdl.log").read())
        print(cl.redb("ERROR: ncvhdl failed!"))
        raise

def elaborate(entity, ncelab_args=[], **kws):
    ncelab_args += NCELAB_ARGS

    try:
        print(cl.cyan("Running ncelab on: '%s'" % entity))

        with open(os.devnull, "w") as log_file:
            sp.check_call(["ncelab"] + ncelab_args + [entity],
                          stdout=log_file,
                          stderr=log_file)
    except OSError as e:
        e.filename = "ncvlog"
        raise
    except sp.CalledProcessError:
        sys.stdout.write(open("ncelab.log").read())
        print(cl.redb("ERROR: ncelab failed!"))
        raise


class Simulate(build.HDLSimulateBase):
    simulator_name = "ncsim"

    init_tcl = ["set severity_pack_asert_off {warning note}",
                "set pack_assert_off {std_logic_arith numeric_std}",
                "run"]
    listening_re = re.compile(r"AFU Server is waiting for " +
                              r"connection on ([a-zA-Z0-9-\.]+):(\d+)")
    job_re = re.compile(r"Job <(\d+)> is submitted to queue")

    def __init__(self, *args, **kwargs):
        self.ncsim_args = kwargs.pop("ncsim_args", [])

        self.probe = kwargs.pop("probe", None)
        if self.probe is None:
            self.probe = "probes/all.tcl"

        if not os.path.exists(self.probe):
            self.probe = build.orig_path(self.probe)

        open(self.probe)

        super(Simulate, self).__init__(*args, **kwargs)

    def command_line(self):
        return ["ncsim"] + self.ncsim_args + ["-INPUT", self.probe, self.entity]

    def init_simulator(self):
        os.write(self.master, "\n".join(self.init_tcl) + "\n")

    def exit_simulator(self):
        for i in range(10):
            os.kill(-os.getpgid(self.p.pid), signal.SIGINT)
            time.sleep(0.05)

        os.write(self.master, "exit\n")

    def read_loop(self, mf, logf):
        line = mf.readline()
        logf.write(line)
        logf.flush()

        if line.startswith("ncsim> "):
            ncsimtxt, line = line.split(" ", 1)

        if self.socket_host is None:
            m = self.listening_re.match(line)
            if m:
                self.socket_host, self.socket_port = m.groups()
                self.socket_ready.set()
                if not self.quiet:
                    print(cl.green(line.strip()))
                return

            m = self.job_re.match(line)
            if m:
                print(cl.cyan("BSUB Job Queued: %d" % int(m.group(1))))
                return

            if line.startswith("<<Starting on"):
                print(cl.cyan("BSUB Job Started."))
                return
        elif not self.stopping and "Socket error" not in line:
            if not self.quiet:
                print(cl.green(line.strip()))
