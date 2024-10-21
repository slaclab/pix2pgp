-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Column Manager
--
-------------------------------------------------------------------------------
-- This file is part of 'Pix2Pgp'.
-- It is subject to the license terms in the LICENSE.txt file found in the
-- top-level directory of this distribution and at:
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
-- No part of 'Pix2Pgp', including this file,
-- may be copied, modified, propagated, or distributed except according to
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpColumnManager is
   generic(
      TPD_G             : time     := 1 ns;
      RST_ASYNC_G       : boolean  := false;
      RST_POLARITY_G    : sl       := '1';
      DATAFIFO_PIPE_G   : positive := 1;
      STATUSFIFO_PIPE_G : positive := 1;
      DATA_DEPTH_G      : integer  := 32;
      STATUS_DEPTH_G    : integer  := 32);
   port(
      -- General Interface
      sparseClk : in  sl;
      pgpClk    : in  sl;
      sparseRst : in  sl := not(RST_POLARITY_G);
      enable    : in  sl;
      -- Sparse Logic Interface
      din       : in  slv(SPARSE_DWIDTH_C-1 downto 0);
      wrEn      : in  sl;
      sof       : in  sl;
      eof       : in  sl;
      overOcc   : in  sl;
      busy      : out sl;
      pause     : out sl;
      -- Arbiter Interface
      statusRd  : in  sl;
      dataRd    : in  sl;
      statusBus : out Pix2PgpStatusBusType;
      dataBus   : out Pix2PgpDataBusType);
end Pix2PgpColumnManager;

architecture rtl of Pix2PgpColumnManager is

   signal statusFifoDout     : slv(STATUSFIFO_DWIDTH_C-1 downto 0) := (others => '0');
   signal dataFifoEmpty      : sl := '0';
   signal dataFifoEmptyDly   : sl := '0';
   signal statusFifoFull     : sl := '0';
   signal statusFifoFullDly  : sl := '0';
   signal dataFifoFull       : sl := '0';
   signal dataFifoFullDly    : sl := '0';

   signal statusWrEn         : sl := '0';
   signal statusDin          : slv(STATUSFIFO_DWIDTH_C-1 downto 0) := (others => '0');
   signal dataWrEn           : sl := '0';
   signal dataDin            : slv(SPARSE_DWIDTH_C-1 downto 0) := (others => '0');

   type StateType is (
      IDLE_S,         -- 00
      IN_FRAME_S,     -- 01
      WREN_STATUS_S); -- 10

   type RegType is record
      -- i/o
      sof           : sl;
      eof           : sl;
      overOcc       : sl;
      statusRd      : sl;
      dataRd        : sl;
      pause         : sl;
      busy          : sl;
      din           : slv(SPARSE_DWIDTH_C-1 downto 0);
      -- internal
      statusWr      : sl;
      dataWr        : sl;
      statusFifoDin : slv(STATUSFIFO_DWIDTH_C-1 downto 0);
      wrEnCnt       : slv(DATALEN_WIDTH_C-1 downto 0);
      trgCnt        : slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0);
      state         : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- i/o
      sof           => '0',
      eof           => '0',
      overOcc       => '0',
      statusRd      => '0',
      dataRd        => '0',
      pause         => '0',
      busy          => '0',
      din           => (others => '0'),
      -- internal
      statusWr      => '0',
      dataWr        => '0',
      statusFifoDin => (others => '0'),
      wrEnCnt       => (others => '0'),
      trgCnt        => (others => '1'), -- so that it rolls-over to zero on first trigger
      state         => IDLE_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Column Manager FSM
   ------------------------------------------------
   comb : process (r, sparseRst, sof, eof, wrEn, din, statusRd,
                   dataRd, dataFifoEmptyDly, dataFifoFullDly,
                   statusFifoDout, statusFifoFullDly, overOcc) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Register inputs
      v.sof      := sof;
      v.eof      := eof;
      v.dataWr   := wrEn;
      v.din      := din;
      v.statusRd := statusRd;
      v.dataRd   := dataRd;

      -- Strobes
      v.statusWr := '0';

      -- wrEn counter management (rising-edge detection)
      if (v.dataWr = '1' and r.dataWr = '0') then
         v.wrEnCnt := r.wrEnCnt + 1;
      end if;

      -- latch the over-occupancy flag here
      if (v.overOcc = '0') then
         v.overOcc := overOcc;
      end if;

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- wait for token; also reset the counters and flags
         when IDLE_S =>
            v.busy    := '0';
            v.wrEnCnt := (others => '0');

            -- start-of-frame detection
            if (v.sof = '1') then
               v.busy   := '1';
               v.trgCnt := r.trgCnt + 1;
               v.state  := IN_FRAME_S;
            end if;

         ----------------------------------------------------------------------
         -- wait for end-of-frame, or for over-occupancy, or for FIFO to fill
         when IN_FRAME_S =>

            -- clear the flag here if was in pause before
            if (r.pause = '1') then
               v.pause := not(dataFifoEmptyDly);
            end if;

            -- if FIFO gets full for the first time, write the status immediately;
            -- also tie the pause flag to the fullData signal
            if (dataFifoFullDly = '1' and r.pause = '0') then
               v.pause := dataFifoFullDly;
               v.state := WREN_STATUS_S;
            end if;

            -- regular EOF (is never issued while in pause)
            -- posedge detection
            if (v.eof = '1' and r.eof = '0') then
               v.state := WREN_STATUS_S;
            end if;

            -- overOcc can happen because of analog (pause is low);
            -- ...or because of digital backpressure (pause is high)
            if (v.overOcc = '1') then
               v.state := WREN_STATUS_S;
            end if;

         ----------------------------------------------------------------------
         -- write into the status FIFO
         when WREN_STATUS_S =>
            v.overOcc := '0'; -- clear (registered value still gets written)

            if r.wrEnCnt(0) = '1' then
               -- wrote odd number of hits? write an extra dummy word;
               -- hold for one clock cycle;
               -- wrEn will switch to input port by default on next cycle
               v.dataWr := '1';
            end if;

            v.statusFifoDin(STATUSFIFO_OVEROCC_POS_C) := r.overOcc;
            v.statusFifoDin(STATUSFIFO_PAUSE_POS_C)   := r.pause;
            v.statusFifoDin(STATUSFIFO_TRG_POS_C)     := r.trgCnt;
            v.statusFifoDin(STATUSFIFO_DATALEN_POS_C) := r.wrEnCnt;
            v.statusWr := '1';
            v.wrEnCnt  := (others => '0');

            -- state switching
            if (v.pause = '1') then
               v.state  := IN_FRAME_S;
            elsif (r.overOcc = '1') then -- have to use the r. here (it gets cleared)
               v.trgCnt := r.trgCnt + 1;
               v.state  := IN_FRAME_S;
            else
               v.state  := IDLE_S;
            end if;

      end case;
      -------------------------------------------------------------------------

      -- Outputs
      pause <= v.pause;
      busy  <= v.busy;
      -- status bus assignments (in pgpClk domain)
      statusBus.pause      <= statusFifoDout(STATUSFIFO_PAUSE_POS_C);
      statusBus.trgNum     <= statusFifoDout(STATUSFIFO_TRG_POS_C);
      statusBus.dataLen    <= statusFifoDout(STATUSFIFO_DATALEN_POS_C);
      statusBus.overOcc    <= statusFifoDout(STATUSFIFO_OVEROCC_POS_C);
      statusBus.columnFull <= statusFifoFullDly; -- dataFifo pauses the logic and shouldn't get full

      -- Reset
      if (RST_ASYNC_G = false and sparseRst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (sparseClk, sparseRst, enable) is
   begin
      if ((RST_ASYNC_G and sparseRst = RST_POLARITY_G)
      or  enable = '0') then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(sparseClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

   ------------------------------------------------
   -- Status FIFO
   ------------------------------------------------
   -- pipeline the status FIFO i/o signals to give some freedom in placement
   U_PipelineStatusWrEn : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => STATUSFIFO_PIPE_G)
      port map (
         clk     => sparseClk,
         din(0)  => r.statusWr,
         dout(0) => statusWrEn);

   U_PipelineStatusDin : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => STATUSFIFO_DWIDTH_C,
         DELAY_G        => STATUSFIFO_PIPE_G)
      port map (
         clk  => sparseClk,
         din  => r.statusFifoDin,
         dout => statusDin);

   U_PipelineStatusFull : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => STATUSFIFO_PIPE_G)
      port map (
         clk     => pgpClk,
         din(0)  => statusFifoFull,
         dout(0) => statusFifoFullDly);

   U_StatusFifo : entity pix2pgp.Pix2PgpFifoWrapper
      generic map (
         TPD_G           => TPD_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         FWFT_EN_G       => true,
         WR_DATA_WIDTH_G => STATUSFIFO_DWIDTH_C,
         RD_DATA_WIDTH_G => STATUSFIFO_DWIDTH_C,
         DWARE_DEPTH_G   => STATUS_DEPTH_G,
         FULL_THRES_G    => 6, -- only for ghdl sim
         ADDR_WIDTH_G    => 4) -- only for ghdl sim
      port map (
         -- Resets
         rst     => sparseRst,
         enable  => enable,
         -- Write Interface
         wrClk   => sparseClk,
         wrEn    => statusWrEn,
         din     => statusDin,
         fullWr  => open,
         emptyWr => open,
         -- Read Interface
         rdClk   => pgpClk,
         rdEn    => statusRd,
         emptyRd => statusBus.columnEmpty,
         fullRd  => statusFifoFull,
         dout    => statusFifoDout);

   ------------------------------------------------
   -- Data FIFO
   ------------------------------------------------
   -- pipeline the data FIFO input signals to give some freedom in placement
   U_PipelineDataWrEn : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => DATAFIFO_PIPE_G)
      port map (
         clk     => sparseClk,
         din(0)  => r.dataWr,
         dout(0) => dataWrEn);

   U_PipelineDataDin : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => SPARSE_DWIDTH_C,
         DELAY_G        => DATAFIFO_PIPE_G)
      port map (
         clk  => sparseClk,
         din  => r.din,
         dout => dataDin);

   U_PipelineDataEmpty : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => STATUSFIFO_PIPE_G)
      port map (
         clk     => sparseClk,
         din(0)  => dataFifoEmpty,
         dout(0) => dataFifoEmptyDly);

   U_PipelineDataFull : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => STATUSFIFO_PIPE_G)
      port map (
         clk     => sparseClk,
         din(0)  => dataFifoFull,
         dout(0) => dataFifoFullDly);

   U_DataFifo : entity pix2pgp.Pix2PgpFifoWrapper
      generic map (
         TPD_G           => TPD_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         FWFT_EN_G       => true,
         DWARE_AF_LVL_G  => 1,
         WR_DATA_WIDTH_G => SPARSE_DWIDTH_C,
         RD_DATA_WIDTH_G => DATABUS_DWIDTH_C,
         DWARE_DEPTH_G   => DATA_DEPTH_G,
         FULL_THRES_G    => 6, -- only for ghdl sim
         ADDR_WIDTH_G    => 4) -- only for ghdl sim
      port map (
         -- Resets
         rst     => sparseRst,
         enable  => enable,
         -- Write Interface
         wrClk   => sparseClk,
         wrEn    => dataWrEn,
         din     => dataDin,
         fullWr  => open,
         aFullWr => dataFifoFull,
         emptyWr => dataFifoEmpty,
         -- Read Interface
         rdClk   => pgpClk,
         rdEn    => dataRd,
         emptyRd => open,
         fullRd  => open,
         dout    => dataBus.data);

end rtl;
