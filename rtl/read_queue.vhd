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

entity read_queue is
    generic (
        WRITE_SLACK :     natural  := 6;
        DATA_BITS   :     natural  := 512;
        ADDR_BITS   :     natural  := 6
        );
    port (
        clk   : in  std_logic;
        rst   : in  std_logic := '0';

        reserve       : in  std_logic;
        reserve_addr  : out unsigned(ADDR_BITS-1 downto 0);
        full          : out std_logic;
        empty         : out std_logic;

        write       : in  std_logic;
        write_addr  : in  unsigned(ADDR_BITS-1 downto 0);
        write_data  : in  std_logic_vector(DATA_BITS-1 downto 0);

        complete  : in std_logic;
        comp_addr : in unsigned(ADDR_BITS-1 downto 0);

        read        : in  std_logic;
        read_valid  : out std_logic;
        read_data   : out std_logic_vector(DATA_BITS-1 downto 0)
        );
end read_queue;

architecture main of read_queue is
    signal vaddr : unsigned(ADDR_BITS-1 downto 0) := (others=>'0');
    signal raddr : unsigned(ADDR_BITS-1 downto 0) := (others=>'0');

    signal read_fwft : std_logic;
    signal empty_int : std_logic;
    signal read_valid_int : std_logic := '0';

    type mem_t  is array(0 to 2**ADDR_BITS-1) of std_logic_vector(DATA_BITS-1 downto 0);
    signal mem : mem_t;
    signal written : std_logic_vector(0 to 2**(ADDR_BITS-1)-1) := (others=>'0');

begin
    reserve_addr <= vaddr;

    MEM_P : process(clk)
    begin
        if rising_edge(clk) then
            if write = '1' then
                mem(to_integer(write_addr)) <= write_data;
            end if;

            if read_fwft = '1' and empty_int = '0' then
                read_data <= mem(to_integer(raddr));
            end if;
        end if;
    end process MEM_P;

    WRITTEN_P : process(clk) is
    begin
        if rising_edge(clk) then
            if rst = '1' then
                written <= (others=>'0');
            else
                if complete = '1' then
                    written(to_integer(comp_addr(comp_addr'high downto 1))) <= '1';
                end if;

                if read_fwft = '1' and empty_int = '0' and raddr(0) = '1' then
                    written(to_integer(raddr(raddr'high downto 1))) <= '0';
                end if;
            end if;
        end if;
    end process WRITTEN_P;

    empty_int <= not written(to_integer(raddr(raddr'high downto 1)));

    ADDR: process (clk) is
    begin
        if rising_edge(clk) then
            if rst = '1' then
                raddr     <= (others=>'0');
                vaddr     <= (others=>'0');
                full      <= '0';
            else
                if reserve = '1' then
                    vaddr <= vaddr + 2;
                end if;

                if read_fwft = '1' and empty_int = '0' then
                    raddr <= raddr + 1;
                end if;

                if raddr - vaddr - 1 <= WRITE_SLACK then
                    full <= '1';
                else
                    full <= '0';
                end if;
            end if;
        end if;
    end process ADDR;

    EMPTY_P: process (clk) is
    begin
        if rising_edge(clk) then
            if written = (written'range => '0') then
                empty <= '1';
            else
                empty <= '0';
            end if;
        end if;
    end process EMPTY_P;

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
