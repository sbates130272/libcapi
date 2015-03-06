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
--                 This block implements the MMIO registers
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library capi;
use capi.psl.all;
use capi.misc.all;

entity mmio is

    port (
        ha_pclock    : in std_logic;
        reset        : in std_logic;

        ha_mmval     : in  std_logic;
        ha_mmcfg     : in  std_logic;
        ha_mmrnw     : in  std_logic;
        ha_mmdw      : in  std_logic;
        ha_mmad      : in  unsigned(0 to 23);
        ha_mmadpar   : in  std_logic;
        ha_mmdata    : in  std_logic_vector(0 to 63);
        ha_mmdatapar : in  std_logic;
        ah_mmack     : out std_logic;
        ah_mmdata    : out std_logic_vector(0 to 63);
        ah_mmdatapar : out std_logic;

        reg_addr     : out unsigned(0 to 23);
        reg_dw       : out std_logic;
        reg_write    : out std_logic;
        reg_wdata    : out std_logic_vector(0 to 63);
        reg_read     : out std_logic;
        reg_rdata    : in  std_logic_vector(0 to 63);
        reg_read_ack : in  std_logic
        );
end entity;

architecture main of mmio is
    signal ha_mmval_d : std_logic;
    signal ha_mmad_d  : unsigned(0 to 23);

    signal mmdata : std_logic_vector(0 to 63);
    signal mmack  : std_logic;

    signal cfg_read    : std_logic;
    signal cfg_read_d  : std_logic;
    signal cfg_write   : std_logic;
    signal mmio_read   : std_logic;
    signal mmio_write  : std_logic;
    signal mmio_dw     : std_logic;
    signal mmio_dw_d   : std_logic;

    signal cfg_rdata  : std_logic_vector(0 to 63);
    signal mmio_rdata : std_logic_vector(0 to 63);
begin
    reg_write <= mmio_write;
    reg_read  <= mmio_read;
    reg_dw    <= mmio_dw;
    reg_addr  <= ha_mmad_d;

    INP: process (ha_pclock) is
    begin
        if rising_edge(ha_pclock) then
            ha_mmval_d <= ha_mmval;
            ha_mmad_d  <= ha_mmad;
            reg_wdata  <= ha_mmdata;

            if ha_mmval = '1' then
                cfg_read   <= ha_mmval and ha_mmcfg and ha_mmrnw;
                cfg_write  <= ha_mmval and ha_mmcfg and not ha_mmrnw;
                mmio_read  <= ha_mmval and not ha_mmcfg and ha_mmrnw;
                mmio_write <= ha_mmval and not ha_mmcfg and not ha_mmrnw;
                mmio_dw    <= ha_mmdw;
            else
                cfg_read  <= '0';
                cfg_write  <= '0';
                mmio_read  <= '0';
                mmio_write <= '0';
            end if;
        end if;
    end process;

    CFG_READ_DATA: process (ha_pclock) is
    begin
        if rising_edge(ha_pclock) then
            if ha_mmval_d = '1' then
                -- AFU descriptor
                -- Offset 0x00(0), bit 31 -> AFU supports only 1 process at a time
                -- Offset 0x00(0), bit 59 -> AFU supports dedicated process
                -- Offset 0x30(6), bit 07 -> AFU Problem State Area Required
                case to_integer(ha_mmad_d(0 to 22)) is
                    when 0      => cfg_rdata <= (31=>'1', 59=>'1', others=>'0');
                    when 6      => cfg_rdata <= (7=>'1', others=>'0');
                    when others => cfg_rdata <= (others=>'0');
                end case;
            end if;
        end if;
    end process;

    OUTPUT : process (ha_pclock) is
    begin
        if rising_edge(ha_pclock) then
            ah_mmdata    <= mmdata;
            ah_mmdatapar <= calc_parity(mmdata);
            ah_mmack     <= mmack;

            cfg_read_d  <= cfg_read;

            mmack <= '0';
            mmdata <= (others=>'0');

            if cfg_read_d = '1' then
                if mmio_dw = '1' then
                    mmdata <= cfg_rdata;
                elsif ha_mmad_d(23) = '1' then
                    mmdata <= cfg_rdata(0 to 31) & cfg_rdata(0 to 31);
                else
                    mmdata <= cfg_rdata(32 to 63) & cfg_rdata(32 to 63);
                end if;

                mmack <= '1';

            elsif reg_read_ack = '1' then
                if mmio_dw = '1' then
                    mmdata <= reg_rdata;
                elsif ha_mmad_d(23) = '1' then
                    mmdata <= reg_rdata(0 to 31) & reg_rdata(0 to 31);
                else
                    mmdata <= reg_rdata(32 to 63) & reg_rdata(32 to 63);
                end if;

                mmack <= '1';

            elsif cfg_write = '1' then
                mmack <= '1';
            elsif mmio_write = '1' then
                mmack <= '1';
            end if;
        end if;
    end process;


end architecture main;

