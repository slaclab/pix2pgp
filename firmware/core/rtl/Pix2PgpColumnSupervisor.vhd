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
      colBitmask    : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNum        : out slv(TRG_WIDTH_C-1 downto 0));
end Pix2PgpColumnSupervisor;

architecture rtl of Pix2PgpColumnSupervisor is

   type StateType is (
      IDLE_S,            -- 000
      ARB_START_S,       -- 001
      WAIT_STATE_S,      -- 010
      IN_PAUSE_S,        -- 011
      IN_PAUSE_ERROR_S); -- 100

   type RegType is record
      -- i/o
      statusRd       : sl;
      arbiterBusy    : sl;
      arbiterStart   : sl;
      colFifoError   : sl;
      overOccError   : sl;
      colPause       : sl;
      colBitmask     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- internal
      pause          : sl;
      pauseError     : sl;
      pauseErrorEnd  : sl;
      dataReady      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colOverOccErr  : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colFifoFullErr : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      columnPause    : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colBitmaskArb  : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      statusRdBmsk   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      columnEnable   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      pauseErrorBmsk : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      columnBusy     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNum         : slv(TRG_WIDTH_C-1 downto 0);
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
      -- internal
      pause          => '0',
      pauseError     => '0',
      pauseErrorEnd  => '0',
      dataReady      => (others => '0'),
      colOverOccErr  => (others => '0'),
      colFifoFullErr => (others => '0'),
      columnPause    => (others => '0'),
      colBitmaskArb  => (others => '0'),
      statusRdBmsk   => (others => '1'),
      columnEnable   => (others => '1'),
      pauseErrorBmsk => (others => '0'),
      columnBusy     => (others => '0'),
      trgNum         => (others => '1'), -- so that on the first trigger it goes to zero
      waitCnt        => (others => '0'),
      state          => IDLE_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;
   signal colEmptyDbg : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');

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

         -- check Data Length from each column manager's status bus and set the colBitmask;
         -- a high bit on the bitmask indicates that the associated column does have hits
         if toBoolean(uOr(statusBusGlbl(col).dataLen)) and toBoolean(v.dataReady(col)) then
            v.colBitmask(col) := '1';
         else
            v.colBitmask(col) := '0';
         end if;

         -- check for any over-occupancy errors
         if toBoolean(statusBusGlbl(col).overOcc) and toBoolean(v.dataReady(col)) then
            v.colOverOccErr(col) := '1';
         else
            v.colOverOccErr(col) := '0';
         end if;

         -- check for any columnFull errors;
         -- note that in this case we do not check for dataReady!
         -- we need to know if the status FIFO is full regardless of its dataReady status
         if toBoolean(statusBusGlbl(col).columnFull) and toBoolean(v.columnEnable(col)) then
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

         -- busy is used to exit from the pause-error state
         v.columnBusy(col) := columnBusy(col) and v.columnEnable(col);

      end loop;

      ---------------------------------------------------------------------------
      case r.state is
      ---------------------------------------------------------------------------
         -- stay here until *all* enabled columns have data;
         -- at least *one* column must be enabled
         when IDLE_S =>
            v.pause        := '0';
            v.pauseError   := '0';
            v.waitCnt      := (others => '0');
            v.statusRdBmsk := (others => '1');

            if (v.dataReady = v.columnEnable) and toBoolean(uOr(v.columnEnable)) then
               v.trgNum := r.trgNum + 1;
               v.state  := ARB_START_S;
            end if;

         ----------------------------------------------------------------------
         -- start the arbiter; monitor the state of its busy signal
         when ARB_START_S =>
            -- update the arbiter status bits before starting the readout process
            v.colFifoError  := uOr(v.colFifoFullErr);
            v.overOccError  := uOr(v.colOverOccErr);
            v.colPause      := uOr(v.columnPause);

            -- if not in pause, get the regular bitmask
            if r.pause = '0' and r.pauseError = '0' then
               v.colBitmaskArb := v.colBitmask;
            end if;

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
               v.pause    := '0'; -- clear the pause flag
               v.state    := WAIT_STATE_S;

               -- were some columns in pause? set the pause flag!
               -- read r.colPause *now* because it will soon change state (after the statusRd)
               -- grab the columnPause bitmask *now* for that same reason
               -- (remember that if in pause-error, things are different)
               if r.colPause = '1' and r.pauseError = '0' then
                  v.pause         := '1';
                  v.colBitmaskArb := r.columnPause;
               end if;
            end if;
            -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

         ----------------------------------------------------------------------
         -- always wait before re-evaluating the status bus empty signal;
         -- the dataReady signal *must* re-settle!
         -- reading the status word on one cycle may not force the empty signal
         -- to go high on the next if there are no more status words in the FIFO
         -- determine what to do with pause and pause-error corner-cases
         -- note that the wait is longer to get out of the pause-error state;
         when WAIT_STATE_S =>
            v.waitCnt := r.waitCnt + 1;
            if (r.waitCnt = FIFO_RD_DELAY_G     and r.pauseErrorEnd = '0') or
               (r.waitCnt = PAUSE_ERROR_DELAY_G and r.pauseErrorEnd = '1') then
               v.waitCnt := (others => '0');
               v.state   := IDLE_S;

               -- override; the event that was just read was a paused event
               if r.pause = '1' then
                  v.state := IN_PAUSE_S;
               end if;

               -- override; need to finish emptying the columns if in pause-error
               if r.pauseError = '1' then
                  v.state := IN_PAUSE_ERROR_S;
               end if;

            end if;

         ----------------------------------------------------------------------
         -- pause event. evaluate the status of the status bus only on paused cols;
         -- wait for the paused columns to resume and close-out their event
         -- (or pause themselves again);
         when IN_PAUSE_S =>
            -- only pop the status words from the paused columns that are queried
            v.statusRdBmsk := v.colBitmaskArb;

            -- paused columns are still in pause and ready to be read;
            if ((v.colBitmaskArb and v.dataReady) = v.colBitmaskArb)
            and r.colPause = '1' then
               v.state := ARB_START_S;
            end if;

            -- corner-case 1: both previously-paused columns and non-paused columns are ready;
            -- basically means that everyone closed their event properly;
            -- resume normal operation (i.e. drop internal pause flag)
            -- same trigger so do not increment trigger counter
            if not(toBoolean(uOr(v.pauseErrorBmsk)))
               and toBoolean(uAnd(v.dataReady))
               and r.colPause = '0' then
               v.statusRdBmsk := (others => '1');
               v.pause        := '0';
               v.state        := ARB_START_S;
            end if;

            -- corner-case 2: another SRO came and now everyone has data again;
            -- abort and read the columns that have data;
            -- not in regular pause anymore, so drop that flag
            -- raise the pause-error flag and increment the trigger counter (new SRO)
            if toBoolean(uOr(v.pauseErrorBmsk)) then
               v.pause         := '0';
               v.pauseError    := '1';
               v.trgNum        := r.trgNum + 1;
               v.statusRdBmsk  := v.dataReady;
               v.colBitmaskArb := v.colBitmask;
               v.state         := ARB_START_S;
            end if;

         ----------------------------------------------------------------------
         -- during pause-error the FIFOs are being drained as fast as possible
         when IN_PAUSE_ERROR_S =>
             -- reset the flag (override below at the relevant if-clause)
            v.pauseErrorEnd := '0';

            -- keep draining the columns until they are all empty
            -- keep incrementing the trigger counter once for each read;
            -- (that read must yield an over-occ event)
            if uOr(v.dataReady) = '1' then
               if uOr(v.colOverOccErr) = '1' then
                  v.trgNum := r.trgNum + 1;
               end if;

               v.statusRdBmsk  := v.dataReady;
               v.colBitmaskArb := v.colBitmask;
               v.state         := ARB_START_S;
            end if;

            -- all FIFOs drained.
            -- wait for all status FIFOs to be completely settled;
            -- do that by going to the relevant state.
            if uOr(v.dataReady) = '0' and uOr(v.columnBusy) = '0' then
               -- raise the flag and then wait
               v.pauseErrorEnd := '1';
               v.state         := WAIT_STATE_S;

               -- the flag is reset at the top of this current state;
               -- the reg'd value will still be '1' if transitioned from WAIT_STATE_S
               if r.pauseErrorEnd = '1' then
                  v.state := IDLE_S;
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

   GEN_DBG: for col in 0 to NUM_OF_COL_MANAGERS_C-1 generate
      colEmptyDbg(col) <= statusBusGlbl(col).columnEmpty;
   end generate GEN_DBG;

end rtl;
