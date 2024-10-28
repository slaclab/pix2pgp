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
   signal dataFifoAlmEmpty    : sl := '0';
   signal dataFifoAlmEmptyDly : sl := '0';
   signal statusFifoEmpty     : sl := '0';
   signal statusFifoFull      : sl := '0';
   signal statusFifoFullDly   : sl := '0';
   signal dataFifoAlmFull     : sl := '0';
   signal dataFifoAlmFullDly  : sl := '0';

   signal statusWrEn          : sl := '0';
   signal statusDin           : slv(STATUSFIFO_DWIDTH_C-1 downto 0) := (others => '0');
   signal dataWrEn            : sl := '0';
   signal dataDin             : slv(SPARSE_DWIDTH_C-1 downto 0) := (others => '0');

   type StateType is (
      IDLE_S,         -- 00
      IN_FRAME_S,     -- 01
      WREN_STATUS_S); -- 10

   type RegType is record
      -- i/o
      sof           : sl;
      eof           : sl;
      overOcc       : sl;
      dataRd        : sl;
      busy          : sl;
      pauseOut      : sl;
      pauseAck      : sl;
      din           : slv(SPARSE_DWIDTH_C-1 downto 0);
      -- internal
      statusWr      : sl;
      dataWr        : sl;
      statusOk      : sl;
      statusFifoDin : slv(STATUSFIFO_DWIDTH_C-1 downto 0);
      wrEnCnt       : slv(DATALEN_WIDTH_C-1 downto 0);
      state         : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- i/o
      sof           => '0',
      eof           => '0',
      overOcc       => '0',
      dataRd        => '0',
      busy          => '0',
      pauseOut      => '0',
      pauseAck      => '0',
      din           => (others => '0'),
      -- internal
      statusWr      => '0',
      dataWr        => '0',
      statusOk      => '0',
      statusFifoDin => (others => '0'),
      wrEnCnt       => (others => '0'),
      state         => IDLE_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Column Manager FSM
   ------------------------------------------------
   comb : process (r, sparseRst, sof, eof, wrEn, din, pauseAck,
                   dataRd, statusFifoDout, statusFifoFull, statusFifoFullDly,
                   overOcc, dataFifoAlmFullDly, dataFifoAlmEmptyDly) is

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

      -- need to account for status-FIFO going full;
      -- if it goes full -> cannot write another word into it;
      -- so inhibit status writing in IN_FRAME_S;
      -- also prevent data words from being written to the data FIFO.
      -- this ensures that the wrEnCnt does get written to the status FIFO,
      -- once the status FIFO is not full again.
      -- otherwise the data FIFOs might not get read properly later on
      --
      -- using the non-delayed signal here;
      -- hopefully the design will still meet timing...
      -- (delayed FIFO signals to ease placement)
      -- gotta inhibit the writing of the status FIFO fast!
      v.statusOk := not(statusFifoFull);

      -- data FIFO wrEn
      v.dataWr := wrEn and v.statusOk;

      -- wrEn counter management (rising-edge detection)
      if v.dataWr = '1' and r.dataWr = '0' then
         v.wrEnCnt := r.wrEnCnt + 1;
      end if;

      -- Strobes
      v.statusWr := '0';

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
            if v.sof = '1' then
               v.busy   := '1';
               v.state  := IN_FRAME_S;
            end if;

         ----------------------------------------------------------------------
         -- wait for end-of-frame, or for over-occupancy, or for FIFO to fill
         -- note the safeguards from status FIFO overflows
         when IN_FRAME_S =>

            -- if FIFO gets full, write the status *after*
            -- the FIFO-writing logic acknowledges the pause
            -- rising-edge detection
            if v.pauseAck = '1' and r.pauseAck = '0' and v.statusOk = '1' then
               v.state := WREN_STATUS_S;
            end if;

            -- regular EOF (ignore if in pause)
            if v.eof = '1' and r.pauseAck = '0' and v.statusOk = '1' then
               v.state := WREN_STATUS_S;
            end if;

            -- over-occupancy
            -- analog overOcc -> overOcc=high, pauseAck=low
            -- digital overOcc -> overOcc=high, pauseAck=high. danger!
            -- if digital overOcc happens ->
            -- both overOcc and pause flags are written into the FIFO:
            -- this will force the supervisor go to PAUSE_ERROR state.
            -- in that state, all columns are drained ASAP;
            -- if they are not drained in time, the status FIFO will get full;
            -- there are safeguards from statusFull here
            if v.overOcc = '1' and v.statusOk = '1' then
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
            v.statusFifoDin(STATUSFIFO_PAUSE_POS_C)   := r.pauseAck;
            v.statusFifoDin(STATUSFIFO_DATALEN_POS_C) := r.wrEnCnt;
            v.statusWr := '1';
            v.wrEnCnt  := (others => '0');

            -- state switching
            if (r.pauseAck = '1' or r.overOcc = '1') then
               v.state := IN_FRAME_S;
            else
               v.state := IDLE_S;
            end if;

      end case;
      -------------------------------------------------------------------------

      -- pause output handling (essentially wait for almost-empty)
      if (r.pauseAck = '0') then
         v.pauseOut := dataFifoAlmFullDly;
      else
         v.pauseOut := not(dataFifoAlmEmptyDly);
      end if;

      -- Outputs
      pause <= v.pauseOut;
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
         rst      => sparseRst,
         enable   => enable,
         -- Write Interface
         wrClk    => sparseClk,
         wrEn     => statusWrEn,
         din      => statusDin,
         aEmptyWr => open,
         fullWr   => open,
         emptyWr  => statusFifoEmpty, -- for debugging
         -- Read Interface
         rdClk    => pgpClk,
         rdEn     => statusRd,
         emptyRd  => statusBus.columnEmpty,
         fullRd   => statusFifoFull,
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

   U_PipelineDataAlmostFull : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => STATUSFIFO_PIPE_G)
      port map (
         clk     => sparseClk,
         din(0)  => dataFifoAlmFull,
         dout(0) => dataFifoAlmFullDly);

   U_PipelineDataAlmostEmpty : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => STATUSFIFO_PIPE_G)
      port map (
         clk     => sparseClk,
         din(0)  => dataFifoAlmEmpty,
         dout(0) => dataFifoAlmEmptyDly);

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
         enable   => enable,
         -- Write Interface
         wrClk    => sparseClk,
         wrEn     => dataWrEn,
         din      => dataDin,
         fullWr   => open,
         aEmptyWr => dataFifoAlmEmpty,
         aFullWr  => dataFifoAlmFull,
         emptyWr  => dataFifoEmpty,  -- for debugging
         -- Read Interface
         rdClk    => pgpClk,
         rdEn     => dataRd,
         emptyRd  => open,
         fullRd   => open,
         dout     => dataBus.data);

end rtl;
