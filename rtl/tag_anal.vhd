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
-- Engineer:       Stephen Bates
--
-- Description:
--                 CAPI Tag Analysis Block
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.psl.all;
use work.misc.all;
use work.std_logic_1164_additions.all;

entity tag_anal is

    port (
        clock      : in std_logic;
        reset      : in std_logic := '0';
        ah_cvalid  : in std_logic;
        ah_ctag    : in std_logic_vector(0 to 7);
        ha_rvalid  : in std_logic;
        ha_rtag    : in std_logic_vector(0 to 7);
        tag_alert  : out std_logic_vector(0 to 63);
        tag_stats0 : out std_logic_vector(0 to 63);
        tag_stats1 : out std_logic_vector(0 to 63);
        tag_read   : in  std_logic;
        tag_rdata  : out std_logic_vector(0 to 63)
        );

end entity tag_anal;

architecture main of tag_anal is

    signal tag_track      : std_logic_vector(0 to 2**ah_ctag'high-1);
    signal tag_track_d    : std_logic_vector(0 to 2**ah_ctag'high-1);
    signal tag_track_or   : unsigned(0 to 31);
    signal tag_track_cnt1 : unsigned(0 to 31);
    signal tag_track_cnt2 : unsigned(0 to 31);
    signal tag_alarm      : std_logic_vector(0 to 2**ah_ctag'high-1);
    signal tag_bad        : std_logic_vector(ah_ctag'range);
    signal tag_count      : unsigned(0 to 31);
    signal act_count      : unsigned(0 to 31);
    signal ha_rtag_d      : std_logic_vector(0 to 7);
    signal ha_rvalid_d    : std_logic;
    signal freeze         : std_logic;

    signal tag_min        : unsigned(0 to 31);
    signal tag_max        : unsigned(0 to 31);
    signal tag_rdata_i    : std_logic_vector(0 to 31);
    signal tag_empty      : std_logic;
    signal tag_full       : std_logic;
    signal tag_write      : std_logic;

    constant FREEZE_ULIM : unsigned(0 to 31) := ( 0=>'1' , others=>'0' );

    type tag_counters_t is array (0 to 2**ah_ctag'high-1) of unsigned (0 to 31);
    signal tag_counters   : tag_counters_t;
    signal tag_counters_d : tag_counters_t;

    signal tag_wen    : std_logic_vector(0 to 2**ah_ctag'high-1);
    signal tq_find1   : natural;
    signal tq_find2   : natural;
    signal tq_rvalid  : std_logic;
    signal tq_wen     : std_logic;
    signal tq_wen_d   : std_logic;
    signal tq_wen_dd  : std_logic;
    signal tq_read    : std_logic;
    signal tq_wdata   : std_logic_vector(0 to 31);
    signal tq_wdata_d : std_logic_vector(0 to 31);
    signal tq_rdata   : std_logic_vector(0 to 31);
    signal tq_alarm   : std_logic;
    signal tq_full    : std_logic;
    signal tq_empty   : std_logic;
begin

    tag_alert  <= ( or_reduce(tag_alarm) &
                  std_logic_vector(resize(unsigned(tag_bad), tag_alert'length-1)) );
    tag_stats0 <= std_logic_vector( tag_count) & std_logic_vector( act_count );
    tag_stats1 <= std_logic_vector( tag_max  ) & std_logic_vector( tag_min   );
    tag_rdata  <= (others=>'0') when tag_empty = '1' else
                      std_logic_vector( resize(unsigned(tag_rdata_i), tag_rdata'length) );

    TAG_COUNTERS_GENERATE : for i in 0 to tag_counters'high generate
    begin
        TAG_COUNTERS_PROCESS : process (clock) is
        begin
            if rising_edge(clock) then
                if reset = '1' then
                    tag_counters(i)   <= (others=>'0');
                    tag_counters_d(i) <= (others=>'0');
                    tag_wen(i)        <= '0';
                else
                    tag_counters_d(i) <= tag_counters(i);
                    tag_wen(i)        <= '0';
                    if tag_wen(i) = '1' then
                        tag_counters(i) <= (others=>'0');
                    elsif tag_track(i) = '0' and tag_track_d(i) = '1' then
                        tag_wen(i) <= '1';
                    elsif tag_track(i) = '1' then
                        tag_counters(i) <= tag_counters(i) + to_unsigned(1, tag_counters(i)'length);
                    end if;
                 end if;
             end if;
        end process TAG_COUNTERS_PROCESS;
    end generate TAG_COUNTERS_GENERATE;

    TAG_QUEUE_PROCESS : process (clock) is
    begin
        if rising_edge(clock) then
            if reset = '1' then
                tq_wen     <= '0';
                tq_wen_d   <= '0';
                tq_wen_dd  <= '0';
                tq_wdata   <= (others=>'0');
                tq_wdata_d <= (others=>'0');
                tq_alarm   <= '0';
                tq_read    <= '0';
                tq_find1   <=  0;
                tq_find2   <=  0;
            else
                tq_wen     <= or_reduce(tag_wen);
                tq_wen_d   <= tq_wen;
                tq_wen_dd  <= tq_wen_d;
                tq_wdata_d <= tq_wdata;
                tq_find1   <= find(tag_wen(0 to tag_wen'length/2-1));
                tq_find2   <= find(tag_wen(tag_wen'length/2 to tag_wen'high));
                if ( tq_find2 > 0 ) then
                    tq_wdata <= std_logic_vector(tag_counters_d(tq_find2));
                else
                    tq_wdata <= std_logic_vector(tag_counters_d(tq_find1));
                end if;
                tq_alarm <= tq_wen_d and tq_full;
                tq_read  <= not tq_empty;
            end if;
        end if;
    end process TAG_QUEUE_PROCESS;

    TAG_CALC_PROCESS : process (clock) is
    begin
        if rising_edge(clock) then
            if reset = '1' then
                tag_min <= (others=>'1');
                tag_max <= (others=>'0');
            elsif tq_rvalid = '1' then
                if (unsigned(tq_rdata) < tag_min) then
                    tag_min <= unsigned(tq_rdata);
                end if;
                if (unsigned(tq_rdata) > tag_max) then
                    tag_max <= unsigned(tq_rdata);
                end if;
            end if;
        end if;
    end process TAG_CALC_PROCESS;

    TAG_INPUT_QUEUE: entity work.sync_fifo_fwft
        generic map (
            WRITE_SLACK => 2,
            DATA_BITS   => tag_counters(0)'length,
            ADDR_BITS   => 4)
        port map (
            clk          => clock,
            rst          => reset,
            full         => tq_full,
            empty        => tq_empty,
            write        => tq_wen_dd,
            write_data   => tq_wdata_d,
            read         => tq_read,
            read_valid   => tq_rvalid,
            read_data    => tq_rdata);

    tag_write <= tq_rvalid and not tag_full;

    TAG_OUTPUT_QUEUE: entity work.sync_fifo_fwft
        generic map (
            WRITE_SLACK => 2,
            DATA_BITS   => tag_counters(0)'length,
            ADDR_BITS   => PSL_TAG_DATA_QUEUE_ADDR)
        port map (
            clk          => clock,
            rst          => reset,
            full         => tag_full,
            empty        => tag_empty,
            write        => tag_write,
            write_data   => tq_rdata,
            read         => tag_read,
            read_data    => tag_rdata_i);

    TAG_ANALYSIS_PROCESS: process (clock) is
      variable idx : integer;
    begin
        if rising_edge(clock) then
            if reset = '1' then
                tag_alarm      <= (others=>'0');
                tag_track      <= (others=>'0');
                tag_track_d    <= (others=>'0');
                tag_bad        <= (others=>'0');
                tag_count      <= (others=>'0');
                act_count      <= (others=>'0');
                tag_track_cnt1 <= (others=>'0');
                tag_track_cnt2 <= (others=>'0');
                tag_track_or   <= (others=>'0');
                ha_rtag_d      <= (others=>'0');
                ha_rvalid_d    <= '0';
                freeze         <= '0';
            else
              tag_track_d    <= tag_track;
              ha_rtag_d      <= ha_rtag;
              ha_rvalid_d    <= ha_rvalid;
              tag_track_cnt1 <= to_unsigned(count(tag_track(0 to tag_track'length/2-1)), tag_track_cnt1'length);
              tag_track_cnt2 <= to_unsigned(count(tag_track(tag_track'length/2 to tag_track'high)), tag_track_cnt2'length);
              tag_track_or   <= resize(unsigned( std_logic_vector'( "" & or_reduce(tag_track) ) ),
                                    tag_track_or'length);
              if freeze = '0' then
                  tag_count <= tag_count + tag_track_cnt1 + tag_track_cnt2;
                  act_count <= act_count + tag_track_or;
              end if;
              if tag_count > FREEZE_ULIM or act_count > FREEZE_ULIM then
                  freeze <= '1';
              end if;
              if ah_cvalid = '1' then
                  idx := to_integer(unsigned(ah_ctag));
                  if tag_track(idx) = '1' then
                    tag_alarm(idx) <= '1';
                    tag_bad        <= std_logic_vector(to_unsigned(idx,tag_bad'length));
                  end if;
                  tag_track(idx) <= '1';
              end if;
              if ha_rvalid_d = '1' then
                 idx := to_integer(unsigned(ha_rtag_d));
                 if tag_track(idx) = '0' then
                     tag_alarm(idx) <= '1';
                     tag_bad        <= std_logic_vector(to_unsigned(idx,tag_bad'length));
                 end if;
                 tag_track(idx) <= '0';
                end if;
            end if;
        end if;
    end process TAG_ANALYSIS_PROCESS;


end architecture main;


