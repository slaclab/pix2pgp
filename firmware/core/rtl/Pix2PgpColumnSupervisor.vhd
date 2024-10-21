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
      alignError    : out sl;
      colPause      : out sl;
      colEmpty      : out sl;
      colBitmask    : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNum        : out slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0));
end Pix2PgpColumnSupervisor;

architecture rtl of Pix2PgpColumnSupervisor is

   type StateType is (
      MON_STATUS_S,
      UPDATE_FLAGS_S,
      WAIT_ARB_S,
      PAUSE_S,
      DONE_S);

   type RegType is record
      -- i/o
      statusRd       : sl;
      arbiterBusy    : sl;
      arbiterStart   : sl;
      colFifoError   : sl;
      overOccError   : sl;
      alignError     : sl;
      colPause       : sl;
      colEmpty       : sl;
      colBitmask     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- internal
      pause          : sl;
      evalFlags      : sl;
      dataReady      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colTrgAlignErr : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colOverOccErr  : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colFifoFullErr : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      columnPause    : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colBitmaskArb  : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      pauseReadBmsk  : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNumArb      : slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0);
      waitCnt        : slv(bitSize(FIFO_RD_DELAY_G)-1 downto 0);
      state          : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      statusRd       => '0',
      arbiterBusy    => '0',
      arbiterStart   => '0',
      colFifoError   => '0',
      overOccError   => '0',
      alignError     => '0',
      colPause       => '0',
      colEmpty       => '0',
      colBitmask     => (others => '0'),
      -- internal
      pause          => '0',
      evalFlags      => '0',
      dataReady      => (others => '0'),
      colTrgAlignErr => (others => '0'),
      colOverOccErr  => (others => '0'),
      colFifoFullErr => (others => '0'),
      columnPause    => (others => '0'),
      colBitmaskArb  => (others => '0'),
      pauseReadBmsk  => (others => '0'),
      trgNumArb      => (others => '0'),
      waitCnt        => (others => '0'),
      state          => MON_STATUS_S);

   signal statusManagerDone : sl := '0';
   signal columnIgnore      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0)  := (others => '0');
   signal refTrgNum         : slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0) := (others => '0');

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Column Supervisor FSM
   ------------------------------------------------
   comb : process (r, pgpRst, statusBusGlbl, arbiterBusy,
                   columnIgnore, refTrgNum, statusManagerDone) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Strobes
      v.statusRd := '0';

      -- Register inputs
      v.arbiterBusy := arbiterBusy;

      -- global status loop
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop

         -- column is ready when its status FIFO has a word
         v.dataReady(col) := not(statusBusGlbl(col).columnEmpty) or
                                (columnIgnore(col));

         -- check Data Length from each column manager's status bus and set the colBitmask;
         -- a high bit on the bitmask indicates that the associated column does have hits
         if allBits(statusBusGlbl(col).dataLen, '0')
         or toBoolean(columnIgnore(col)) then
            v.colBitmask(col) := '0';
         else
            v.colBitmask(col) := '1';
         end if;

         -- evaluate status/error flags
         if r.evalFlags = '1' then

            -- check if all triggers are aligned with each other
            if statusBusGlbl(col).trgNum = refTrgNum
            or toBoolean(columnIgnore(col)) then
               v.colTrgAlignErr(col) := '0';
            else
               v.colTrgAlignErr(col) := '1';
            end if;

            -- check for any over-occupancy errors
            if (toBoolean(statusBusGlbl(col).overOcc)) and
            not(toBoolean(columnIgnore(col))) then
               v.colOverOccErr(col) := '1';
            else
               v.colOverOccErr(col) := '0';
            end if;

            -- check for any columnFull errors
            if (toBoolean(statusBusGlbl(col).columnFull)) and
            not(toBoolean(columnIgnore(col))) then
               v.colFifoFullErr(col) := '1';
            else
               v.colFifoFullErr(col) := '0';
            end if;

            if (toBoolean(statusBusGlbl(col).pause)) and
            not(toBoolean(columnIgnore(col))) then
               v.columnPause(col) := '1';
            else
               v.columnPause(col) := '0';
            end if;

         end if;

      end loop;

      ---------------------------------------------------------------------------
      case r.state is
      ---------------------------------------------------------------------------
         -- stay here until *all* columns have data;
         -- issue the rdEn pulse to the FIFO if all columns have data;
         -- don't do anything if all columns are disabled (see submodule)
         when MON_STATUS_S =>
            v.pause    := '0';
            v.waitCnt  := (others => '0');
            v.colEmpty := not(uOr(v.dataReady));

            if toBoolean(uAnd(v.dataReady)) and statusManagerDone = '1' then
               v.evalFlags := '1';
               v.state     := UPDATE_FLAGS_S;
            end if;

         ----------------------------------------------------------------------
         -- update the arbiter status bits before starting the readout process
         when UPDATE_FLAGS_S =>
            v.evalFlags     := '0';
            v.colEmpty      := '0';
            v.colFifoError  := uOr(v.colFifoFullErr);
            v.overOccError  := uOr(v.colOverOccErr);
            v.colPause      := uOr(v.columnPause);
            v.colBitmaskArb := v.colBitmask;

            -- override if in pause;
            -- forces status readout on paused cols only
            -- suppress alignment errors if in true pause mode
            if r.pause = '1' then
               v.alignError    := '0';
               v.colBitmaskArb := v.pauseReadBmsk;
            end if;

            -- only grab the trgNum if not in pause
            -- if in pause, keep the same trigger number
            -- same for alignment errors; ignore them while in pause
            if r.pause = '0' then
               v.trgNumArb  := refTrgNum;
               v.alignError := uOr(v.colTrgAlignErr);
            end if;

            -- state switching;
            -- first raise the start flag...
            if r.arbiterBusy = '0' and v.arbiterStart = '0' then
               v.arbiterStart := '1';
            end if;

            -- ...then switch and wait
            if r.arbiterBusy = '1' and v.arbiterStart = '1' then
               v.arbiterStart := '0';
               v.state        := WAIT_ARB_S;
            end if;

         ----------------------------------------------------------------------
         -- wait for the arbiter to finish parsing the data
         when WAIT_ARB_S =>
            if r.arbiterBusy = '0' then
               v.statusRd := '1'; -- pop the status word
               v.state    := DONE_S;
            end if;

         ----------------------------------------------------------------------
         -- pause event. change the status-readout mask and raise the flag;
         -- wait for the paused columns to resume and close-out their event
         -- (or pause themselves again);
         when PAUSE_S =>
            -- this internally-used pause flag controls the way columns are read-out
            v.pause := '1';

            if ((v.columnPause and v.dataReady) = v.columnPause) then
               v.evalFlags     := '1';
               v.pauseReadBmsk := v.columnPause;
               v.state         := UPDATE_FLAGS_S;
            end if;

            -- corner-case: another SRO came and now everyone has data again
            -- i.e. pause flag is dropped and normal operation is resumed
            -- (probably an over-occupancy/trigger misalignment though)
            if (toBoolean(uAnd(v.dataReady))) then
               v.evalFlags := '1';
               v.pause     := '0';
               v.state     := UPDATE_FLAGS_S;
            end if;

         ----------------------------------------------------------------------
         -- always wait before re-evaluating the status bus empty signal;
         -- reading the status word on one cycle may not force the empty signal
         -- to go high on the next if there are no more status words in the FIFO
         when DONE_S =>
            v.waitCnt := r.waitCnt + 1;
            if (r.waitCnt = FIFO_RD_DELAY_G) then
               v.state := MON_STATUS_S;

               -- override; the event that was just read was a paused event
               if (r.colPause = '1') then
                  v.state := PAUSE_S;
               end if;
            end if;

      end case;
      ---------------------------------------------------------------------------

      -- Outputs
      colFifoError <= v.colFifoError;
      overOccError <= v.overOccError;
      alignError   <= v.alignError;
      colPause     <= v.colPause;
      colBitmask   <= v.colBitmaskArb;
      trgNum       <= v.trgNumArb;
      arbiterStart <= r.arbiterStart; -- delay for one cycle
      colEmpty     <= v.colEmpty;

      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
         -- distribute the statusFifo rdEn
         -- note the difference if in pause mode; see relevant state
         if r.pause = '0' then
            statusRd(col) <= v.statusRd and not(columnIgnore(col));
         else
            statusRd(col) <= v.statusRd and v.pauseReadBmsk(col);
         end if;
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

   ------------------------------------------------
   -- Column Status sub-FSM
   ------------------------------------------------
   U_Pix2PgpColumnStatusManager: entity pix2pgp.Pix2PgpColumnStatusManager
      generic map(
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         RST_POLARITY_G => RST_POLARITY_G)
      port map(
         -- General Interface
         pgpClk        => pgpClk,
         pgpRst        => pgpRst,
         columnEnable  => columnEnable,
         -- Column Manager Interface
         statusBusGlbl => statusBusGlbl,
         -- Column Supervisor Interface
         done          => statusManagerDone,
         columnIgnore  => columnIgnore,
         refTrgNum     => refTrgNum);

end rtl;
