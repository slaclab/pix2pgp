-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Simple watchdog circuit
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
use pix2pgp.Pix2PgpAsicPkg.all;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpWatchdog is
   generic(
      TPD_G          : time      := 1 ns;
      RST_ASYNC_G    : boolean   := false;
      RST_POLARITY_G : std_logic := '1';
      CNT_WIDTH_G    : positive  := 12);
   port(
      -- General Interface
      clk     : in  sl;
      rst     : in  sl;
      limit   : in  slv(CNT_WIDTH_G-1 downto 0);
      -- Control Interface
      set     : in  sl;
      timeout : out sl);
end Pix2PgpWatchdog;

architecture rtl of Pix2PgpWatchdog is

   type RegType is record
      cnt     : slv(CNT_WIDTH_G-1 downto 0);
      timeout : sl;
   end record RegType;

   constant REG_INIT_C : RegType := (
      cnt     => (others => '0'),
      timeout => '0');

   signal r   : RegType;
   signal rin : RegType;

begin

   comb : process (r, rst, set, limit) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      if (set = '1' and uOr(limit) = '1') then
         if r.cnt = limit then
            -- stay in this state until rst or set=low
            v.timeout := '1';
         else
            v.cnt := r.cnt + 1;
         end if;
      else
         v.timeout := '0';
         v.cnt     := (others => '0');
      end if;

      -- Outputs
      timeout <= v.timeout;

      -- Reset
      if (RST_ASYNC_G = false and rst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (clk, rst) is
   begin
      if (RST_ASYNC_G and rst = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(clk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

end rtl;
