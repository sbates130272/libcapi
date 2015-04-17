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
##     Build Script
##
########################################################################

from waflib import Configure, Options, Logs, Utils
Configure.autoconfig = True

import os

def options(opt):
    opt.load("compiler_c gnu_dirs")

    if not hasattr(opt, 'library_group'):
        opt.library_group =  opt.add_option_group("Library options")

    gr = opt.library_group
    gr.add_option("--libcxl-dir", action="store",
                  help="specify the path to find libcxl.h")


def configure(conf):
    conf.load("compiler_c gnu_dirs")

    conf.env.append_unique("DEFINES", ["_GNU_SOURCE"])
    conf.env.append_unique("CFLAGS", ["-std=gnu99", "-O2", "-Wall",
                                      "-Werror", "-g"])

    conf.check_cc(fragment="int main() { return 0; }\n",
                  msg="Checking for working compiler")
    conf.check_cc(lib='pthread')
    conf.check_cc(lib='rt')

    if not conf.env.LIBCXL_DIR:
        LIBCXL_DIR = Options.options.libcxl_dir or os.getenv("LIBCXL_DIR", "")
        if LIBCXL_DIR:
            conf.env.LIBCXL_DIR = conf.path.find_node(LIBCXL_DIR).abspath()


    def p(msg=""):
        Logs.pprint('NORMAL', msg)

    if conf.env.LIBCXL_DIR:
        conf.env.append_unique("INCLUDES", conf.env.LIBCXL_DIR)
        conf.env.append_unique("INCLUDES",
                               os.path.join(conf.env.LIBCXL_DIR, 'include'))
    else:
        raise conf.errors.ConfigurationError(
            "LIBCXL_DIR is not set, please use the --libcxl-dir option or "
            "set LIBCXL_DIR in the environment")

    try:
        conf.start_msg("Checking for misc/cxl.h")
        devnull = open(os.devnull, "w")
        proc = Utils.subprocess.Popen(["make", "-C", conf.env.LIBCXL_DIR,
                                       "include/misc/cxl.h"],
                                      stdout=devnull, stderr=devnull)
        proc.wait()
        conf.end_msg("yes")
    except Exception:
        conf.end_msg("no", 'YELLOW')
        conf.fatal("Failed running make include/misc/cxl.h")


    try:
        conf.check(header_name="libcxl.h")
    except conf.errors.ConfigurationError:
        p()
        p("Could not find libcxl.h, please obtain a copy of it from:")
        p("   https://github.com/kirkmorrow/pslse")
        p("and specify it as the --libcxl-dir option")
        p()
        raise


def build(bld):
    bld.stlib(source=bld.path.ant_glob("src/*.c"),
              target="capi",
              includes=["inc/capi", "inc"],
              install_path="${PREFIX}/lib",
              use="PTHREAD RT")

    bld.install_files("${PREFIX}/include/libcapi",
                      bld.path.ant_glob("inc/libcapi/*.h"))
