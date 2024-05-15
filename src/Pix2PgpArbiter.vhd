-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: PIX2PGP Arbiter
--              Column Supervisor signals Arbiter that FIFO statuses are stable
--              Then Arbiter Parses in the data accordingly
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

entity Pix2PgpArbiter is
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
      statusBusSel    : in  Pix2PgpStatusBusType;
      dataBusSel      : in  Pix2PgpDataBusType;
      dataRd          : out sl;
      colSel          : out slv(BITMAX_COL_MANAGERS_C-1 downto 0);
      -- Column Supervisor Interface
      arbiterStart    : in  sl;
      statusFifoError : in  sl;
      dataFifoError   : in  sl;
      overOccError    : in  sl;
      alignError      : in  sl;
      colBitmask      : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNum          : in  slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0);
      arbiterBusy     : out sl);
end Pix2PgpArbiter;

architecture rtl of Pix2PgpArbiter is

   type StateType is (
      IDLE_S,
      CHK_STATUS_S,
     -- TX_HEADER_S,
      CHK_DATALEN_S,
      INCR_SEL_S,
      WAIT_BUS_S
      );

   type RegType is record
      -- i/o
      statusBusSel    : Pix2PgpStatusBusType;
      dataBusSel      : Pix2PgpDataBusType;
      dataRd          : sl;
      colSel          : slv(BITMAX_COL_MANAGERS_C-1 downto 0);
      arbiterStart    : sl;
      statusFifoError : sl;
      dataFifoError   : sl;
      overOccError    : sl;
      alignError      : sl;
      colBitmask      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNum          : slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0);
      arbiterBusy     : sl;
      -- internal
      eventEmpty      : sl;
      headerOnly      : sl;
      waitCnt         : slv(WAITCNT_WIDTH_G-1 downto 0);
      state           : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- i/o
      statusBusSel    => DEFAULT_PIX2PGP_STATUSBUS_C,
      dataBusSel      => DEFAULT_PIX2PGP_DATABUS_C,
      dataRd          => '0',
      colSel          => (others => '0'),
      arbiterStart    => '0',
      statusFifoError => '0',
      dataFifoError   => '0',
      overOccError    => '0',
      alignError      => '0',
      colBitmask      => (others => '0'),
      trgNum          => (others => '0'),
      arbiterBusy     => '0',
      -- internal
      eventEmpty      => '0',
      headerOnly      => '0',
      waitCnt         => (others => '0'),
      state           => IDLE_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Arbiter FSM
   ------------------------------------------------
   comb : process (r, rst, statusBusSel, dataBusSel, arbiterStart, statusFifoError,
                   dataFifoError, overOccError, alignError, colBitmask, trgNum) is

      variable v : RegType;

   begin

      -- Latch the current value
      v := r;

      -- Strobes
      v.dataRd := '0';

      -- Register inputs
      v.statusBusSel    := statusBusSel;
      v.dataBusSel      := dataBusSel;
      v.arbiterStart    := arbiterStart;
      v.statusFifoError := statusFifoError;
      v.dataFifoError   := dataFifoError;
      v.overOccError    := overOccError;
      v.alignError      := alignError;
      v.colBitmask      := colBitmask;
      v.trgNum          := trgNum;

      v.eventEmpty      := not(uOr(r.colBitmask));

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- supervisor signals a start of sequence
         -- raise the busy flag
         when IDLE_S =>
            if r.arbiterStart = '1' then
               v.arbiterBusy := '1';
               v.state       := CHK_STATUS_S;
            end if;

         ----------------------------------------------------------------------
         -- check the error flags first (overocc is ignored by the Arbiter)
         when CHK_STATUS_S =>
            if r.statusFifoError = '1' or
               r.dataFifoError   = '1' or
               r.alignError      = '1' or
               r.eventEmpty      = '1' then

               v.headerOnly := '1';
               null; --v.state      := TX_HEADER_S;
            else
               v.state      := CHK_DATALEN_S;
            end if;

         ----------------------------------------------------------------------
         -- check the data length of the selected column
         when CHK_DATALEN_S =>
            v.waitCnt := (others => '0');

            if allBits((r.statusBusSel.dataLen), '0') then
               v.state := INCR_SEL_S;
            else
               null; --TO-DO FILL ME
            end if;

         ----------------------------------------------------------------------
         -- check the data length of the selected column
         when INCR_SEL_S =>
            if (r.colSel <= NUM_OF_COL_MANAGERS_C-1) then
               v.state := CHK_DATALEN_S;
            else
               null; -- v.state := TX_HEADER_S;
            end if;

         ----------------------------------------------------------------------
         -- wait for the bus to stabilize
         when WAIT_BUS_S =>
            v.waitCnt := r.waitCnt + 1;

            if r.waitCnt = WAIT_CYCLES_G then
               v.state := CHK_DATALEN_S;
            end if;
      end case;
      -------------------------------------------------------------------------

      -- Outputs
      dataRd <= r.dataRd;
      colSel <= r.colSel;

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
