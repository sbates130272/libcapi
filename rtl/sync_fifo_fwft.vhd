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
--                 Synchronous First-Word-Fall-Through FIFO
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sync_fifo_fwft is
    generic (
        WRITE_SLACK :     positive := 1;
        DATA_BITS   :     natural  := 8;
        ADDR_BITS   :     natural  := 8
        );
    port (
        clk   : in  std_logic;
        rst   : in  std_logic := '0';
        -- write side
        write       : in  std_logic;
        reserve     : in  std_logic := '0';
        write_data  : in  std_logic_vector(DATA_BITS-1 downto 0);
        full        : out std_logic := '0';
        res_full    : out std_logic := '0';
        -- read side
        read        : in  std_logic;
        read_valid  : out std_logic;
        read_data   : out std_logic_vector(DATA_BITS-1 downto 0);
        empty       : out std_logic
        );
end sync_fifo_fwft;

architecture main of sync_fifo_fwft is
    signal waddr : unsigned(ADDR_BITS-1 downto 0) := (others=>'0');
    signal raddr : unsigned(ADDR_BITS-1 downto 0) := (others=>'0');
    signal vaddr : unsigned(ADDR_BITS-1 downto 0) := (others=>'0');

    signal read_fwft      : std_logic := '0';
    signal read_valid_int : std_logic := '0';

    signal full_int : std_logic := '0';
    signal empty_int : std_logic := '1';

    type MEM_TYPE is array(0 to 2**ADDR_BITS-1) of std_logic_vector(DATA_BITS-1 downto 0);
    signal mem : MEM_TYPE;
begin
    full   <= full_int;
    empty  <= empty_int;

    MEM_P : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                read_data <= (others=>'0');
            else
                if read_fwft = '1' and empty_int = '0' then
                    read_data <= mem(to_integer(raddr(ADDR_BITS-1 downto 0)));
                end if;

                if write = '1' then
                    mem(to_integer(waddr(ADDR_BITS-1 downto 0))) <= write_data;
                end if;
            end if;
        end if;
    end process MEM_P;

    ADDR: process (clk) is
    begin
        if rising_edge(clk) then
            if rst = '1' then
                waddr     <= (others=>'0');
                raddr     <= (others=>'0');
                vaddr     <= (others=>'0');
                empty_int <= '1';
                full_int  <= '1';
                res_full  <= '1';
            else
                if write = '1' then
                    waddr <= waddr + 1;
                    empty_int <= '0';
                end if;

                if reserve = '1' then
                    vaddr <= vaddr + 1;
                end if;

                if read_fwft = '1' and empty_int = '0' then
                    raddr <= raddr + 1;

                    if write = '0' and raddr + 1 = waddr then
                        empty_int <= '1';
                    end if;
                end if;

                if raddr - waddr - 1 <= WRITE_SLACK then
                    full_int <= '1';
                else
                    full_int <= '0';
                end if;

                if raddr - vaddr - 1 <= WRITE_SLACK then
                    res_full <= '1';
                else
                    res_full <= '0';
                end if;

            end if;
        end if;
    end process ADDR;

    read_valid <= read_valid_int;
    read_fwft  <= not read_valid_int or read;
    FWFT_P : process(clk, rst)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                read_valid_int <= '0';
            else
                if read_fwft = '1' and empty_int = '0' then
                    read_valid_int <= '1';
                elsif read = '1' then
                    read_valid_int <= '0';
                end if;
            end if;
        end if;
    end process FWFT_P;

end architecture main;
