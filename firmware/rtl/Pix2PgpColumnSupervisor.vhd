-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Column Supervisor
--              Oversees the general status of all column managers;
--              Also increments trigger counter
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
      pgpClk          : in  sl;
      rst             : in  sl := not(RST_POLARITY_G);
      -- Column Manager Interface
      statusBusGlbl   : in  Pix2PgpStatusBusArray;
      statusRd        : out sl;
      -- Arbiter Interface
      arbiterBusy     : in  sl;
      arbiterStart    : out sl;
      statusFifoError : out sl;
      dataFifoError   : out sl;
      overOccError    : out sl;
      alignError      : out sl;
      colBitmask      : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNum          : out slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0));
end Pix2PgpColumnSupervisor;

architecture rtl of Pix2PgpColumnSupervisor is

   type StateType is (
      MON_STATUS_S,
      WAIT_BUS_S,
      CHECK_ERROR_S,
      WAIT_ARB_S);

   type RegType is record
      -- i/o
      statusRd         : sl;
      arbiterBusyDly   : sl;
      arbiterStart     : sl;
      statusFifoError  : sl;
      dataFifoError    : sl;
      overOccError     : sl;
      alignError       : sl;
      colBitmask       : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- internal
      dataReady        : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      refTrgNum        : slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0);
      colTrgAlignErr   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colOverOccErr    : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colDataFullErr   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colStatusFullErr : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      waitCnt          : slv(bitSize(FIFO_RD_DELAY_G)-1 downto 0);
      state            : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      statusRd         => '0',
      arbiterBusyDly   => '0',
      arbiterStart     => '0',
      statusFifoError  => '0',
      dataFifoError    => '0',
      overOccError     => '0',
      alignError       => '0',
      colBitmask       => (others => '0'),
      -- internal
      dataReady        => (others => '0'),
      refTrgNum        => (others => '0'),
      colTrgAlignErr   => (others => '0'),
      colOverOccErr    => (others => '0'),
      colDataFullErr   => (others => '0'),
      colStatusFullErr => (others => '0'),
      waitCnt          => (others => '0'),
      state            => MON_STATUS_S);

   signal arbiterBusyDly : sl;
   signal r              : RegType := REG_INIT_C;
   signal rin            : RegType;

begin

   ------------------------------------------------
   -- Column Supervisor FSM
   ------------------------------------------------
   comb : process (r, rst, statusBusGlbl, arbiterBusyDly) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Strobes
      v.statusRd := '0';

      -- Register inputs
      v.arbiterBusyDly := arbiterBusyDly;

      -- global monitoring of status bus
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
         -- column is ready when its status FIFO has a word
         v.dataReady(col) := not(statusBusGlbl(col).statusEmpty);

         -- check Data Length from each column manager's status bus and set the colBitmask accordingly
         -- a high bit on the bitmask indicates that the associated column does have hits
         if allBits(statusBusGlbl(col).dataLen, '0') then
            v.colBitmask(col) := '0';
         else
            v.colBitmask(col) := '1';
         end if;

         -- error-checking
         -- reference trigger number is associated with the first column
         v.refTrgNum := statusBusGlbl(0).trgNum;

         -- check if all triggers are aligned with each other
         if statusBusGlbl(col).trgNum = r.refTrgNum then
            v.colTrgAlignErr(col) := '0';
         else
            v.colTrgAlignErr(col) := '1';
         end if;

         -- check for any over-occupancy errors
         v.colOverOccErr(col) := statusBusGlbl(col).overOcc;

         -- check for any dataFull errors
         v.colDataFullErr(col) := statusBusGlbl(col).dataFull;

         -- check for any dataFull errors
         v.colStatusFullErr(col) := statusBusGlbl(col).statusFull;
      end loop;

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- stay here until *all* columns have data
         -- issue the rdEn pulse to the FIFO if all columns have data
         when MON_STATUS_S =>
            if toBoolean(uAnd(v.dataReady)) then
               v.statusRd := '1';
               v.state    := WAIT_BUS_S;
            end if;

         ----------------------------------------------------------------------
         -- wait for the bus to stabilize first
         when WAIT_BUS_S =>
            v.waitCnt         := r.waitCnt + 1;
            v.statusFifoError := uOr(v.colStatusFullErr);
            v.dataFifoError   := uOr(v.colDataFullErr);
            v.overOccError    := uOr(v.colOverOccErr);
            v.alignError      := uOr(v.colTrgAlignErr);

            if r.waitCnt = FIFO_RD_DELAY_G then
               v.state := CHECK_ERROR_S;
            end if;

         ----------------------------------------------------------------------
         -- change the column bitmask if an error is reported
         -- overOcc is read-out normally, so don't change the bitmask
         when CHECK_ERROR_S =>
            if r.statusFifoError = '1' then
               v.colBitmask := v.colStatusFullErr;
            elsif r.dataFifoError = '1' then
               v.colBitmask := v.colDataFullErr;
            elsif r.alignError = '1' then
               v.colBitmask := v.colTrgAlignErr;
            end if;

            v.arbiterStart := '1';

            -- rising-edge detection;
            -- arbiter might also be TX'ing dummy headers;
            -- need to account for this (can't just check `arbiterBusy = '1'`)
            if v.arbiterBusyDly = '1' and r.arbiterBusyDly = '0' then
               v.state := WAIT_ARB_S;
            end if;

         ----------------------------------------------------------------------
         -- wait for the arbiter to finish parsing the data
         when WAIT_ARB_S =>
            v.arbiterStart := '0';
            v.waitCnt      := (others => '0');

            if r.arbiterBusyDly = '0' then
               v.state := MON_STATUS_S;
            end if;

      end case;
      -------------------------------------------------------------------------

      -- Outputs
      statusRd        <= v.statusRd;
      statusFifoError <= v.statusFifoError;
      dataFifoError   <= v.dataFifoError;
      overOccError    <= v.overOccError;
      alignError      <= v.alignError;
      colBitmask      <= v.colBitmask;
      trgNum          <= v.refTrgNum;

      arbiterStart    <= r.arbiterStart;

      -- Reset
      if (RST_ASYNC_G = false and rst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (pgpClk, rst) is
   begin
      if (RST_ASYNC_G and rst = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(pgpClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

   U_PipelineBusy : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => 1)
      port map (
         clk     => pgpClk,
         din(0)  => arbiterBusy,
         dout(0) => arbiterBusyDly);

end rtl;
