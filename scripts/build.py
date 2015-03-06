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
##     Generic code to build and run simulations using ncsim
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
import version

ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))

POWER8 = os.path.join(ROOT, "ibm", "systemsim", "run", "pegasus", "power8")

ver = version.get_git_version()

NCVLOG_ARGS = ["-DEFINE", "BUILD_TIMESTAMP=32'd%d" % time.time(),
               "-DEFINE", 'BUILD_VERSION="%s"' % ver]
NCVHDL_ARGS = []
NCELAB_ARGS = ["-GPG", "BUILD_TIMESTAMP=>%d" % time.time(),
               "-GPG", 'BUILD_VERSION=>"%s"' % ver]

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

def make_nclibs(*libs):
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

def run_ncvlog(sources, ncvlog_args=[], work=None, **kws):
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
            print(cl.cyan("    " + os.path.relpath(s, orig_dir)))

        sources = [orig_path(s) for s in sources]

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

def run_ncvhdl(sources, ncvhdl_args=[], work=None, **kws):
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
            print(cl.cyan("    " + os.path.relpath(s, orig_dir)))

        sources = [orig_path(s) for s in sources]

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

def run_ncelab(entity, ncelab_args=[], **kws):
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


class NCSimRunner(threading.Thread):
    listening_re = re.compile(r"AFU Server is waiting for " +
                              r"connection on ([a-zA-Z0-9-\.]+):(\d+)")
    job_re = re.compile(r"Job <(\d+)> is submitted to queue")

    init_tcl = ["set severity_pack_asert_off {warning note}",
                "set pack_assert_off {std_logic_arith numeric_std}",
                "run"]

    def __init__(self, entity, ncsim_args=[],
                 bsub=[], **kws):
        super(NCSimRunner, self).__init__()

        self.entity = entity
        if kws.get("use_bsub", True):
            self.bsub = bsub
        else:
            self.bsub = []
        self.ncsim_args = ncsim_args
        self.quiet = kws.get("quiet", False)

        self.socket_ready = threading.Event()
        self.socket_host = None
        self.socket_port = None

        self.stopping = False
        self.p = None

        self.probe = kws.get("probe", None)
        if self.probe is None:
            self.probe = "probes/all.tcl"

        if not os.path.exists(self.probe):
            self.probe = orig_path(self.probe)

        open(self.probe)

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


    def start(self):
        if not self.quiet:
            print(cl.cyan("Starting ncsim for '%s' (messages in green)" %
                          self.entity))
        else:
            print(cl.cyan("Starting ncsim for '%s'" %
                          self.entity))
        super(NCSimRunner, self).start()

    def run(self):
        master, slave = pty.openpty()
        self.master, self.slave = master, slave

        self.ncsim_args += ["-INPUT", self.probe]

        self.p = sp.Popen(self.bsub + ["ncsim"] +
                          self.ncsim_args + [self.entity],
                          stdin=slave, stdout=slave, stderr=slave,
                          preexec_fn=os.setsid)
        mf = os.fdopen(master)
        os.write(self.master, "\n".join(self.init_tcl) + "\n")

        try:
            with open("ncsim.full.log", "w") as logf:
                while True:
                    self.read_loop(mf, logf)
        except IOError:
            pass

    def stop(self):
        if not self.is_alive() or not self.p:
            return

        self.stopping=True

        print(cl.cyan("Stopping NCSIM"))

        for i in range(10):
            os.kill(-os.getpgid(self.p.pid), signal.SIGINT)
            time.sleep(0.05)
        os.write(self.master, "exit\n")
        self.p.wait()
        os.close(self.slave)
        self.join(5)

    def wait_for_socket(self, timeout=None):
        self.socket_ready.wait(timeout)
        return self.socket_ready.isSet()

class SimException(Exception):
    pass
SystemSimException = SimException


class SimRunner(threading.Thread):
    def __init__(self, prog, ncsim, args=[],
                 **kwopts):
        super(SimRunner, self).__init__()

        self.prog = prog
        self.ncsim = ncsim
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

    def _wait_for_ncsim(self):
        if not self.ncsim.wait_for_socket(300):  # SF: Changed from 120 to 300 seconds
            raise SimException("Timed out waiting for NCSIM to Start.")

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

    def __init__(self, ncsim, tcl_file, args=["-n", "-f"],
                 **kwopts):
        super(SystemSimRunner, self).__init__(POWER8, ncsim, args, **kwopts)

        self.tcl_file = orig_path(tcl_file)
        self.args.append(self.tcl_file)

    def start(self):
        self._wait_for_ncsim()

        os.environ["AFU_SERVER_HOST"] = self.ncsim.socket_host
        os.environ["AFU_SERVER_PORT"] = self.ncsim.socket_port

        print(cl.cyan("Running power8 systemsim with '%s'" %
                      self.tcl_file))

        super(SystemSimRunner, self).start()

class CapiRunner(SimRunner):
    def __init__(self, *args, **kws):
        super(CapiRunner, self).__init__(*args, **kws)
        self.log_name = os.path.basename(self.prog) + ".log"

    def start(self):
        self._wait_for_ncsim()

        with open("shim_host.dat", "w") as w:
            w.write("afu0.0d,%s:%d\n" % (self.ncsim.socket_host,
                                         int(self.ncsim.socket_port)))

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
