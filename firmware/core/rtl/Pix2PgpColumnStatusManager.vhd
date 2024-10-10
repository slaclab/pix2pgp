-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Depending on which column(s) is/are enabled, a reference
--              trigger has to be selected. This module performs that
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

entity Pix2PgpColumnStatusManager is
   generic(
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1');
   port(
      -- General Interface
      pgpClk        : in  sl;
      pgpRst        : in  sl := not(RST_POLARITY_G);
      columnEnable  : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- Column Manager Interface
      statusBusGlbl : in  Pix2PgpStatusBusArray;
      -- Column Supervisor Interface
      done          : out sl;
      columnIgnore  : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      refTrgNum     : out slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0));
end Pix2PgpColumnStatusManager;

architecture rtl of Pix2PgpColumnStatusManager is

   type StateType is (
      SCAN_ENABLE_S,
      WAIT_NEW_VALUE_S);

   type RegType is record
      -- i/o
      columnEnable    : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      done            : sl;
      columnIgnore    : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- internal
      columnEnablePrv : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colSel          : slv(BITMAX_COL_MANAGERS_C downto 0);
      state           : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- i/o
      columnEnable    => (others => '1'),
      done            => '0',
      columnIgnore    => (others => '0'),
      -- internal
      columnEnablePrv => (others => '1'),
      colSel          => (others => '0'),
      state           => SCAN_ENABLE_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   comb : process (r, pgpRst, statusBusGlbl, columnEnable) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Register inputs
      v.columnEnable := columnEnable;
      v.columnIgnore := not(r.columnEnable);

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- first go through the bitmask and find the first enabled column
         when SCAN_ENABLE_S =>
            v.done   := '0';
            v.colSel := r.colSel + 1;

            -- went through all bits; did not find any enabled column
            -- keep 'done' low to prevent supervisor from operating
            if conv_integer(unsigned(r.colSel)) = NUM_OF_COL_MANAGERS_C-1 then
               v.columnEnablePrv := r.columnEnable;
               v.state           := WAIT_NEW_VALUE_S;
            end if;

            -- found an enabled column; raise 'done'
            if r.columnEnable(conv_integer(unsigned(r.colSel))) = '1' then
               v.done            := '1';
               v.columnEnablePrv := r.columnEnable;
               v.state           := WAIT_NEW_VALUE_S;
            end if;

         -- trigger a fresh scanning cycle if a new value of enable is registered
         when WAIT_NEW_VALUE_S =>
            v.colSel := (others => '0');
            if (r.columnEnablePrv /= r.columnEnable) then
               v.state := SCAN_ENABLE_S;
            end if;

      end case;
      -------------------------------------------------------------------------

      -- Outputs
      -- (keep it combinatorial)
      done         <= v.done;
      columnIgnore <= v.columnIgnore;
      -- reference trigger number is associated with the first enabled column
      refTrgNum    <= statusBusGlbl(conv_integer(unsigned(r.colSel))).trgNum;

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
