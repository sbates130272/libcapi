--------------------------------------------------------------------------------
--
-- Copyright 2015 PMC-Sierra, Inc.
--
-- Licensed under the Apache License, Version 2.0 (the "License"); you
-- may not use this file except in compliance with the License. You may
-- obtain a copy of the License at
-- http://www.apache.org/licenses/LICENSE-2.0 Unless required by
-- applicable law or agreed to in writing, software distributed under the
-- License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
-- CONDITIONS OF ANY KIND, either express or implied. See the License for
-- the specific language governing permissions and limitations under the
-- License.
--
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Company:        PMC-Sierra, Inc.
-- Engineer:       Logan Gunthorpe
--
-- Description:
--                 Package of defines describing the PSL
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


package psl is
    constant PSL_CTRL_CMD_START : std_logic_vector(0 to 7) := x"90";
    constant PSL_CTRL_CMD_RESET : std_logic_vector(0 to 7) := x"80";

    constant PSL_CMD_READ_CL_NA   : std_logic_vector(0 to 12) := "0" & x"A00";
    constant PSL_CMD_READ_CL_S    : std_logic_vector(0 to 12) := "0" & x"A50";
    constant PSL_CMD_READ_CL_M    : std_logic_vector(0 to 12) := "0" & x"A60";
    constant PSL_CMD_READ_CL_LCK  : std_logic_vector(0 to 12) := "0" & x"A6B";
    constant PSL_CMD_READ_CL_RES  : std_logic_vector(0 to 12) := "0" & x"A67";
    constant PSL_CMD_READ_PE      : std_logic_vector(0 to 12) := "0" & x"A52";
    constant PSL_CMD_READ_PNA     : std_logic_vector(0 to 12) := "0" & x"E00";

    constant PSL_CMD_TOUCH_I      : std_logic_vector(0 to 12) := "0" & x"240";
    constant PSL_CMD_TOUCH_S      : std_logic_vector(0 to 12) := "0" & x"250";
    constant PSL_CMD_TOUCH_M      : std_logic_vector(0 to 12) := "0" & x"260";

    constant PSL_CMD_WRITE_MI     : std_logic_vector(0 to 12) := "0" & x"D60";
    constant PSL_CMD_WRITE_MS     : std_logic_vector(0 to 12) := "0" & x"D70";
    constant PSL_CMD_WRITE_UNLOCK : std_logic_vector(0 to 12) := "0" & x"D6B";
    constant PSL_CMD_WRITE_C      : std_logic_vector(0 to 12) := "0" & x"D67";
    constant PSL_CMD_WRITE_NA     : std_logic_vector(0 to 12) := "0" & x"D00";
    constant PSL_CMD_WRITE_INJ    : std_logic_vector(0 to 12) := "0" & x"D10";

    constant PSL_CMD_PUSH_I       : std_logic_vector(0 to 12) := "0" & x"140";
    constant PSL_CMD_PUSH_S       : std_logic_vector(0 to 12) := "0" & x"150";
    constant PSL_CMD_EVICT_I      : std_logic_vector(0 to 12) := "1" & x"140";
    constant PSL_CMD_LOCK         : std_logic_vector(0 to 12) := "0" & x"16B";
    constant PSL_CMD_UNLOCK       : std_logic_vector(0 to 12) := "0" & x"17B";

    constant PSL_CMD_FLUSH        : std_logic_vector(0 to 12) := "0" & x"100";
    constant PSL_CMD_INTREQ       : std_logic_vector(0 to 12) := "0" & x"000";
    constant PSL_CMD_RESTART      : std_logic_vector(0 to 12) := "0" & x"001";


    constant PSL_CABT_STRICT : std_logic_vector(0 to 2) := "000";
    constant PSL_CABT_ABORT  : std_logic_vector(0 to 2) := "001";
    constant PSL_CABT_PAGE   : std_logic_vector(0 to 2) := "010";
    constant PSL_CABT_PREF   : std_logic_vector(0 to 2) := "011";
    constant PSL_CABT_SPEC   : std_logic_vector(0 to 2) := "111";

    constant PSL_RESP_DONE    : std_logic_vector(0 to 7) := x"00";
    constant PSL_RESP_AERROR  : std_logic_vector(0 to 7) := x"01";
    constant PSL_RESP_DERROR  : std_logic_vector(0 to 7) := x"03";
    constant PSL_RESP_NLOCK   : std_logic_vector(0 to 7) := x"04";
    constant PSL_RESP_NRES    : std_logic_vector(0 to 7) := x"05";
    constant PSL_RESP_FLUSHED : std_logic_vector(0 to 7) := x"06";
    constant PSL_RESP_FAULT   : std_logic_vector(0 to 7) := x"07";
    constant PSL_RESP_FAILED  : std_logic_vector(0 to 7) := x"08";
    constant PSL_RESP_PAGED   : std_logic_vector(0 to 7) := x"0A";
    constant PSL_RESP_CONTEXT : std_logic_vector(0 to 7) := x"0B";

    constant PSL_TAG_ANAL_EN         : boolean  := true;
    constant PSL_TAG_DATA_QUEUE_ADDR : positive := 12;

    function calc_parity (x : std_logic_vector)
        return std_logic;
    function calc_parity (x : unsigned)
        return std_logic;

end package psl;

package body psl is

    function calc_parity (
        x : std_logic_vector)
        return std_logic
    is
        variable ret : std_logic := '0';
    begin
        for i in x'range loop
            ret := ret xor x(i);
        end loop;
        return not ret;
    end function;

    function calc_parity (
         x : unsigned)
        return std_logic
    is
    begin
        return calc_parity(std_logic_vector(x));
    end function;

end package body;
