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
--                 PSL Debug Snooper
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.psl.all;
use work.misc.all;

entity snooper is

    port (
        ha_pclock  : in std_logic;
        reset      : in std_logic := '0';

        -- Command Interface
        ah_cvalid  : in std_logic;
        ah_ctag    : in std_logic_vector(0 to 7);
        ah_com     : in std_logic_vector(0 to 12);
        ah_cea     : in unsigned(0 to 63);
        ah_csize   : in unsigned(0 to 11);

        -- Response Interface
        ha_rvalid      : in std_logic;
        ha_rtag        : in std_logic_vector(0 to 7);
        ha_response    : in std_logic_vector(0 to 7);
        ha_rcredits    : in signed(0 to 8);
        ha_rcachestate : in std_logic_vector(0 to 1);
        ha_rcachepos   : in std_logic_vector(0 to 12);

        -- Buffer Interface
        ha_bwvalid  : in  std_logic;
        ha_bwdata   : in  std_logic_vector(0 to 511);

        -- Register Interface
        reg_en       : in  std_logic;
        reg_addr     : in  unsigned(0 to 5);
        reg_dw       : in  std_logic;
        reg_write    : in  std_logic;
        reg_wdata    : in  std_logic_vector(0 to 63);
        reg_read     : in  std_logic;
        reg_rdata    : out std_logic_vector(0 to 63);
        reg_read_ack : out std_logic
        );

end entity snooper;

architecture main of snooper is

    signal write      : std_logic;
    signal full       : std_logic;
    signal write_data : std_logic_vector(0 to
                                         ah_ctag'length +
                                         ah_com'length +
                                         ah_csize'length +
                                         ha_rtag'length +
                                         ha_response'length + 2 + 12 -1);

    signal xor_sum_i : std_logic_vector(0 to 63) := (others=>'0');


    signal read       : std_logic;
    signal read_data  : std_logic_vector(0 to 63) := (others=>'0');
    signal xor_sum    : std_logic_vector(0 to 63);
    signal tag_alert  : std_logic_vector(0 to 63);
    signal tag_stats0 : std_logic_vector(0 to 63);
    signal tag_stats1 : std_logic_vector(0 to 63);
    signal tag_read   : std_logic;
    signal tag_rdata  : std_logic_vector(0 to 63) := (others=>'0');

begin
    xor_sum   <= endian_swap(xor_sum_i);

    REG_INPUT: process (ha_pclock) is
    begin
        if rising_edge(ha_pclock) then
            write <= '0';
            if ah_cvalid = '1' or ha_rvalid = '1' then
                write      <= not full;
                write_data <= ha_rtag & ha_response &
                              std_logic_vector(ah_cea(45 to 56)) &
                              ah_ctag & ah_com &
                              std_logic_vector(ah_csize) & ha_rvalid & ah_cvalid;
            end if;
        end if;
    end process REG_INPUT;

    XOR_RD_DATA: process (ha_pclock) is
        variable x : std_logic_vector(0 to 63);
    begin
        if rising_edge(ha_pclock) then
            if reset = '1' then
                xor_sum_i <= (others=>'0');
            elsif ha_bwvalid = '1' then
                x := xor_sum_i;
                for i in 0 to ha_bwdata'length / 64-1 loop
                    x := x xor ha_bwdata(i*64 to (i+1)*64-1);
                end loop;
                xor_sum_i <= x;
            end if;
        end if;
    end process XOR_RD_DATA;

    GEN_TAG_ANAL : if PSL_TAG_ANAL_EN generate
    tag_anal_i: entity work.tag_anal
        port map (
            clock      => ha_pclock,
            reset      => reset,
            ah_cvalid  => ah_cvalid,
            ah_ctag    => ah_ctag,
            ha_rvalid  => ha_rvalid,
            ha_rtag    => ha_rtag,
            tag_alert  => tag_alert,
            tag_stats0 => tag_stats0,
            tag_stats1 => tag_stats1,
            tag_read   => tag_read,
            tag_rdata  => tag_rdata
            );
    end generate GEN_TAG_ANAL;

    NOT_GEN_TAG_ANAL : if not PSL_TAG_ANAL_EN generate
        tag_alert  <= (others=>'0');
        tag_stats0 <= (others=>'0');
        tag_stats1 <= (others=>'0');
        tag_rdata  <= (others=>'0');
    end generate NOT_GEN_TAG_ANAL;

    cfifo: entity work.sync_fifo_fwft
        generic map (
            WRITE_SLACK => 4,
            DATA_BITS   => write_data'length,
            ADDR_BITS   => 11)
        port map (
            clk        => ha_pclock,
            rst        => '0',
            write      => write,
            full       => full,
            write_data => write_data,
            read       => read,
            read_valid => read_data(0),
            read_data  => read_data(64-write_data'length to 63));



    REG_READ_P: process (ha_pclock) is
    begin
        if rising_edge(ha_pclock) then
            reg_read_ack <= '0';
            reg_rdata    <= (others=>'0');
            read         <= '0';
            tag_read     <= '0';

            if reg_en = '1' then
                reg_read_ack <= reg_read;

                case to_integer(reg_addr(0 to 4)) is
                    when 0      => reg_rdata <= read_data;
                                   read      <= '1';
                    when 1      => reg_rdata <= xor_sum;
                    when 2      => reg_rdata <= tag_alert;
                    when 3      => reg_rdata <= tag_stats0;
                    when 4      => reg_rdata <= tag_stats1;
                    when 5      => reg_rdata <= tag_rdata;
                                   tag_read  <= '1';
                    when others => reg_rdata <= (others=>'0');
                end case;
            end if;
        end if;
    end process REG_READ_P;

end architecture main;
