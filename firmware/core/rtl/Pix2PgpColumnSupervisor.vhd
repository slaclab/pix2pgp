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
      TPD_G           : time     := 1 ns;
      RST_ASYNC_G     : boolean  := false;
      RST_POLARITY_G  : sl       := '1';
      FIFO_RD_DELAY_G : positive := 3);
   port(
      -- General Interface
      pgpClk        : in  sl;
      pgpRst        : in  sl := not(RST_POLARITY_G);
      columnEnable  : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- Column Manager Interface (via Bridge)
      statusBusGlbl : in  Pix2PgpStatusBusArray;
      statusRd      : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- Arbiter Interface
      arbiterBusy   : in  sl;
      arbiterStart  : out sl;
      colFifoError  : out sl;
      overOccError  : out sl;
      colPauseError : out sl;
      colPause      : out sl;
      colEmpty      : out sl;
      colBitmask    : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNum        : out slv(TRG_WIDTH_C-1 downto 0));
end Pix2PgpColumnSupervisor;

architecture rtl of Pix2PgpColumnSupervisor is

   type StateType is (
      MON_STATUS_S,   -- 000
      UPDATE_FLAGS_S, -- 001
      WAIT_ARB_S,     -- 010
      PAUSE_S,        -- 011
      DONE_S);        -- 100

   type RegType is record
      -- i/o
      statusRd       : sl;
      arbiterBusy    : sl;
      arbiterStart   : sl;
      colFifoError   : sl;
      overOccError   : sl;
      colPause       : sl;
      colEmpty       : sl;
      colBitmask     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- internal
      pause          : sl;
      pauseError     : sl;
      dataReady      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colOverOccErr  : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colFifoFullErr : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      columnPause    : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colBitmaskArb  : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      statusRdBmsk   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      columnEnable   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      pauseErrorBmsk : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNum         : slv(TRG_WIDTH_C-1 downto 0);
      waitCnt        : slv(bitSize(FIFO_RD_DELAY_G)-1 downto 0);
      state          : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      statusRd       => '0',
      arbiterBusy    => '0',
      arbiterStart   => '0',
      colFifoError   => '0',
      overOccError   => '0',
      colPause       => '0',
      colEmpty       => '0',
      colBitmask     => (others => '0'),
      -- internal
      pause          => '0',
      pauseError     => '0',
      dataReady      => (others => '0'),
      colOverOccErr  => (others => '0'),
      colFifoFullErr => (others => '0'),
      columnPause    => (others => '0'),
      colBitmaskArb  => (others => '0'),
      statusRdBmsk   => (others => '1'),
      columnEnable   => (others => '1'),
      pauseErrorBmsk => (others => '0'),
      trgNum         => (others => '1'), -- so that on the first trigger it goes to zero
      waitCnt        => (others => '0'),
      state          => MON_STATUS_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Column Supervisor FSM
   ------------------------------------------------
   comb : process (r, pgpRst, statusBusGlbl, arbiterBusy, columnEnable) is
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

         -- column is ready when its status FIFO has a word
         v.dataReady(col) := not(statusBusGlbl(col).columnEmpty) and
                                (r.columnEnable(col));

         -- note that for all flags we check against the dataReady signal;
         -- why? because we are using FWFT FIFOs...
         -- which means that if the FIFO is empty, it might present stale/misleading data!

         -- check Data Length from each column manager's status bus and set the colBitmask;
         -- a high bit on the bitmask indicates that the associated column does have hits
         if allBits(statusBusGlbl(col).dataLen, '0') or toBoolean(not(v.dataReady(col))) then
            v.colBitmask(col) := '0';
         else
            v.colBitmask(col) := '1';
         end if;

         -- check for any over-occupancy errors
         if toBoolean(statusBusGlbl(col).overOcc) and toBoolean(v.dataReady(col)) then
            v.colOverOccErr(col) := '1';
         else
            v.colOverOccErr(col) := '0';
         end if;

         -- check for any columnFull errors
         if toBoolean(statusBusGlbl(col).columnFull) and toBoolean(v.dataReady(col)) then
            v.colFifoFullErr(col) := '1';
         else
            v.colFifoFullErr(col) := '0';
         end if;

         if toBoolean(statusBusGlbl(col).pause) and toBoolean(v.dataReady(col)) then
            v.columnPause(col) := '1';
         else
            v.columnPause(col) := '0';
         end if;

         -- see columnManager; if both of these are high, an SRO was received while in pause
         -- also, check against the dataReady
         v.pauseErrorBmsk(col) := v.colOverOccErr(col) and v.columnPause(col) and v.dataReady(col);

      end loop;

      ---------------------------------------------------------------------------
      case r.state is
      ---------------------------------------------------------------------------
         -- stay here until *all* columns have data;
         -- issue the rdEn pulse to the FIFO if all columns have data;
         -- don't do anything if all columns are disabled (see submodule)
         when MON_STATUS_S =>
            v.pause        := '0';
            v.pauseError   := '0';
            v.waitCnt      := (others => '0');
            v.colEmpty     := not(uOr(v.dataReady));
            v.statusRdBmsk := (others => '1');

            if toBoolean(uAnd(v.dataReady)) then
               v.trgNum := r.trgNum + 1;
               v.state  := UPDATE_FLAGS_S;
            end if;

         ----------------------------------------------------------------------
         -- update the arbiter status bits before starting the readout process
         when UPDATE_FLAGS_S =>
            v.colEmpty      := '0';
            v.colFifoError  := uOr(v.colFifoFullErr);
            v.overOccError  := uOr(v.colOverOccErr);
            v.colPause      := uOr(v.columnPause);

            -- if not in pause, get the regular bitmask;
            -- if in pause, bitmask is grabbed on DONE
            if r.pause = '0' then
               v.colBitmaskArb := v.colBitmask;
            end if;

            -- state switching;
            -- first raise the start flag...
            if v.arbiterBusy = '0' and v.arbiterStart = '0' then
               v.arbiterStart := '1';
            end if;

            -- ...then switch and wait
            if v.arbiterBusy = '1' and v.arbiterStart = '1' then
               v.arbiterStart := '0';
               v.state        := WAIT_ARB_S;
            end if;

         ----------------------------------------------------------------------
         -- wait for the arbiter to finish parsing the data
         -- evaluate pause-related flags now before they change state
         when WAIT_ARB_S =>
            if r.arbiterBusy = '0' then
               v.statusRd := '1'; -- pop the status word
               v.pause    := '0'; -- clear the flag
               v.state    := DONE_S;

               -- grab the previously-paused columns if last event was a pause
               -- read r.colPause *now* because it will soon change state (after the statusRd)
               -- grab the columnPause bitmask *now* for that same reason
               -- set the pause flag; remember that if in pause-error, things are different
               if r.colPause = '1' and r.pauseError = '0' then
                  v.pause         := '1';
                  v.colBitmaskArb := r.columnPause;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- pause event. evaluate the status of the status bus only on paused cols;
         -- wait for the paused columns to resume and close-out their event
         -- (or pause themselves again);
         when PAUSE_S =>
            -- only pop the status words from the paused columns that are queried
            v.statusRdBmsk := v.colBitmaskArb;

            if (v.colBitmaskArb and v.dataReady) = v.colBitmaskArb then
               v.state := UPDATE_FLAGS_S;
            end if;

            -- corner-case 1: both previously-paused columns and non-paused columns are ready;
            -- basically means that everyone closed their event properly;
            -- resume normal operation (i.e. drop internal pause flag)
            -- same trigger so do not increment trigger counter
            if not(toBoolean(uOr(v.pauseErrorBmsk))) and toBoolean(uAnd(v.dataReady)) then
               v.statusRdBmsk := (others => '1');
               v.pause        := '0';
               v.state        := UPDATE_FLAGS_S;
            end if;

            -- corner-case 2: another SRO came and now everyone has data again;
            -- abort and read the columns that have data;
            -- not in regular pause anymore, so drop that flag
            -- raise the pause-error flag and increment the trigger counter (new SRO)
            if toBoolean(uOr(v.pauseErrorBmsk)) then
               v.pause        := '0';
               v.pauseError   := '1';
               v.trgNum       := r.trgNum + 1;
               v.statusRdBmsk := v.dataReady;
               v.state        := UPDATE_FLAGS_S;
            end if;

         ----------------------------------------------------------------------
         -- always wait before re-evaluating the status bus empty signal;
         -- reading the status word on one cycle may not force the empty signal
         -- to go high on the next if there are no more status words in the FIFO
         -- determine what to do with pause and pause-error corner-cases
         when DONE_S =>
            v.waitCnt := r.waitCnt + 1;
            if (r.waitCnt = FIFO_RD_DELAY_G) then
               v.waitCnt := (others => '0');
               v.state   := MON_STATUS_S;

               -- override; the event that was just read was a paused event
               if r.pause = '1' then
                  v.state := PAUSE_S;
               end if;

               -- if in pause-error, keep draining the columns until they are all empty
               -- keep incrementing the trigger counter once for each read
               if r.pauseError = '1' and uOr(v.dataReady) = '1' then
                  v.statusRdBmsk := v.dataReady;
                  v.trgNum       := r.trgNum + 1;
                  v.state        := UPDATE_FLAGS_S;
               -- recovered from pause-error -> resume normal operation
               elsif r.pauseError = '1' and uOr(v.dataReady) = '0' then
                  v.state        := MON_STATUS_S;
               end if;
            end if;

      end case;
      ---------------------------------------------------------------------------

      -- Outputs
      colFifoError  <= v.colFifoError;
      overOccError  <= v.overOccError;
      colPause      <= v.colPause;
      colPauseError <= v.pauseError;
      colBitmask    <= v.colBitmaskArb;
      trgNum        <= v.trgNum;
      arbiterStart  <= r.arbiterStart; -- delay for one cycle
      colEmpty      <= v.colEmpty;

      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
         -- distribute the statusFifo rdEn
         statusRd(col) <= v.statusRd and v.statusRdBmsk(col) and r.columnEnable(col);
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
