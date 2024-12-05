-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Status/Data Bus Multiplexer and control signal pipeline
--              Note that not all parts of the status bus are multiplexed;
--              some are just pipelined
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

entity Pix2PgpBridge is
   generic(
      TPD_G             : time    := 1 ns;
      PIPELINE_DATA_G   : boolean := false;
      PIPELINE_STATUS_G : boolean := false);
   port(
      -- General Interface
      pgpClk        : in  sl;
      -- Column Manager Interface
      statusBusIn   : in  Pix2PgpStatusBusArray;
      dataBusIn     : in  Pix2PgpDataBusArray;
      busyIn        : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      statusRdOut   : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      dataRdOut     : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- Column Supervisor Interface
      statusRdIn    : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      busyOut       : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      statusBusGlbl : out Pix2PgpStatusBusArray;
      -- Arbiter Interface
      dataRdIn      : in  sl;
      colSel        : in  slv(BITMAX_COL_MANAGERS_C downto 0);
      statusBusSel  : out Pix2PgpStatusBusType;
      dataBusSel    : out Pix2PgpDataBusType);
end Pix2PgpBridge;

architecture rtl of Pix2PgpBridge is

begin

   GEN_NO_PIPELINE_STATUS : if (PIPELINE_STATUS_G = false) generate
      process(statusBusIn, colSel, statusRdIn, busyIn)
      begin
         statusBusGlbl <= statusBusIn;
         statusRdOut   <= statusRdIn;
         busyOut       <= busyIn;

         if colSel <= NUM_OF_COL_MANAGERS_C-1 then
            statusBusSel <= statusBusIn(conv_integer(unsigned(colSel)));
         else
            statusBusSel <= DEFAULT_PIX2PGP_STATUSBUS_C;
         end if;
      end process;
   end generate GEN_NO_PIPELINE_STATUS;

   GEN_NO_PIPELINE_DATA : if (PIPELINE_DATA_G = false) generate
      process(colSel, dataBusIn, dataRdIn)
      begin
         if dataRdIn = '1' then
            if colSel <= NUM_OF_COL_MANAGERS_C-1 then
               dataRdOut(conv_integer(unsigned(colSel))) <= dataRdIn;
            else
               dataRdOut <= (others => '0');
            end if;
         else
            dataRdOut <= (others => '0');
         end if;

         if colSel <= NUM_OF_COL_MANAGERS_C-1 then
            dataBusSel <= dataBusIn(conv_integer(unsigned(colSel)));
         else
            dataBusSel <= DEFAULT_PIX2PGP_DATABUS_C;
         end if;
      end process;
   end generate GEN_NO_PIPELINE_DATA;

   GEN_PIPELINE_STATUS : if (PIPELINE_STATUS_G = true) generate
      process(pgpClk)
      begin
         if (rising_edge(pgpClk)) then
            statusBusGlbl <= statusBusIn after TPD_G;
            statusRdOut   <= statusRdIn  after TPD_G;
            busyOut       <= busyIn      after TPD_G;

            if colSel <= NUM_OF_COL_MANAGERS_C-1 then
               statusBusSel <= statusBusIn(conv_integer(unsigned(colSel))) after TPD_G;
            end if;
         end if;
      end process;
   end generate GEN_PIPELINE_STATUS;

   GEN_PIPELINE_DATA : if (PIPELINE_DATA_G = true) generate
      process(pgpClk)
      begin
         if (rising_edge(pgpClk)) then
            if colSel <= NUM_OF_COL_MANAGERS_C-1 then
               dataBusSel <= dataBusIn(conv_integer(unsigned(colSel))) after TPD_G;
               dataRdOut(conv_integer(unsigned(colSel))) <= dataRdIn after TPD_G;
            end if;
         end if;
      end process;
   end generate GEN_PIPELINE_DATA;

end rtl;
