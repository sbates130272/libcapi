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
--                 Work Queue Block (see wqueue.md)
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;

use work.psl.all;
use work.misc.all;
use work.std_logic_1164_additions.all;

entity wqueue is

    port (
        ha_pclock  : in std_logic;
        reset      : in std_logic;
        start      : in std_logic;
        timer      : in unsigned(0 to 63) := (others=>'0');

        wed_base_addr : in unsigned(0 to 63);
        wqueue_done   : out std_logic := '0';

        -- Command Interface
        ah_cvalid  : out std_logic;
        ah_ctag    : out std_logic_vector(0 to 7);
        ah_ctagpar : out std_logic;
        ah_com     : out std_logic_vector(0 to 12);
        ah_compar  : out std_logic;
        ah_cabt    : out std_logic_vector(0 to 2) := PSL_CABT_STRICT;
        ah_cea     : out unsigned(0 to 63);
        ah_ceapar  : out std_logic;
        ah_cch     : out std_logic_vector(0 to 15) := (others=>'0');
        ah_csize   : out unsigned(0 to 11);
        ha_croom   : in  unsigned(0 to 7);

        -- Response Interface
        ha_rvalid      : in std_logic;
        ha_rtag        : in std_logic_vector(0 to 7);
        ha_rtagpar     : in std_logic;
        ha_response    : in std_logic_vector(0 to 7);
        ha_rcredits    : in signed(0 to 8);
        ha_rcachestate : in std_logic_vector(0 to 1);
        ha_rcachepos   : in std_logic_vector(0 to 12);

        -- Buffer Interface
        ha_brvalid  : in  std_logic;
        ha_brtag    : in  std_logic_vector(0 to 7);
        ha_brtagpar : in  std_logic;
        ha_brad     : in  unsigned(0 to 5);
        ah_brlat    : out std_logic_vector(0 to 3) := x"1";
        ah_brdata   : out std_logic_vector(0 to 511) := (others=>'0');
        ah_brpar    : out std_logic_vector(0 to 7) := (others=>'0');
        ha_bwvalid  : in  std_logic;
        ha_bwtag    : in  std_logic_vector(0 to 7);
        ha_bwtagpar : in  std_logic;
        ha_bwad     : in  unsigned(0 to 5);
        ha_bwdata   : in  std_logic_vector(0 to 511);
        ha_bwpar    : in  std_logic_vector(0 to 7);

        -- Register Interface
        reg_en       : in  std_logic;
        reg_addr     : in  unsigned(0 to 5);
        reg_dw       : in  std_logic;
        reg_write    : in  std_logic;
        reg_wdata    : in  std_logic_vector(0 to 63);
        reg_read     : in  std_logic;
        reg_rdata    : out std_logic_vector(0 to 63);
        reg_read_ack : out std_logic;

        --Processor Interface
        proc_clear   : out std_logic;
        proc_idata   : out std_logic_vector(0 to 511);
        proc_ivalid  : out std_logic;
        proc_idone   : out std_logic;
        proc_iready  : in  std_logic := '1';
        proc_odata   : in  std_logic_vector(0 to 511) := (others=>'0');
        proc_ovalid  : in  std_logic := '0';
        proc_odirty  : in  std_logic := '1';
        proc_oready  : out std_logic;
        proc_odone   : in  std_logic := '1';
        proc_len     : out unsigned(0 to 31);
        proc_flags   : out std_logic_vector(0 to 7)
        );

end entity;

architecture main of wqueue is
    type state_t is (IDLE,
                     LOAD_QUEUE_ITEM, WAIT_FOR_QUEUE_ITEM,
                     RUN, READ_SRC, WRITE_DST, WRITE_WAIT, FLUSH,
                     RESTART_BUS, RESTART_BUS_FLUSH,
                     SAVE_QUEUE_ITEM, NEXT_ITEM,
                     WAIT_FOR_DONE, DONE);
    signal state : state_t;

    signal ah_cvalid_i : std_logic;
    signal ah_ctag_i : std_logic_vector(ah_ctag'range);

    signal wed_offset    : unsigned(15 downto 0);
    signal wed_addr      : unsigned(63 downto 0);
    signal wed_addr_next : unsigned(63 downto 0);

    signal TAG_QUEUE_ITEM : std_logic_vector(0 to 2) := "001";
    signal TAG_RDATA      : std_logic_vector(0 to 2) := "010";
    signal TAG_WDATA      : std_logic_vector(0 to 2) := "011";

    signal credits    : signed(ha_rcredits'range);
    signal credit_lim : signed(ha_rcredits'range);
    signal has_room   : std_logic;
    signal flushed    : std_logic;

    signal trigger_seen : std_logic := '0';

    signal got_qitem : std_logic;

    signal qitem_flags     : std_logic_vector(0 to 15);
    signal qitem_chunk_len : unsigned(0 to 31);
    signal qitem_src       : unsigned(0 to 63);
    signal qitem_dst       : unsigned(0 to 63);
    alias  qitem_ready     : std_logic is qitem_flags(15);
    alias  qitem_done      : std_logic is qitem_flags(14);
    alias  qitem_dirty     : std_logic is qitem_flags(13);
    alias  qitem_always_wr : std_logic is qitem_flags(12);
    alias  qitem_wr_only   : std_logic is qitem_flags(10);

    signal error_mask : std_logic_vector(0 to 15) := (others=>'0');

    signal src_count : unsigned(0 to 31);
    signal src_addr  : unsigned(0 to 63);

    signal dst_addr  : unsigned(0 to 63-6);
    signal dst_count : unsigned(0 to 31);

    signal rq_reserve   : std_logic;
    signal rq_full      : std_logic;
    signal rq_write     : std_logic;
    signal rq_res_addr  : unsigned(0 to 5);
    signal rq_wr_addr   : unsigned(0 to 5);
    signal rq_empty     : std_logic;
    signal rq_comp      : std_logic;
    signal rq_comp_addr : unsigned(0 to 5);

    signal wq_write     : std_logic;
    signal wq_wr_addr   : unsigned(0 to 5);
    signal wq_full      : std_logic;
    signal wq_read      : std_logic;
    signal wq_rd_addr   : unsigned(0 to 5);
    signal wq_data      : std_logic_vector(0 to 511);
    signal wq_comp      : std_logic;
    signal wq_comp_addr : unsigned(0 to 5);

    signal wafifo_write : std_logic;
    signal wafifo_read  : std_logic;
    signal wafifo_valid : std_logic;
    signal wafifo_wdata : std_logic_vector(0 to dst_addr'length + wq_rd_addr'length - 3);
    signal wafifo_rdata : std_logic_vector(0 to dst_addr'length + wq_rd_addr'length - 3);
    signal wafifo_addr  : unsigned(0 to 63) := (others=>'0');
    signal wafifo_tag   : std_logic_vector(0 to 4);
    signal wafifo_empty : std_logic;

    signal last_write : std_logic := '0';

    signal ha_brvalid_last : std_logic;
    signal ha_brtag_last   : std_logic_vector(ha_brtag'range);

    signal dirty : std_logic;

    signal debug_state : std_logic_vector(0 to 7);
    signal debug_item_count : unsigned(0 to 15);
    signal debug_wr_count   : unsigned(0 to 31);
    signal debug_rd_count   : unsigned(0 to 31);

    signal rd_comp_count    : unsigned(0 to 31);

    signal is_done   : std_logic;
    signal is_done_d : std_logic_vector(0 to 7);

    signal clear : std_logic;

    signal start_time : unsigned(0 to 63);

    signal reg_wq_len        : unsigned(0 to 15);
    signal reg_wq_trigger    : std_logic;
    signal reg_wq_force_stop : std_logic;
    signal reg_wq_debug      : std_logic_vector(0 to 63);
    signal reg_wq_counts     : std_logic_vector(0 to 63);
    signal reg_croom         : unsigned(credits'range);
    signal reg_croom_set     : std_logic;

begin
    ah_cvalid <= ah_cvalid_i;
    ah_ctag   <= ah_ctag_i;

    proc_len   <= qitem_chunk_len;
    proc_flags <= qitem_flags(0 to 7);
    proc_clear <= clear;

    with state select debug_state <=
        x"01" when IDLE,
        x"02" when LOAD_QUEUE_ITEM,
        x"03" when WAIT_FOR_QUEUE_ITEM,
        x"04" when RUN,
        x"05" when READ_SRC,
        x"06" when WRITE_DST,
        x"07" when FLUSH,
        x"08" when RESTART_BUS,
        x"09" when SAVE_QUEUE_ITEM,
        x"0A" when NEXT_ITEM,
        x"0B" when WAIT_FOR_DONE,
        x"0C" when DONE,
        x"0D" when WRITE_WAIT,
        x"0E" when RESTART_BUS_FLUSH;

    reg_wq_debug <= debug_state & (8 to 47 => '0') &
                    std_logic_vector(debug_item_count);
    reg_wq_counts <= std_logic_vector(debug_wr_count) &
                     std_logic_vector(debug_rd_count);

    process (ha_pclock) is
        procedure submit_cmd(
            com : std_logic_vector(0 to 12);
            tag : std_logic_vector(0 to 7);
            addr : unsigned(0 to 63);
            size : positive) is
        begin
            ah_cvalid_i <= has_room;
            ah_com      <= com;
            ah_compar   <= calc_parity(com);
            ah_ctag_i   <= tag;
            ah_ctagpar  <= calc_parity(tag);
            ah_cea      <= addr;
            ah_ceapar   <= calc_parity(addr);
            ah_csize    <= to_unsigned(size, ah_csize'length);
        end procedure;

        procedure report_qitem is
            variable l : line;
        begin
            write(l, string'("wqueue: Running qitem ") & to_hstring(wed_addr));
            writeline(output, l);
            write(l, string'("wqueue:   SRC=") & to_hstring(qitem_src));
            writeline(output, l);
            write(l, string'("wqueue:   DST=") & to_hstring(qitem_dst));
            writeline(output, l);
            write(l, string'("wqueue:   LEN=") & to_hstring(qitem_chunk_len));
            writeline(output, l);
        end procedure;

    begin
        if rising_edge(ha_pclock) then
            ah_cvalid_i <= '0';
            wafifo_read <= '0';
            clear       <= '0';

            case state is
                when IDLE =>
                    if trigger_seen = '1' then
                        state <= LOAD_QUEUE_ITEM;
                    end if;

                when LOAD_QUEUE_ITEM =>
                    clear <= '1';
                    start_time <= timer;

                    submit_cmd(PSL_CMD_READ_CL_M,
                               TAG_QUEUE_ITEM & "00000",
                               wed_addr, 128);

                    if has_room = '1' then
                        state <= WAIT_FOR_QUEUE_ITEM;
                    end if;

                when WAIT_FOR_QUEUE_ITEM =>
                    dirty <= '0';
                    clear <= '1';

                    last_write <= '0';

                    if got_qitem = '1' then
                        clear <= '0';

                        if qitem_ready = '1' and qitem_done = '0' then
                            report_qitem;
                            src_addr  <= qitem_src;
                            src_count <= (others=>'0');

                            debug_item_count <= debug_item_count + 1;

                            state <= RUN;
                        else
                            state <= IDLE;
                        end if;
                    end if;

                when RUN =>
                    if is_done = '1' then
                        state <= FLUSH;
                    elsif wafifo_valid = '1' and
                        (last_write = '0' or src_count = qitem_chunk_len or
                         rq_full='1')
                    then
                        last_write <= not qitem_wr_only;
                        state <= WRITE_DST;
                        dirty <= '1';
                    elsif rq_full = '0' and src_count /= qitem_chunk_len and
                        qitem_wr_only = '0'
                    then
                        last_write <= '0';
                        src_count <= src_count + 1;
                        state <= READ_SRC;
                    end if;

                    if error_mask /= x"0000" then
                        state <= FLUSH;
                    end if;

                when READ_SRC =>
                    submit_cmd(PSL_CMD_READ_CL_NA,
                               TAG_RDATA & std_logic_vector(rq_res_addr(0 to 4)),
                               src_addr, 128);

                    if has_room = '1' then
                        src_addr  <= src_addr + "10000000";
                        state <= RUN;
                    end if;

                when WRITE_DST =>
                     submit_cmd(PSL_CMD_WRITE_NA,
                                TAG_WDATA & wafifo_tag,
                                wafifo_addr, 128);

                     if has_room = '1' then
                         wafifo_read <= '1';
                         state <= WRITE_WAIT;
                     end if;

                when WRITE_WAIT =>
                    state <= RUN;

                when FLUSH =>
                    if flushed = '1' then
                        if error_mask = x"0000" then
                            state <= SAVE_QUEUE_ITEM;
                        else
                            state <= RESTART_BUS;
                        end if;
                    end if;

                when RESTART_BUS =>
                    submit_cmd(PSL_CMD_RESTART,
                               "00000000",
                               (0 to 63 => '0'), 128);

                    if has_room = '1' then
                        state <= RESTART_BUS_FLUSH;
                    end if;

                when RESTART_BUS_FLUSH =>
                    if flushed = '1' and ah_cvalid_i = '0' then
                        state <= SAVE_QUEUE_ITEM;
                    end if;

                when SAVE_QUEUE_ITEM =>
                    submit_cmd(PSL_CMD_WRITE_MI,
                               TAG_QUEUE_ITEM & "00001",
                               wed_addr, 16);

                    if has_room = '1' then
                        wed_addr <= wed_addr_next;
                        state <= NEXT_ITEM;
                    end if;

                when NEXT_ITEM =>
                    if flushed = '1' and ah_cvalid_i = '0' then
                        state <= LOAD_QUEUE_ITEM;
                    end if;

                when WAIT_FOR_DONE =>
                    if flushed = '1' then
                        state <= DONE;
                    end if;

                when DONE =>
                    wqueue_done <= '1';
                when others => null;
            end case;

            if reg_wq_force_stop = '1' then
                state <= WAIT_FOR_DONE;
            end if;

            if reset = '1' then
                wqueue_done <= '0';
                state       <= IDLE;

                debug_item_count <= (others=>'0');
            end if;

            if start = '1' then
                wed_addr <= wed_base_addr;
            end if;
        end if;
    end process;

    TRIG: process (ha_pclock) is
    begin
        if rising_edge(ha_pclock) then
            if state = LOAD_QUEUE_ITEM then
                trigger_seen <= '0';
            elsif reg_wq_trigger = '1' then
                trigger_seen <= '1';
            end if;
        end if;
    end process TRIG;

    DONE_CHECK: process (ha_pclock) is
    begin
        if rising_edge(ha_pclock) then
            if clear = '1' then
                is_done   <= '0';
                is_done_d <= (others=>'0');

                proc_idone <= '0';
            else
                if rq_empty = '1' and (rd_comp_count = qitem_chunk_len or
                    qitem_wr_only = '1')
                then
                    proc_idone <= '1';
                end if;

                if wafifo_empty = '1' and flushed = '1' and  proc_odone = '1' then
                    is_done_d(0) <= '1';
                else
                    is_done_d(0) <= '0';
                end if;

                is_done_d(1 to is_done_d'high) <= is_done_d(0 to is_done_d'high -1);
                is_done <= std_logic(and_reduce(is_done_d));
            end if;
        end if;
    end process DONE_CHECK;

    ROOM_CHECK: process (ha_pclock) is
        variable decr : signed(0 to 1);
        variable incr : signed(ha_rcredits'range);
    begin
        if rising_edge(ha_pclock) then
            if reset = '1' then
                credits    <= signed("0" & ha_croom);
                credit_lim <= signed("0" & ha_croom);
                has_room   <= '1';
                flushed    <= '1';
            else

                if ah_cvalid_i = '1' then
                    decr := "01";
                else
                    decr := "00";
                end if;

                if ha_rvalid = '1' then
                    incr := ha_rcredits;
                else
                    incr := (others=>'0');
                end if;

                if reg_croom_set='1' then
                    credits    <= signed(reg_croom);
                    credit_lim <= signed(reg_croom);
                else
                    credits <= credits + incr - decr;
                end if;

                if credits < 1 then
                    has_room <= '0';
                else
                    has_room <= '1';
                end if;

                if credits = credit_lim then
                    flushed <= not ah_cvalid_i;
                else
                    flushed <= '0';
                end if;
            end if;
        end if;
    end process ROOM_CHECK;

    QITEM_READ: process (ha_pclock) is
    begin
        if rising_edge(ha_pclock) then
            got_qitem   <= '0';

            if ha_bwvalid = '1' then
                if ha_bwtag(0 to 2) = TAG_QUEUE_ITEM and ha_bwad(5) = '0' then

                    qitem_flags     <= endian_swap(ha_bwdata(0 to 15));
                    qitem_chunk_len <= endian_swap(unsigned(ha_bwdata(32 to 63)));
                    qitem_src       <= endian_swap(unsigned(ha_bwdata(128 to 191)));
                    qitem_dst       <= endian_swap(unsigned(ha_bwdata(192 to 255)));
                end if;
            end if;

            if ha_rvalid = '1' and ha_rtag(0 to 2) = TAG_QUEUE_ITEM then
                got_qitem <= '1';
            end if;
        end if;
    end process QITEM_READ;

    WDATA: process (ha_pclock) is
        variable rdata_qitem : std_logic_vector(0 to 511) := (others=>'0');
        variable rpar_qitem  : std_logic_vector(0 to 7)   := (others=>'0');
    begin
        if rising_edge(ha_pclock) then
            rdata_qitem(0 to 15)   := endian_swap(qitem_flags(0 to 12) & dirty & "10");
            rdata_qitem(16 to 31)  := endian_swap(error_mask);
            rdata_qitem(32 to 63)  := std_logic_vector(endian_swap("0" & dst_count(0 to 30)));
            rdata_qitem(64 to 95)  := std_logic_vector(endian_swap(start_time(32 to 63)));
            rdata_qitem(96 to 127) := std_logic_vector(endian_swap(timer(32 to 63)));
            for i in rpar_qitem'range loop
                rpar_qitem(i) := calc_parity(rdata_qitem(i*64 to (i+1)*64-1));
            end loop;

            ha_brvalid_last <= ha_brvalid;
            ha_brtag_last   <= ha_brtag;

            if ha_brvalid_last = '1' then
                if ha_brtag_last(0 to 2) = TAG_QUEUE_ITEM then
                    ah_brdata <= rdata_qitem;
                    ah_brpar  <= rpar_qitem;
                else
                    ah_brdata <= wq_data;
                    for i  in ah_brpar'range loop
                        ah_brpar(i)  <= calc_parity(wq_data(i*64 to (i+1)*64-1));
                    end loop;
                end if;
            end if;
        end if;
    end process WDATA;

    ERROR_CHECK: process (ha_pclock) is
    begin
        if rising_edge(ha_pclock) then
            if state = LOAD_QUEUE_ITEM then
                error_mask <= (others=>'0');
            elsif ha_rvalid = '1' then
                case ha_response is
                    when PSL_RESP_DONE    => null;
                    when PSL_RESP_AERROR  => error_mask(15) <= '1';
                    when PSL_RESP_DERROR  => error_mask(14) <= '1';
                    when PSL_RESP_NLOCK   => error_mask(13) <= '1';
                    when PSL_RESP_NRES    => error_mask(12) <= '1';
                    when PSL_RESP_FLUSHED => error_mask(11) <= '1';
                    when PSL_RESP_FAULT   => error_mask(10) <= '1';
                    when PSL_RESP_FAILED  => error_mask(9)  <= '1';
                    when PSL_RESP_PAGED   => error_mask(8)  <= '1';
                    when PSL_RESP_CONTEXT => error_mask(7)  <= '1';
                    when others => error_mask(6)  <= '1';
                end case;
            end if;
        end if;
    end process ERROR_CHECK;

    WED_ADDR_GEN : process (ha_pclock) is
    begin
        if rising_edge(ha_pclock) then
            if wed_addr = wed_base_addr + (reg_wq_len & "0000000") then
                wed_addr_next <= wed_base_addr;
            else
                wed_addr_next <= wed_addr + "10000000";
            end if;
        end if;
    end process WED_ADDR_GEN;

    READ_QUEUE: entity work.read_queue
        generic map (
            WRITE_SLACK => 6,
            DATA_BITS   => ha_bwdata'length,
            ADDR_BITS   => rq_wr_addr'length)
        port map (
            clk          => ha_pclock,
            rst          => clear,
            reserve      => rq_reserve,
            reserve_addr => rq_res_addr,
            full         => rq_full,
            empty        => rq_empty,
            write        => rq_write,
            write_addr   => rq_wr_addr,
            complete     => rq_comp,
            comp_addr    => rq_comp_addr,
            write_data   => ha_bwdata,
            read         => proc_iready,
            read_valid   => proc_ivalid,
            read_data    => proc_idata);

    rq_reserve   <= '1' when ah_cvalid_i = '1' and ah_ctag_i(0 to 2) = TAG_RDATA else '0';
    rq_write     <= '1' when ha_bwvalid = '1' and ha_bwtag(0 to 2) = TAG_RDATA else '0';
    rq_wr_addr   <= unsigned(ha_bwtag(3 to 7)) & ha_bwad(5);
    rq_comp      <= '1' when ha_rvalid = '1' and ha_rtag(0 to 2) = TAG_RDATA else '0';
    rq_comp_addr <= unsigned(ha_rtag(3 to 7)) & '0';

    WRITE_QUEUE: entity work.write_queue
        generic map (
            DATA_BITS => ha_bwdata'length,
            ADDR_BITS => wq_wr_addr'length)
        port map (
            clk        => ha_pclock,
            rst        => clear,
            write      => wq_write,
            write_data => proc_odata,
            write_addr => wq_wr_addr,
            full       => wq_full,
            read       => wq_read,
            read_addr  => wq_rd_addr,
            read_data  => wq_data,
            complete   => wq_comp,
            comp_addr  => wq_comp_addr);

    wq_write     <= proc_ovalid and (proc_odirty or qitem_always_wr);
    wq_read      <= '1' when ha_brvalid = '1' and ha_brtag(0 to 2) = TAG_WDATA else '0';
    wq_rd_addr   <= unsigned(ha_brtag(3 to 7)) &  ha_brad(5);
    wq_comp      <= '1' when ha_rvalid = '1' and ha_rtag(0 to 2) = TAG_WDATA else '0';
    wq_comp_addr <= unsigned(ha_rtag(3 to 7)) & '0';
    proc_oready  <= not wq_full;

    WRITE_ADDR_FIFO : entity work.sync_fifo_fwft
        generic map (
            DATA_BITS   => dst_addr'length + wq_wr_addr'length - 2,
            ADDR_BITS   => wq_wr_addr'length-1)
        port map (
            clk        => ha_pclock,
            rst        => clear,
            write      => wafifo_write,
            write_data => wafifo_wdata,
            read       => wafifo_read,
            read_valid => wafifo_valid,
            read_data  => wafifo_rdata,
            empty      => wafifo_empty);

    wafifo_write <= wq_write and dst_addr(dst_addr'high) and not wq_full;
    wafifo_wdata <= std_logic_vector(dst_addr(0 to dst_addr'high-1) & wq_wr_addr(0 to 4));
    wafifo_addr(0 to dst_addr'high-1)  <= unsigned(wafifo_rdata(0 to dst_addr'high-1));
    wafifo_tag <= wafifo_rdata(dst_addr'length-1 to wafifo_rdata'high);

    DST_ADDR_P: process (ha_pclock) is
    begin
        if rising_edge(ha_pclock) then
            if got_qitem = '1' then
                dst_count <= (others=>'0');
                dst_addr  <= qitem_dst(dst_addr'range);
            elsif proc_ovalid = '1' and wq_full = '0' then
                dst_addr  <= dst_addr + 1;
                dst_count <= dst_count + 1;
            end if;
        end if;
    end process DST_ADDR_P;

    RD_COUNT: process (ha_pclock) is
    begin
        if rising_edge(ha_pclock) then
            if clear = '1' then
                rd_comp_count <= (others=>'0');
            elsif ha_rvalid = '1' then
                if ha_rtag(0 to 2) = TAG_RDATA then
                    rd_comp_count <= rd_comp_count + 1;
                end if;
            end if;
        end if;
    end process RD_COUNT;


    DEBUG_COUNTS: process (ha_pclock) is
    begin
        if rising_edge(ha_pclock) then
            if reset = '1' then
                debug_wr_count <= (others=>'0');
                debug_rd_count <= (others=>'0');
            elsif ha_rvalid = '1' then
                if ha_rtag(0 to 2) = TAG_RDATA then
                    debug_rd_count <= debug_rd_count + 1;
                elsif ha_rtag(0 to 2) = TAG_WDATA then
                    debug_wr_count <= debug_wr_count + 1;
                end if;
            end if;
        end if;
    end process DEBUG_COUNTS;


    REG_READ_P: process (ha_pclock) is
    begin
        if rising_edge(ha_pclock) then
            reg_read_ack <= '0';
            reg_rdata <= (others=>'0');

            if reg_en = '1' then
                reg_read_ack <= reg_read;

                case to_integer(reg_addr(0 to 4)) is
                    when 0      => reg_rdata <= std_logic_vector(resize(reg_wq_len, 64));
                    --   1      => Trigger
                    --   2      => Stop
                    when 3      => reg_rdata <= reg_wq_debug;
                    when 4      => reg_rdata <= reg_wq_counts;
                    when 5      => reg_rdata <= std_logic_vector(resize(reg_croom, 64));
                    when 6      => reg_rdata <= std_logic_vector(timer);
                    when others => reg_rdata <= (others=>'0');
                end case;
            end if;
        end if;
    end process REG_READ_P;

    REG_WRITE_P: process (ha_pclock) is
    begin
        if rising_edge(ha_pclock) then
            reg_croom_set     <= '0';
            reg_wq_trigger    <= '0';
            reg_wq_force_stop <= '0';

            if reg_en = '1' and reg_write = '1' then
                case to_integer(reg_addr(0 to 4)) is
                    when  0 =>
                        if reg_addr(5) = '0' or reg_dw = '1' then
                            reg_wq_len <= resize(unsigned(reg_wdata), reg_wq_len'length);
                        end if;

                    when 1 => reg_wq_trigger    <= '1';
                    when 2 => reg_wq_force_stop <= '1';
                    when 3 => null;      --Debug
                    when 4 => null;      --Counts
                    when 5 =>
                        reg_croom_set <= '1';
                        if reg_addr(5) = '0' or reg_dw = '1' then
                            reg_croom <= resize(unsigned(reg_wdata), reg_croom'length);
                        end if;
                    when 6 => null;     --Timer

                    when others => null;
                end case;
            end if;

            if reset = '1' then
                reg_croom <= resize(ha_croom, reg_croom'length);
            end if;
        end if;
    end process REG_WRITE_P;

end architecture main;
