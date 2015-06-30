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
##     Generic code to build and run simulations
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

ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))

POWER8 = os.path.join(ROOT, "ibm", "systemsim", "run", "pegasus", "power8")

orig_dir = "."

def options(parser):
    parser.add_option("-b", "--bsub", action="store_true", dest="use_bsub",
                      help="run ncsim using bsub")
    parser.add_option("-o", "--outdir", default="build",
                      help="output directory")
    parser.add_option("-p", "--probe", metavar="TCL_SCRIPT",
                      help="probe file to use")
    parser.add_option("-v", "--verbose", action="store_false",
                      default=True, dest="quiet",
                      help="print ncsim output inline")
    parser.add_option("-R", "--rebuild", action="store_true",
                      help="clean before rebuilding")
    parser.add_option("-V", "--valgrind", action="store_true",
                      help="run capi sim with valgrind")

def chdir(outdir, **kws):
    global orig_dir
    orig_dir = os.getcwd()
    if not os.path.exists(outdir):
        os.makedirs(outdir)
    os.chdir(outdir)

def orig_path(x):
    op = os.path.relpath(os.path.join(orig_dir, x))
    if os.path.join(*([".."]*4)) in op:
        return os.path.abspath(op)
    return op

def run_make(directory, rebuild=False,
             log_file_name="make.log", **kws):
    directory = orig_path(directory)

    try:
        print(cl.cyan("Running make in '%s'" % directory))
        with open(log_file_name, "w") as log_file:
            def call_make(args=[]):
                sp.check_call(["make", "-C", directory] + args,
                              stdout=log_file, stderr=log_file)
            if rebuild:
                call_make(["clean"])
            call_make()
    except sp.CalledProcessError:
        sys.stdout.write(open(log_file_name).read())
        print(cl.redb("ERROR: make failed for '%s'!" % directory))
        raise

def run_waf(directory, rebuild=False,
            log_file_name="waf.log", **kws):
    directory = orig_path(directory)

    try:
        print(cl.cyan("Running waf in '%s'" % directory))
        with open(log_file_name, "w") as log_file:
            def call_waf(args=[]):
                sp.check_call(["./waf"] + args, cwd=directory,
                              stdout=log_file, stderr=log_file)
            if rebuild:
                 call_waf(["clean"])
            call_waf()
    except sp.CalledProcessError:
        sys.stdout.write(open(log_file_name).read())
        print(cl.redb("ERROR: waf failed for '%s'!" % directory))
        raise

class HDLSimulateBase(threading.Thread):
    simulator_name = "???"

    def __init__(self, entity, bsub=[], **kws):
        super(HDLSimulateBase, self).__init__()

        self.entity = entity
        if kws.get("use_bsub", False):
            self.bsub = bsub
        else:
            self.bsub = []
        self.quiet = kws.get("quiet", False)

        self.socket_ready = threading.Event()
        self.socket_host = None
        self.socket_port = None

        self.stopping = False
        self.p = None

    def start(self):
        if not self.quiet:
            print(cl.cyan("Starting %s for '%s' (messages in green)" %
                          (self.simulator_name, self.entity)))
        else:
            print(cl.cyan("Starting %s for '%s'" %
                          (self.simulator_name, self.entity)))
        super(HDLSimulateBase, self).start()

    def run(self):
        master, slave = pty.openpty()
        self.master, self.slave = master, slave

        self.p = sp.Popen(self.bsub + self.command_line(),
                          stdin=slave, stdout=slave, stderr=slave,
                          preexec_fn=os.setsid)
        mf = os.fdopen(master)

        self.init_simulator()

        try:
            with open("%s.full.log" % self.simulator_name, "w") as logf:
                while True:
                    self.read_loop(mf, logf)
        except IOError:
            pass

    def stop(self):
        if not self.is_alive() or not self.p:
            return

        self.stopping=True

        print(cl.cyan("Stopping %s" % self.simulator_name))
        self.exit_simulator()

        self.p.wait()
        os.close(self.slave)
        self.join(5)

    def wait_for_socket(self, timeout=None):
        self.socket_ready.wait(timeout)
        return self.socket_ready.isSet()

    def __enter__(self):
        self.start()

    def __exit__(self, type, value, traceback):
        self.stop()


class SimException(Exception):
    pass
SystemSimException = SimException


class SimRunner(threading.Thread):
    def __init__(self, prog, hdl_sim, args=[],
                 **kwopts):
        super(SimRunner, self).__init__()

        self.prog = prog
        self.hdl_sim = hdl_sim
        self.args = [self._check_file_arg(a) for a in args]
        self.started = threading.Event()

        self.valgrind = []
        if kwopts.get("valgrind", False):
            self.valgrind = ["valgrind", "--leak-check=yes", "--error-exitcode=77"]

    def _check_file_arg(self, a):
        if a.startswith("-"): return a

        oa = orig_path(a)

        if os.path.exists(oa) or oa.endswith(".dat") or "/" in a:
            return oa

        return a

    def _wait_for_hdl_sim(self):
        if not self.hdl_sim.wait_for_socket(300):
            raise SimException("Timed out waiting for HDL simulator to start.")

    def _read_loop(self, mf, logf):
        line = mf.readline()
        logf.write(line)
        logf.flush()
        print(line.strip("\n\r"))

    def run(self):
        try:
            master, slave = pty.openpty()
            self.master, self.slave = master, slave

            cmd = self.valgrind + [self.prog] + self.args
            print(cl.cyan("Command: " + " ".join(cmd)))
            self.p = sp.Popen(cmd, stdin=slave, stdout=slave, stderr=slave)

            mf = os.fdopen(master)
            with open(self.log_name, "w") as logf:
                self.started.set()
                while True:
                    self._read_loop(mf, logf)


        except IOError:
            pass

    def wait(self):
        self.started.wait(2)
        if self.started.isSet():
            ret = self.p.wait()
            os.close(self.slave)
        else:
            ret = -1
        self.join(5)
        return ret

class SystemSimRunner(SimRunner):
    log_name = "systemsim.log"

    def __init__(self, hdl_sim, tcl_file, args=["-n", "-f"],
                 **kwopts):
        super(SystemSimRunner, self).__init__(POWER8, hdl_sim, args, **kwopts)

        self.tcl_file = orig_path(tcl_file)
        self.args.append(self.tcl_file)

    def start(self):
        self._wait_for_hdl_sim()

        os.environ["AFU_SERVER_HOST"] = self.hdl_sim.socket_host
        os.environ["AFU_SERVER_PORT"] = self.hdl_sim.socket_port

        print(cl.cyan("Running power8 systemsim with '%s'" %
                      self.tcl_file))

        super(SystemSimRunner, self).start()

class CapiRunner(SimRunner):
    def __init__(self, *args, **kws):
        super(CapiRunner, self).__init__(*args, **kws)
        self.log_name = os.path.basename(self.prog) + ".log"

    def start(self):
        self._wait_for_hdl_sim()

        with open("shim_host.dat", "w") as w:
            w.write("afu0.0d,%s:%d\n" % (self.hdl_sim.socket_host,
                                         int(self.hdl_sim.socket_port)))

        print(cl.cyan("Running %s" % os.path.basename(self.prog)))

        super(CapiRunner, self).start()

def load_waf_cache():
    try:
        ret = {}
        re_imp = re.compile('^(#)*?([^#=]*?)\ =\ (.*?)$',re.M)
        with open("build/c4che/_cache.py") as f:
            for m in re_imp.finditer(f.read()):
                ret[m.group(2)]=eval(m.group(3))
        return ret
    except IOError:
        print(cl.red("Project not configured, please run './waf configure'"))
        sys.exit(-1)

def append_environ(name, value):
    if name in os.environ:
        os.environ[name] += os.pathsep + value
    else:
        os.environ[name] = value

def gen_pslse_params(**kws):
    with open("pslse.parms", "w") as f:
        for k,v in kws.items():
            print("%s:%s" % (k,v), file=f)

import hdl_cadence_ies

if hdl_cadence_ies.available():
    hdl = hdl_cadence_ies
else:
    print(cl.red("Could not find any HDL simulation tools."))
    sys.exit(-1)
