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
--                 FIFO-Like primitive that allows the DMA engine to re-order
--                 requests.
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity write_queue is
    generic (
        DATA_BITS   :     natural  := 512;
        ADDR_BITS   :     natural  := 6
        );
    port (
        clk   : in  std_logic;
        rst   : in  std_logic := '0';

        write       : in  std_logic;
        write_data  : in  std_logic_vector(DATA_BITS-1 downto 0);
        write_addr  : out unsigned(ADDR_BITS-1 downto 0);
        full        : out std_logic;

        read        : in  std_logic;
        read_addr   : in  unsigned(ADDR_BITS-1 downto 0);
        read_data   : out std_logic_vector(DATA_BITS-1 downto 0);

        complete  : in std_logic;
        comp_addr : in unsigned(ADDR_BITS-1 downto 0)
        );
end write_queue;

architecture main of write_queue is
    signal waddr : unsigned(ADDR_BITS-1 downto 0) := (others=>'0');

    type mem_t  is array(0 to 2**ADDR_BITS-1) of std_logic_vector(DATA_BITS-1 downto 0);
    signal mem : mem_t;
    signal written : std_logic_vector(0 to 2**(ADDR_BITS-1)-1) := (others=>'0');

    signal full_i : std_logic;

    signal comp_addr_d : unsigned(read_addr'range);
    signal comp_d      : std_logic;

begin
    write_addr <= waddr;
    full <= full_i;

    MEM_P : process(clk)
    begin
        if rising_edge(clk) then
            if write = '1' then
                mem(to_integer(waddr)) <= write_data;
            end if;

            read_data <= mem(to_integer(read_addr));
        end if;
    end process MEM_P;

    WRITTEN_P : process(clk) is
    begin
        if rising_edge(clk) then
            comp_d      <= complete;
            comp_addr_d <= comp_addr;

            if rst = '1' then
                written <= (others=>'0');
            else
                if write = '1' and full_i = '0' and waddr(0) = '1' then
                    written(to_integer(waddr(write_addr'high downto 1))) <= '1';
                end if;

                if comp_d = '1' then
                    written(to_integer(comp_addr_d(comp_addr_d'high downto 1))) <= '0';
                end if;
            end if;
        end if;
    end process WRITTEN_P;

    ADDR: process (clk) is
    begin
        if rising_edge(clk) then
            if rst = '1' then
                waddr <= (others=>'0');
                full_i  <= '0';
            else
                full_i <= written(to_integer(waddr(waddr'high downto 1))) or
                          written(to_integer(waddr(waddr'high downto 1)+1)) or
                          written(to_integer(waddr(waddr'high downto 1)+2));

                if write = '1' and full_i = '0'then
                    waddr <= waddr + 1;
                end if;
            end if;
        end if;
    end process ADDR;

end architecture main;
