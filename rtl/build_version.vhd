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
--                 Build Version Register Block
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.misc.all;

entity build_version is
    generic (
        BUILD_TIMESTAMP : integer := -1;
        BUILD_VERSION   : string := string'("unset                   "));

    port (
        clk          : in  std_logic;
        reg_en       : in  std_logic;
        reg_addr     : in  unsigned(0 to 5);
        reg_dw       : in  std_logic;
        reg_write    : in  std_logic;
        reg_wdata    : in  std_logic_vector(0 to 63);
        reg_read     : in  std_logic;
        reg_rdata    : out std_logic_vector(0 to 63);
        reg_read_ack : out std_logic
        );
end entity build_version;

architecture main of build_version is
    constant BUILD_VERSION_PAD : string(1 to 24) := resize(BUILD_VERSION, 24);
begin

    process (clk) is
    begin
        if rising_edge(clk) then
            reg_read_ack <= '0';
            reg_rdata <= (others=>'0');

            if reg_en = '1' then
                reg_read_ack <= reg_read;

                case to_integer(reg_addr(0 to 4)) is
                    when 0      => reg_rdata <= endian_swap(to_slv(BUILD_VERSION_PAD(1 to 8)));
                    when 1      => reg_rdata <= endian_swap(to_slv(BUILD_VERSION_PAD(9 to 16)));
                    when 2      => reg_rdata <= endian_swap(to_slv(BUILD_VERSION_PAD(17 to 24)));
                    when 3      => reg_rdata <= std_logic_vector(to_signed(BUILD_TIMESTAMP, 64));
                    when others => reg_rdata <= (others=>'0');
                end case;
            end if;
        end if;
    end process;

end architecture main;
