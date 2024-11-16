-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Adapter for PGP. Temporarily stores data into a FIFO;
--              checks the status of the 'txReady' from the PGP interface;
--              asserts valid, sof, eof accordingly
--
-- Important!   The frame size is fixed to 5x64-bit words (320 bits);
--              The arbiter monitors the amount of 40-bit words sent to the
--              40:64 gearbox. 8x40-bit words (*also* 320 bits)
--              should be written into the gearbox to keep things in check;
--              if a smaller amount of 40-bit words is written and a timeout
--              is reached, the arbiter stuffs the gearbox with dummy headers;
--              this functionality allows for the last data to be TX'd
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

entity Pix2PgpAdapter is
   generic(
      TPD_G           : time     := 1 ns;
      RST_ASYNC_G     : boolean  := false;
      RST_POLARITY_G  : sl       := '1';
      DWARE_DEPTH_G   : integer  := 12;
      DWARE_AF_LVL_G  : integer  := 3);
   port(
      -- General Interface
      pgpClk   : in  sl;
      pgpRst   : in  sl := not(RST_POLARITY_G);
      -- Gearbox Interface
      pgpValid : in  sl;
      pgpData  : in  slv(PGP_DWIDTH_C-1 downto 0);
      pgpReady : out sl;
      -- Pgp4TxLite Interface
      txReady  : in   sl;
      txValid  : out  sl;
      txData   : out  slv(PGP_DWIDTH_C-1 downto 0);
      txSof    : out  sl;
      txEof    : out  sl;
      txEofe   : out  sl);
end Pix2PgpAdapter;

architecture rtl of Pix2PgpAdapter is

   type RegType is record
      -- i/o
      txReady  : sl;
      txValid  : sl;
      txSof    : sl;
      txEof    : sl;
      pgpReady : sl;
      pgpValid : sl;
      txData   : slv(PGP_DWIDTH_C-1 downto 0);
      pgpData  : slv(PGP_DWIDTH_C-1 downto 0);
      -- internal
      fifoRdEn : sl;
      frameCnt : slv(2 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- i/o
      txReady  => '0',
      txValid  => '0',
      txSof    => '0',
      txEof    => '0',
      pgpReady => '0',
      pgpValid => '0',
      txData   => (others => '0'),
      pgpData  => (others => '0'),
      -- internal
      fifoRdEn => '0',
      frameCnt => (others => '0'));

   signal fifoEmpty : sl      := '0';
   signal fifoRdEn  : sl      := '0';
   signal pgpFull   : sl      := '0';
   signal pgpAFull  : sl      := '0';
   signal r         : RegType := REG_INIT_C;
   signal rin       : RegType;

begin

   ------------------------------------------------
   -- Adapter FSM
   ------------------------------------------------
   comb : process (r, pgpRst, fifoEmpty, txReady, pgpValid, pgpData) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- inputs
      v.pgpData  := pgpData;
      v.pgpValid := pgpValid;
      v.txReady  := txReady;
      v.txData   := v.pgpData;

      -- defaults
      v.pgpReady := '1'; -- ready to grab the data
      v.txSof    := '1';
      v.txEof    := '0';

      if r.frameCnt > 0 then
         v.txSof := '0';
      end if;

      if r.frameCnt = 4 then
         v.txEof   := '1';
      end if;

      if v.pgpValid = '1' then
         v.pgpReady := '0'; -- stop receiving data
         v.txValid  := '1'; -- go up and stay that way
      end if;

      if r.txValid = '1' then
         v.pgpReady := '0'; -- stay down to block slave
         if v.txReady = '1' then
            v.pgpReady := '1'; -- ready to grab the data again
            v.frameCnt := r.frameCnt + 1;
            v.txValid  := '0'; -- drop the valid
         end if;
      end if;

      -- Outputs
      txData   <= v.txData;
      pgpReady <= v.pgpReady;
      txValid  <= r.txValid;
      txSof    <= v.txSof;
      txEof    <= v.txEof;
      txEofe   <= '0';

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
