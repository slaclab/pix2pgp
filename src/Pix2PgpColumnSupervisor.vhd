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
      WAITCNT_WIDTH_G : positive := 8;
      WAIT_CYCLES_G   : positive := 4);
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
      REG_STATUS_S,
      WAIT_ARB_S);

   type RegType is record
      -- i/o
      statusBusGlbl    : Pix2PgpStatusBusArray;
      statusRd         : sl;
      arbiterBusy      : sl;
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
      waitCnt          : slv(WAITCNT_WIDTH_G-1 downto 0);
      state            : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      statusBusGlbl    => (others => DEFAULT_PIX2PGP_STATUSBUS_C),
      statusRd         => '0',
      arbiterBusy      => '0',
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

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Column Supervisor FSM
   ------------------------------------------------
   comb : process (r, rst, statusBusGlbl, arbiterBusy) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Strobes
      v.statusRd := '0';

      -- Register inputs
      v.statusBusGlbl := statusBusGlbl;
      v.arbiterBusy   := arbiterBusy;

      -- global monitoring of status bus
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
         -- column is ready when its status FIFO has a word
         v.dataReady(col) := not(r.statusBusGlbl(col).statusEmpty);

         -- check Data Length from each column manager's status bus and set the colBitmask accordingly
         -- a high bit on the bitmask indicates that the associated column does have hits
         v.colBitmask(col) := ite(allBits(r.statusBusGlbl(col).dataLen, '0'), '0', '1');

         -- error-checking
         -- reference trigger number is associated with "middle" column (arbitrary)
         v.refTrgNum := r.statusBusGlbl(NUM_OF_COL_MANAGERS_C/2).trgNum;

         -- check if all triggers are aligned with each other
         v.colTrgAlignErr(col) := ite(r.statusBusGlbl(col).trgNum = r.refTrgNum, '0', '1');

         -- check for any over-occupancy errors
         v.colOverOccErr(col) := r.statusBusGlbl(col).overOcc;

         -- check for any dataFull errors
         v.colDataFullErr(col) := r.statusBusGlbl(col).dataFull;

         -- check for any dataFull errors
         v.colStatusFullErr(col) := r.statusBusGlbl(col).statusFull;
      end loop;

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- stay here until *all* columns have data
         -- issue the rdEn pulse to the FIFO if all columns have data
         when MON_STATUS_S =>
            if toBoolean(uAnd(r.dataReady)) then
               v.statusRd := '1';
               v.state    := WAIT_BUS_S;
            end if;

         ----------------------------------------------------------------------
         -- wait for the bus to stabilize first
         when WAIT_BUS_S =>
            v.waitCnt := r.waitCnt + 1;

            if r.waitCnt = WAIT_CYCLES_G then
               v.state := REG_STATUS_S;
            end if;

         ----------------------------------------------------------------------
         -- register the status bits and signal the arbiter to do its thing
         when REG_STATUS_S =>
            v.statusFifoError := uOr(r.colStatusFullErr);
            v.dataFifoError   := uOr(r.colDataFullErr);
            v.overOccError    := uOr(r.colOverOccErr);
            v.alignError      := uOr(r.colTrgAlignErr);
            v.arbiterStart    := '1';

            if r.arbiterBusy = '1' then
               v.state := WAIT_ARB_S;
            end if;

         ----------------------------------------------------------------------
         -- wait for the arbiter to finish parsing the data
         when WAIT_ARB_S =>
            v.arbiterStart := '0';
            v.waitCnt      := (others => '0');

            if r.arbiterBusy = '0' then
               v.state := MON_STATUS_S;
            end if;

      end case;
      -------------------------------------------------------------------------

      -- Outputs
      statusRd        <= r.statusRd;
      arbiterStart    <= r.arbiterStart;
      statusFifoError <= r.statusFifoError;
      dataFifoError   <= r.dataFifoError;
      overOccError    <= r.overOccError;
      alignError      <= r.alignError;
      colBitmask      <= r.colBitmask;
      trgNum          <= r.refTrgNum;

      -- Reset
      if (RST_ASYNC_G = false and rst = '1') then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (pgpClk, rst) is
   begin
      if (RST_ASYNC_G and rst = '1') then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(pgpClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

end rtl;
