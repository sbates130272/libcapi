########################################################################
##
## Copyright 2014 PMC-Sierra, Inc.
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
##   Date: Oct 23, 2014
##
##   Description:
##     Common code for printing to a TTY in colour.
##
########################################################################


import curses

try:
    curses.setupterm()
    bold = curses.tigetstr("bold") or ""
    setf = curses.tigetstr("setf")
    setaf = curses.tigetstr("setaf")
    rst = curses.tigetstr("sgr0") or ""
except curses.error:
    bold = ""
    setf = ""
    setaf = ""
    rst = ""

colours = {}
colours["green"] = ""
colours["magenta"] = ""
colours["yellow"] = ""
colours["cyan"] = ""
colours["red"] = ""
colours["blue"] = ""

if setaf:
    colours["green"] = curses.tparm(setaf, curses.COLOR_GREEN) or ""
    colours["magenta"] = curses.tparm(setaf, curses.COLOR_MAGENTA) or ""
    colours["yellow"] = curses.tparm(setaf, curses.COLOR_YELLOW) or ""
    colours["cyan"] = curses.tparm(setaf, curses.COLOR_CYAN) or ""
    colours["red"] = curses.tparm(setaf,  curses.COLOR_RED) or ""
    colours["blue"] = curses.tparm(setaf, curses.COLOR_BLUE) or ""
elif setf:
    colours["green"] = curses.tparm(setf, curses.COLOR_GREEN) or ""
    colours["magenta"] = curses.tparm(setf, curses.COLOR_MAGENTA) or ""
    colours["yellow"] = curses.tparm(setf, curses.COLOR_YELLOW) or ""
    colours["cyan"] = curses.tparm(setf, curses.COLOR_CYAN) or ""
    colours["red"] = curses.tparm(setf,  curses.COLOR_RED) or ""
    colours["blue"] = curses.tparm(setf, curses.COLOR_BLUE) or ""

def colourf(c):
    def func(x):
        return c + x + rst
    return func

def colourb(c):
    def func(x):
        return c + bold + x + rst
    return func

for name, c in colours.iteritems():
    globals()[name] = colourf(c)
    globals()[name + "b"] = colourb(c)


def boldface(x):
    return bold + x + rst

if __name__ == "__main__":
    colour = (magentab("C") +
              blueb("O") +
              greenb("L") +
              cyanb("O") +
              yellowb("U") +
              redb("R"))
    print colour
