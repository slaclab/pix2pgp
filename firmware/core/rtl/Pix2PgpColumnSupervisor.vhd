-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Column Supervisor
--              Oversees the general status of all column managers;
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

entity Pix2PgpColumnSupervisor is
   generic(
      TPD_G               : time     := 1 ns;
      RST_ASYNC_G         : boolean  := false;
      RST_POLARITY_G      : sl       := '1';
      FIFO_RD_DELAY_G     : positive := 3;
      PAUSE_ERROR_DELAY_G : positive := 15);
   port(
      -- General Interface
      pgpClk        : in  sl;
      pgpRst        : in  sl := not(RST_POLARITY_G);
      columnEnable  : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- Column Manager Interface (via Bridge)
      statusBusGlbl : in  Pix2PgpStatusBusArray;
      columnBusy    : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      statusRd      : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- Arbiter Interface
      arbiterBusy   : in  sl;
      arbiterStart  : out sl;
      colFifoError  : out sl;
      overOccError  : out sl;
      colPauseError : out sl;
      colPause      : out sl;
      trgCntGlbl    : out  slv(TRGCNT_WIDTH_C-1 downto 0);
      colBitmask    : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0));
end Pix2PgpColumnSupervisor;

architecture rtl of Pix2PgpColumnSupervisor is

   type StateType is (
      IDLE_S,
      ARB_START_S,
      WAIT_STATE_S);

   type RegType is record
      -- i/o
      statusRd       : sl;
      arbiterBusy    : sl;
      arbiterStart   : sl;
      colFifoError   : sl;
      overOccError   : sl;
      colPause       : sl;
      colBitmask     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgCntGlbl     : slv(TRGCNT_WIDTH_C-1 downto 0);
      -- internal
      pause          : sl;
      pauseError     : sl;
      hitmaskAll     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      dataReady      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colOverOccErr  : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colFifoErr     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      columnPause    : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      statusRdBmsk   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      columnEnable   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      pauseErrorBmsk : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      columnBusy     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      waitCnt        : slv(3 downto 0);
      state          : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      statusRd       => '0',
      arbiterBusy    => '0',
      arbiterStart   => '0',
      colFifoError   => '0',
      overOccError   => '0',
      colPause       => '0',
      colBitmask     => (others => '0'),
      trgCntGlbl     => (others => '1'),
      -- internal
      pause          => '0',
      pauseError     => '0',
      hitmaskAll     => (others => '0'),
      dataReady      => (others => '0'),
      colOverOccErr  => (others => '0'),
      colFifoErr     => (others => '0'),
      columnPause    => (others => '0'),
      statusRdBmsk   => (others => '1'),
      columnEnable   => (others => '1'),
      pauseErrorBmsk => (others => '0'),
      columnBusy     => (others => '0'),
      waitCnt        => (others => '0'),
      state          => IDLE_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Column Supervisor FSM
   ------------------------------------------------
   comb : process (r, pgpRst, statusBusGlbl, arbiterBusy, columnEnable, columnBusy) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Strobes
      v.statusRd := '0';

      -- Register inputs
      v.arbiterBusy  := arbiterBusy;
      v.columnEnable := columnEnable;

      -- global status loop
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop

         -- column is ready when its status FIFO has a word;
         v.dataReady(col) := not(statusBusGlbl(col).columnEmpty) and v.columnEnable(col);

         -- note that for all flags we check against the dataReady signal;
         -- why? because we are using FWFT FIFOs...
         -- which means that if the FIFO is empty, it might present stale/misleading data!

         -- check Data Length from each column manager's status bus and set `hitmaskAll`;
         -- a high bit on this bitmask indicates that the associated column does have hits
         if toBoolean(uOr(statusBusGlbl(col).dataLen)) and toBoolean(v.dataReady(col)) then
            v.hitmaskAll(col) := '1';
         else
            v.hitmaskAll(col) := '0';
         end if;

         -- check for any over-occupancy errors
         if toBoolean(statusBusGlbl(col).overOcc) and toBoolean(v.dataReady(col)) then
            v.colOverOccErr(col) := '1';
         else
            v.colOverOccErr(col) := '0';
         end if;

         -- check for any fifoError flags;
         -- note that in this case we do not check for dataReady!
         -- we need to know if the FIFOs have underflowed regardless of the dataReady status
         if toBoolean(statusBusGlbl(col).fifoError) and toBoolean(v.columnEnable(col)) then
            v.colFifoErr(col) := '1';
         else
            v.colFifoErr(col) := '0';
         end if;

         if toBoolean(statusBusGlbl(col).pause) and toBoolean(v.dataReady(col)) then
            v.columnPause(col) := '1';
         else
            v.columnPause(col) := '0';
         end if;

         -- see columnManager; if both of these are high, an SRO was received while in pause
         -- also, check against the dataReady
         v.pauseErrorBmsk(col) := v.colOverOccErr(col) and v.columnPause(col) and v.dataReady(col);

         -- busy is used to exit from the pause-error state
         v.columnBusy(col) := columnBusy(col) and v.columnEnable(col);

      end loop;

      -- some random picks...can't think of anything smarter...
      if v.columnEnable(7) = '1' then
         v.trgCntGlbl := statusBusGlbl(7).trgCnt;
      elsif v.columnEnable(0) = '1' then
         v.trgCntGlbl := statusBusGlbl(0).trgCnt;
      elsif v.columnEnable(5) = '1' then
         v.trgCntGlbl := statusBusGlbl(5).trgCnt;
      elsif v.columnEnable(15) = '1' then
         v.trgCntGlbl := statusBusGlbl(15).trgCnt;
      elsif v.columnEnable(23) = '1' then
         v.trgCntGlbl := statusBusGlbl(23).trgCnt;
      end if;

      ---------------------------------------------------------------------------
      case r.state is
      ---------------------------------------------------------------------------
         -- stay here until *all* enabled columns have data;
         -- at least *one* column must be enabled
         when IDLE_S =>
            v.pause        := '0';
            v.waitCnt      := (others => '0');
            v.statusRdBmsk := (others => '1');
            v.colBitmask   := v.hitmaskAll;
            v.pause        := '0';
            v.pauseError   := '0';

            if (v.dataReady = v.columnEnable) and toBoolean(uOr(v.columnEnable)) then

               -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
               -- latch the errors
               -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
               v.colFifoError := uOr(v.colFifoErr);
               v.overOccError := uOr(v.colOverOccErr);

               -- raise the pause flag if necessary;
               -- override the columns that will be read
               if uOr(v.columnPause) = '1' and uOr(v.pauseErrorBmsk) = '0' then
                  v.statusRdBmsk := v.columnPause;
                  v.colBitmask   := v.columnPause;
                  v.pause        := '1';
               end if;

               -- will take into effect on next cycle
               if uOr(v.pauseErrorBmsk) = '1' then
                  v.pauseError := '1';
               end if;
               -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

               v.state := ARB_START_S;
            end if;

            -- in pause-error from previous readout cycle; (hence the r.)
            -- keep draining the columns until they are all empty
            if r.pauseError = '1' then
               v.pause := '0';

               if uOr(v.dataReady) = '1' then
                  v.statusRdBmsk := v.dataReady;
                  v.colBitmask   := v.hitmaskAll;

                  if uOr(v.pauseErrorBmsk) = '1' then
                     v.pauseError := '1';
                  end if;
               else
                  v.pauseError   := '0';
               end if;
            end if;

         ----------------------------------------------------------------------
         -- start the arbiter; monitor the state of its busy signal
         when ARB_START_S =>

            -- state switching;
            -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            -- first raise the start flag...
            if v.arbiterBusy = '0' and r.arbiterBusy = '0' and v.arbiterStart = '0' then
               v.arbiterStart := '1';
            end if;

            -- ...then release and wait...
            if v.arbiterBusy = '1' and v.arbiterStart = '1' then
               v.arbiterStart := '0';
            end if;

            -- ...and finally pop the status word when arbiter's busy transitions to low
            -- (negative-edge detection)
            if v.arbiterBusy = '0' and r.arbiterBusy = '1' then
               v.statusRd := '1'; -- pop the status word
               v.state    := WAIT_STATE_S;
            end if;
            -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

         ----------------------------------------------------------------------
         -- always wait before re-evaluating the status bus empty signal;
         -- the dataReady signal *must* re-settle!
         -- reading the status word on one cycle may not force the empty signal
         -- to go high on the next if there are no more status words in the FIFO
         when WAIT_STATE_S =>
            v.waitCnt := r.waitCnt + 1;
            if r.waitCnt = FIFO_RD_DELAY_G then
               v.waitCnt := (others => '0');
               v.state   := IDLE_S;
            end if;

      end case;
      ---------------------------------------------------------------------------

      -- Outputs
      colFifoError  <= v.colFifoError;
      overOccError  <= v.overOccError;
      colPause      <= v.pause;
      colPauseError <= v.pauseError;
      colBitmask    <= v.colBitmask;
      arbiterStart  <= r.arbiterStart; -- delay for one cycle
      trgCntGlbl    <= r.trgCntGlbl;

      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
         -- distribute the statusFifo rdEn
         statusRd(col) <= v.statusRd and v.statusRdBmsk(col) and v.columnEnable(col);
      end loop;

      -- Reset
      if (RST_ASYNC_G = false and pgpRst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (pgpClk, pgpRst) is
   begin
      if (RST_ASYNC_G and pgpRst = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(pgpClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

end rtl;
