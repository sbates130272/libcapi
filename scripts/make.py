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
##      Waf tool to build a static library with a makefile.
##
########################################################################

import os

from waflib import Context, Utils
from waflib.TaskGen import  feature
from waflib import Task, Errors, Logs
from waflib.Configure import conf
from waflib.Tools.ccroot import stlink_task
def make_clean(self, make_dir):
    if self.cmd != 'clean':
        return
    self.cmd_and_log(self.env.MAKE + ["-C", make_dir, "clean"],
                     quiet=Context.STDOUT if Logs.verbose == 0 else None)

Context.Context.make_clean = make_clean

class make(stlink_task):
    #run_str = '${MAKE} -C ${MAKE_DIR} && cp ${MAKE_DIR}/${TGT[0]} ${TGT[0]}'
    color = 'YELLOW'

    def run(self):
        try:
            self.generator.bld.cmd_and_log(self.env.MAKE + ["-C"] +
                                           self.env.MAKE_DIR,
                                           env=self.make_env,
                                           quiet=Context.STDOUT if Logs.verbose == 0 else None)

        except Errors.WafError as e:
            return e.returncode

        source = os.path.join(self.env.MAKE_DIR[0], str(self.outputs[0]))
        return self.exec_command(["cp", source, self.outputs[0].abspath()])

    def runnable_status(self):
        return Task.RUN_ME

    def keyword(self):
        return "Making"

@feature('make')
def make_feature(self):
    fname = self.env['cstlib_PATTERN']  % self.target
    tgt = self.path.find_or_declare(fname)
    task = self.create_task('make', tgt=tgt)
    task.make_env = None
    make_env = getattr(self, 'make_env', None)
    if make_env is not None:
        task.make_env = dict(os.environ)
        task.make_env.update(make_env)
    task.env.append_unique('MAKE_DIR', self.make_dir)
    self.link_task = task

@conf
def make_stlib(bld, *args, **kws):
    kws['features'] = Utils.to_list(kws.get('features', [])) + ['make']
    bld(*args, **kws)
    bld.make_clean(kws['make_dir'])
