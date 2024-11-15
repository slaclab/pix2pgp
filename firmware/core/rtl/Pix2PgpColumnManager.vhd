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
      -- Sparse Logic Interface
      din       : in  slv(SPARSE_DWIDTH_C-1 downto 0);
      wrEn      : in  sl;
      sof       : in  sl;
      eof       : in  sl;
      overOcc   : in  sl;
      pauseAck  : in  sl;
      busy      : out sl;
      pause     : out sl;
      -- Arbiter Interface
      statusRd  : in  sl;
      dataRd    : in  sl;
      statusBus : out Pix2PgpStatusBusType;
      dataBus   : out Pix2PgpDataBusType);
end Pix2PgpColumnManager;

architecture rtl of Pix2PgpColumnManager is

   signal statusFifoDout      : slv(STATUSFIFO_DWIDTH_C-1 downto 0) := (others => '0');
   signal dataFifoEmpty       : sl := '0';
   signal statusFifoEmpty     : sl := '0';
   signal statusFifoFullRd    : sl := '0';
   signal statusFifoAlmFull   : sl := '0';
   signal statusFifoFullDly   : sl := '0';
   signal dataFifoAlmFull     : sl := '0';

   signal statusWrEn          : sl := '0';
   signal statusDin           : slv(STATUSFIFO_DWIDTH_C-1 downto 0) := (others => '0');
   signal dataWrEn            : sl := '0';
   signal dataDin             : slv(SPARSE_DWIDTH_C-1 downto 0) := (others => '0');

   type RegType is record
      -- i/o
      sof           : sl;
      eof           : sl;
      overOcc       : sl;
      dataRd        : sl;
      busy          : sl;
      pause         : sl;
      pauseAck      : sl;
      din           : slv(SPARSE_DWIDTH_C-1 downto 0);
      -- internal
      overOccReg    : sl;
      pauseAckReg   : sl;
      eofReg        : sl;
      statusWr      : sl;
      dataWr        : sl;
      statusOk      : sl;
      statusFifoWr  : sl;
      statusFifoDin : slv(STATUSFIFO_DWIDTH_C-1 downto 0);
      wrEnCnt       : slv(DATALEN_WIDTH_C-1 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- i/o
      sof           => '0',
      eof           => '0',
      overOcc       => '0',
      dataRd        => '0',
      busy          => '0',
      pause         => '0',
      pauseAck      => '0',
      din           => (others => '0'),
      -- internal
      overOccReg    => '0',
      pauseAckReg   => '0',
      eofReg        => '0',
      statusWr      => '0',
      dataWr        => '0',
      statusOk      => '0',
      statusFifoWr  => '0',
      statusFifoDin => (others => '0'),
      wrEnCnt       => (others => '0'));

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Column Manager FSM
   ------------------------------------------------
   comb : process (r, sparseRst, sof, eof, wrEn, din, pauseAck, dataRd,
                   statusFifoDout, statusFifoAlmFull, statusFifoFullDly,
                   overOcc, dataFifoAlmFull) is

      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Register inputs
      v.sof      := sof;
      v.eof      := eof;
      v.din      := din;
      v.dataRd   := dataRd;
      v.pauseAck := pauseAck;
      v.overOcc  := overOcc;

      -- Strobes
      v.statusWr := '0';

      -- need to account for status-FIFO going full;
      -- if it goes full -> cannot write another word into it;
      -- so inhibit status writing in IN_FRAME_S;
      -- also prevent data words from being written to the data FIFO.
      -- this ensures that the correct wrEnCnt gets written to the status FIFO,
      -- once the status FIFO is not full again.
      -- otherwise the data FIFOs might not get read properly later on
      --
      -- using the non-delayed signal here;
      -- hopefully the design will still meet timing...
      -- (delayed FIFO signals to ease placement)
      -- gotta inhibit the writing of the status FIFO fast!
      v.statusOk := not(statusFifoAlmFull);

      -- rising-edge detection
      -- raise busy signal
      if v.sof = '1' and r.sof = '0' then
         v.busy := '1';
      end if;

      -- data FIFO wrEn
      -- only write while busy (in-frame)
      v.dataWr := wrEn and v.busy;

      -- wrEn counter management (rising-edge detection)
      if v.dataWr = '1' and r.dataWr = '0' then
         v.wrEnCnt := r.wrEnCnt + 1;
      end if;

      -- all these trigger a writing of a status word;
      -- note the use of *Reg. This is because a word might not be written right away.
      -- (the status FIFO *must not* be almostFull in order for its din to be written)
      -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      -- overOcc is single-cycle strobe; no need to catch edge
      if v.overOcc = '1' and v.busy = '1' and r.overOccReg = '0' then
         v.overOccReg := '1';
      end if;

      -- rising-edge detection (pauseAck is not a single-cycle strobe)
      if v.pauseAck = '1' and r.pauseAck = '0' and v.busy = '1' and r.pauseAckReg = '0' then
         v.pauseAckReg := '1';
      end if;

      -- EOF will remain high as long as this logic is busy
      -- busy is released once the EOF-related flag is written into the status
      if v.eof = '1' and v.busy = '1' and r.eofReg = '0' then
         v.eofReg := '1';
      end if;
      -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

      -- write status FIFO
      -- ///////////////////////////////////////////////////////////////////////////////////////////
      if (r.overOccReg = '1' or r.pauseAckReg = '1' or r.eofReg = '1') and v.statusOk = '1' then
         if r.wrEnCnt(0) = '1' then
            -- wrote odd number of hits? write an extra dummy word;
            -- hold for one clock cycle;
            -- wrEn will switch to input port by default on next cycle
            v.dataWr := '1';
         end if;

         v.statusFifoDin(STATUSFIFO_OVEROCC_POS_C) := r.overOccReg;
         v.statusFifoDin(STATUSFIFO_PAUSE_POS_C)   := r.pauseAckReg;
         v.statusFifoDin(STATUSFIFO_DATALEN_POS_C) := r.wrEnCnt;
         v.statusWr := '1';
         v.wrEnCnt  := (others => '0');

         -- reset the flags (including busy)
         -- over-occupancy received and written
         if r.overOccReg = '1' then
            v.overOccReg := '0';
         end if;

         -- pause-acknowledge received and written
         if r.pauseAckReg = '1' then
            v.pauseAckReg := '0';
         end if;

         -- regular EOF received and status word written
         if r.eofReg = '1' then
            v.eofReg := '0';
            v.busy   := '0';
         end if;
      end if;
      -- ///////////////////////////////////////////////////////////////////////////////////////////
      -- pause output handling
      v.pause := dataFifoAlmFull or statusFifoAlmFull;

      -- Outputs
      pause <= v.pause;
      busy  <= v.busy;
      -- status bus assignments (in pgpClk domain)
      statusBus.overOcc    <= statusFifoDout(STATUSFIFO_OVEROCC_POS_C);
      statusBus.pause      <= statusFifoDout(STATUSFIFO_PAUSE_POS_C);
      statusBus.dataLen    <= statusFifoDout(STATUSFIFO_DATALEN_POS_C);
      statusBus.columnFull <= statusFifoFullDly; -- dataFifo pauses the logic and shouldn't get full

      -- Reset
      if (RST_ASYNC_G = false and sparseRst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (sparseClk, sparseRst) is
   begin
      if RST_ASYNC_G and sparseRst = RST_POLARITY_G then
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
         din(0)  => statusFifoFullRd,
         dout(0) => statusFifoFullDly);

   U_StatusFifo : entity pix2pgp.Pix2PgpFifoWrapper
      generic map (
         TPD_G           => TPD_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         FWFT_EN_G       => true,
         DWARE_AF_LVL_G  => 1,
         WR_DATA_WIDTH_G => STATUSFIFO_DWIDTH_C,
         RD_DATA_WIDTH_G => STATUSFIFO_DWIDTH_C,
         DWARE_DEPTH_G   => STATUS_DEPTH_G,
         FULL_THRES_G    => 6, -- only for ghdl sim
         ADDR_WIDTH_G    => 4) -- only for ghdl sim
      port map (
         -- Resets
         rst      => sparseRst,
         -- Write Interface
         wrClk    => sparseClk,
         wrEn     => statusWrEn,
         din      => statusDin,
         aEmptyWr => open,
         aFullWr  => statusFifoAlmFull,
         emptyWr  => statusFifoEmpty, -- for debugging
         -- Read Interface
         rdClk    => pgpClk,
         rdEn     => statusRd,
         emptyRd  => statusBus.columnEmpty,
         fullRd   => statusFifoFullRd,
         dout     => statusFifoDout);

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
         rst      => sparseRst,
         -- Write Interface
         wrClk    => sparseClk,
         wrEn     => dataWrEn,
         din      => dataDin,
         aFullWr  => dataFifoAlmFull,
         emptyWr  => dataFifoEmpty,  -- for debugging
         -- Read Interface
         rdClk    => pgpClk,
         rdEn     => dataRd,
         emptyRd  => open,
         fullRd   => open,
         dout     => dataBus.data);

end rtl;
