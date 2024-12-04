-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Column Supervisor
--              Oversees the general status of all column managers
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
      FIFO_RD_DELAY_G : positive := 3;
      TIMEOUT_WIDTH_G : positive := 12);
   port(
      -- General Interface
      pgpClk        : in  sl;
      pgpRst        : in  sl := not(RST_POLARITY_G);
      timeoutLimit  : in  slv(TIMEOUT_WIDTH_G-1 downto 0);
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
      timeoutError  : out sl;
      colPauseError : out sl;
      colPause      : out sl;
      trgCntGlbl    : out slv(TRGCNT_WIDTH_C-1 downto 0);
      colBitmask    : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0));
end Pix2PgpColumnSupervisor;

architecture rtl of Pix2PgpColumnSupervisor is

   type StateType is (
      IDLE_S,
      ARB_START_S,
      WAIT_STATE_S,
      ERROR_S);

   type RegType is record
      -- i/o
      statusRd       : sl;
      arbiterBusy    : sl;
      arbiterStart   : sl;
      colFifoError   : sl;
      overOccError   : sl;
      timeoutError   : sl;
      colPause       : sl;
      colBitmask     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgCntGlbl     : slv(TRGCNT_WIDTH_C-1 downto 0);
      -- internal
      pause          : sl;
      pauseError     : sl;
      setWatchdog    : sl;
      timeout        : sl;
      allColsReady   : sl;
      hitmaskAll     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      dataReady      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colOverOccErr  : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colFifoErr     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      columnPause    : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      statusRdBmsk   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      columnEnable   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      pauseErrorBmsk : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      columnBusy     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      waitCnt        : slv(bitsize(FIFO_RD_DELAY_G) downto 0);
      state          : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      statusRd       => '0',
      arbiterBusy    => '0',
      arbiterStart   => '0',
      colFifoError   => '0',
      overOccError   => '0',
      timeoutError   => '0',
      colPause       => '0',
      colBitmask     => (others => '0'),
      trgCntGlbl     => (others => '1'),
      -- internal
      pause          => '0',
      pauseError     => '0',
      setWatchdog    => '0',
      timeout        => '0',
      allColsReady   => '0',
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

   signal setWatchdog : sl := '0';
   signal timeout     : sl := '0';

begin

   ------------------------------------------------
   -- Column Supervisor FSM
   ------------------------------------------------
   comb : process (r, pgpRst, statusBusGlbl, arbiterBusy,
                   columnEnable, columnBusy, timeout) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Strobes and Defaults
      v.statusRd    := '0';
      v.setWatchdog := '0';

      -- Register inputs
      v.arbiterBusy  := arbiterBusy;
      v.columnEnable := columnEnable;
      v.timeout      := timeout;

      -- global status loop
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop

         -- column is ready when its status FIFO has a word;
         v.dataReady(col) := not(statusBusGlbl(col).columnEmpty) and v.columnEnable(col);

         -- note that for all flags we check against the dataReady signal;
         -- why? because we are using FWFT FIFOs...
         -- which means that if the FIFO is empty, it might present stale/misleading data!

         -- check Data Length from each column manager's status bus and set `hitmaskAll`;
         -- a high bit on this bitmask indicates that the associated column does have hits
         v.hitmaskAll(col) := uOr(statusBusGlbl(col).dataLen) and v.dataReady(col);

         -- check for any over-occupancy errors
         v.colOverOccErr(col) := statusBusGlbl(col).overOcc and v.dataReady(col);

         -- check for any fifoError flags;
         -- note that in this case we do not check for dataReady!
         -- we need to know if the FIFOs have underflowed regardless of the dataReady status
         v.colFifoErr(col) := statusBusGlbl(col).fifoError and v.columnEnable(col);

         -- pause handling
         v.columnPause(col) := statusBusGlbl(col).pause and v.dataReady(col);

         -- see columnManager; if both of these are high, an SRO was received while in pause
         -- also, check against the dataReady
         v.pauseErrorBmsk(col) := v.colOverOccErr(col) and v.columnPause(col) and v.dataReady(col);

         -- busy is used to exit from the pause-error state
         v.columnBusy(col) := columnBusy(col) and v.columnEnable(col);

      end loop;

      -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      -- trigger count management
      -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      v.trgCntGlbl := (others => '0');

      -- separate loop for trigger counter assertion (have to exit it on first index hit)
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
         if v.dataReady(col) = '1' and uOr(v.columnPause) = '0' then
            v.trgCntGlbl := statusBusGlbl(col).trgCnt;
            exit;
         end if;

         if v.columnPause(col) = '1' and uOr(v.columnPause) = '1' then
            v.trgCntGlbl := statusBusGlbl(col).trgCnt;
            exit;
         end if;
      end loop;
      -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

      -- variable that triggers state transition from IDLE has to be evaluated last
      v.allColsReady := toSl(v.dataReady = v.columnEnable) and uOr(v.columnEnable);

      ---------------------------------------------------------------------------
      case r.state is
      ---------------------------------------------------------------------------
         -- stay here until *all* enabled columns have data;
         -- at least *one* column must be enabled
         when IDLE_S =>
            v.waitCnt      := (others => '0');
            v.statusRdBmsk := (others => '1');
            v.colBitmask   := v.hitmaskAll;
            v.colFifoError := uOr(v.colFifoErr);
            v.overOccError := uOr(v.colOverOccErr);
            v.pause        := '0';
            v.timeoutError := '0';
            v.pauseError   := '0';

            -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            -- nominal operation
            -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            if v.allColsReady = '1' then

               -- raise the pause flag if necessary;
               -- override the columns that will be read;
               -- in terms of status and data as well
               if uOr(v.columnPause) = '1' and uOr(v.pauseErrorBmsk) = '0' then
                  v.statusRdBmsk := v.columnPause;
                  v.colBitmask   := v.columnPause;
                  v.pause        := '1';
               end if;

               v.state := ARB_START_S;
            end if;
            -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            -- error handling
            -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            if uOr(v.dataReady) = '1' and v.allColsReady = '0' then
               v.setWatchdog := '1';
            end if;

            -- waited for too long for all columns to be ready,
            -- while some have been ready for some time...
            if v.timeout = '1' then
               v.timeoutError := '1';
               v.state        := ERROR_S;
            end if;

            -- pause + overOcc -> digital cannot keep up with the rate
            if uOr(v.pauseErrorBmsk) = '1' then
               v.pauseError := '1';
               v.state      := ERROR_S;
            end if;
            -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

         ----------------------------------------------------------------------
         -- start the arbiter; monitor the state of its busy signal
         when ARB_START_S =>

            -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            -- state switching
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
               v.statusRd     := '1'; -- pop the status word
               v.timeoutError := '0'; -- reset this
               v.state        := WAIT_STATE_S;
            end if;
            -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

         ----------------------------------------------------------------------
         -- always wait before re-evaluating the status bus empty signal;
         -- the dataReady signal *must* re-settle!
         -- reading the status word after one cycle may not force the empty signal
         -- to go high on the next even if there are no more status words in the FIFO
         when WAIT_STATE_S =>
            v.waitCnt := r.waitCnt + 1;
            if r.waitCnt = FIFO_RD_DELAY_G then
               v.state := IDLE_S;

               if v.pauseError = '1' or v.timeoutError = '1' then
                  v.state := ERROR_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- during this state the FIFOs are being drained as fast as possible
         when ERROR_S =>
            v.waitCnt := (others => '0');

            -- more data to read
            if uOr(v.dataReady) = '1' then
               v.statusRdBmsk := v.dataReady;
               v.colBitmask   := v.hitmaskAll;
               v.state        := ARB_START_S;
            end if;

            -- all FIFOs drained;
            -- release the error flags and go back to idle (after waiting)
            if uOr(v.dataReady) = '0' and uOr(v.columnBusy) = '0' then
               v.state := WAIT_STATE_S;
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
      trgCntGlbl    <= v.trgCntGlbl;
      timeoutError  <= v.timeoutError;

      setWatchdog   <= v.setWatchdog;

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

   U_Watchdog : entity pix2pgp.Pix2PgpWatchdog
      generic map(
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         RST_POLARITY_G => RST_POLARITY_G,
         CNT_WIDTH_G    => TIMEOUT_WIDTH_G)
      port map(
         -- General Interface
         clk     => pgpClk,
         rst     => pgpRst,
         limit   => timeoutLimit,
         -- Control Interface
         set     => setWatchdog,
         timeout => timeout);

end rtl;
