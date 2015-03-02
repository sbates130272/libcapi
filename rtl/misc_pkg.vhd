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
--                 Package of misc functions
--
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package misc is

    function count(x : std_logic_vector)
        return natural;

    function find(x : std_logic_vector; y : natural := 0)
        return natural;

    function log2_ceil(N: natural)
        return positive;

    function resize(x : std_logic_vector; new_size :natural)
        return std_logic_vector;

    function endian_swap(x : std_logic_vector)
        return std_logic_vector;
    function endian_swap(x : unsigned)
        return unsigned;

    function resize(s : string; len : positive)
        return string;

    function to_slv(s: string)
        return std_logic_vector;

end package misc;

package body misc is

    function count (x : std_logic_vector)
        return natural
    is
        variable ret : natural := 0;
    begin
        for i in x'range loop
            if x(i) = '1' then
                ret := ret+1;
            end if;
        end loop;
        return ret;
    end function;

    function find (x : std_logic_vector;
                   y : natural := 0)
        return natural
    is
        variable ret : natural := 0;
    begin
        for i in x'range loop
            if x(i) = '1' then
                ret := y + i;
            end if;
        end loop;
        return ret;
    end function;

    function log2_ceil(N : natural) return positive is
	begin
		if (N <= 2) then
			return 1;
		else
		  if (N mod 2 = 0) then
		  	return 1 + log2_ceil(N/2);
		  else
		    return 1 + log2_ceil((N+1)/2);
		 end if;
		end if;
	end function log2_ceil;

    function resize(x : std_logic_vector; new_size :natural)
        return std_logic_vector is
    begin
        return std_logic_vector(resize(unsigned(x), new_size));
    end function resize;

    function endian_swap(x : std_logic_vector)
        return std_logic_vector is
        variable ret : std_logic_vector(0 to x'length-1);
        variable xx  : std_logic_vector(0 to x'length-1);
        constant bytes : positive := x'length / 8;
    begin
        xx := x;
        for i in 0 to bytes-1 loop
            ret(i*8 to i*8+7) := xx((bytes-i-1)*8 to (bytes-i-1)*8+7);
        end loop;
        return ret;
    end function endian_swap;

    function endian_swap(x : unsigned)
        return unsigned is
    begin
        return unsigned(endian_swap(std_logic_vector(x)));
    end function endian_swap;

    function resize(s : string; len : positive)
        return string is
        variable ret : string(1 to len) := (others=>NUL);
    begin
        for i in 1 to s'length loop
            if i <= ret'high then
                ret(i) := s(s'low + i - 1);
            end if;
        end loop;
        return ret;
    end function resize;

    function to_slv(s: string)
        return std_logic_vector is
        variable ret : std_logic_vector(0 to 8*s'length-1);
        variable c   : integer;
    begin
        for i in 0 to s'length-1 loop
            c := character'pos(s(s'low + i));
            ret(i*8 to (i+1)*8-1) := std_logic_vector(to_unsigned(c, 8));
        end loop;
        return ret;
    end function to_slv;

end package body;
