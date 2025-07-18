-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp Lane Merging Logic
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
use surf.AxiStreamPkg.all;
use surf.SsiPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpLaneMerger is
   generic(
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1';  -- '1' for active high rst, '0' for active low
      DELAY_G        : natural := 1);
   port(
      -- General Interface
      pgpRxClk     : in  sl;
      pgpRxRst     : in  sl := not(RST_POLARITY_G);
      clk   : in  sl;
      rst   : in  sl := not(RST_POLARITY_G);
      start : in  sl;
      done  : out sl;
      dout  : out slv(7 downto 0));
end Pix2PgpLaneMerger;

architecture rtl of Pix2PgpLaneMerger is

   type StateType is (
      IDLE_S,
      COUNT_S);

   type RegType is record
      cnt   : slv(7 downto 0);
      go    : sl;
      start : sl;
      done  : sl;
      state : stateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      cnt   => (others => '0'),
      go    => '0',
      start => '0',
      done  => '0',
      state => IDLE_S
   );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   comb : process (start, r, rst) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Register input
      v.start := start;

      -- Default values
      v.go   := '0';
      v.done := '0';

      -- rising-edge detection of start
      if v.start = '1' and r.start = '0' then
         v.go := '1';
      end if;

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- wait for 'go' signal
         when IDLE_S =>
            if r.go = '1' then
               v.state := COUNT_S;
            end if;

         ----------------------------------------------------------------------
         -- start counting until all bits are high
         when COUNT_S =>
            v.cnt := r.cnt + 1;

            -- using StdRtlPkg function
            if uAnd(r.cnt) = '1' then
               v.done  := '1';
               v.state := IDLE_S;
            end if;

      end case;
      -----------------------------------------------------------------------

      dout <= r.cnt;

      -- Reset
      if (RST_ASYNC_G = false and rst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   U_delayDone : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => DELAY_G)
      port map (
         clk     => clk,
         din(0)  => r.done,
         dout(0) => done);

   seq : process (clk, rst) is
   begin
      if (RST_ASYNC_G and rst = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(clk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

end rtl;
