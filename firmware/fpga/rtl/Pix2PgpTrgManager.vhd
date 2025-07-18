-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp Trigger Management Logic
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

entity Pix2PgpTrgManager is
   generic(
      TPD_G                 : time    := 1 ns;
      RST_ASYNC_G           : boolean := false;
      RST_POLARITY_G        : sl      := '1';  -- '1' for active high rst, '0' for active low
      TRG_FIFO_ADDR_WIDTH_G : positive := 6);
   port(
      -- General Interface
      asicClk      : in  sl;
      asicRst      : in  sl := not(RST_POLARITY_G);
      pgpRxClk     : in  sl;
      pgpRxRst     : in  sl;
      -- ASIC Control Interface
      asicSro      : in  sl;
      asicSroEn    : in  sl;
      -- Lane Supervisor Interface
      trgBuffRd     : in  sl;
      trgBuffTrgCnt : out slv(TRGCNT_WIDTH_C-1 downto 0);
      trgBuffSroEn  : out sl;
      trgBuffValid  : out sl);
end Pix2PgpTrgManager;

architecture rtl of Pix2PgpTrgManager is

   constant TRGBUFF_WIDTH_C : natural := TRGCNT_WIDTH_C + 1; -- trigger-counter plus SroEn

   signal trgBuffDin  : slv(TRGBUFF_WIDTH_C-1 downto 0) := (others => '0');
   signal trgBuffDout : slv(TRGBUFF_WIDTH_C-1 downto 0) := (others => '0');

   type RegType is record
      asicSro    : sl;
      trgBuffWr  : sl;
      fpgaTrgCnt : slv(TRGCNT_WIDTH_C-1 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      asicSro    => '0',
      trgBuffWr  => '0',
      fpgaTrgCnt => (others => '1'));

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   comb : process (asicSro, asicRst, asicSroEn, r) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Register input
      v.asicSro := asicSro;

      -- posedge detection
      if v.asicSro = '1' and r.asicSro = '0' then
         v.fpgaTrgCnt := r.fpgaTrgCnt + 1;
      end if;

      -- negedge detection
      if v.asicSro = '0' and r.asicSro = '1' then
         v.trgBuffWr := '1';
      end if;

      trgBuffDin <= r.fpgaTrgCnt & asicSroEn;

      -- Reset
      if (RST_ASYNC_G = false and asicRst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   ----------------------------------------
   -- Trigger/SRO Buffer
   ----------------------------------------
   U_TriggerBuffer : entity surf.Fifo
      generic map (
         TPD_G           => TPD_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         GEN_SYNC_FIFO_G => false,
         MEMORY_TYPE_G   => "block",
         FWFT_EN_G       => true,
         DATA_WIDTH_G    => TRGBUFF_WIDTH_C,
         ADDR_WIDTH_G    => TRG_FIFO_ADDR_WIDTH_G)
      port map (
         rst      => asicRst,
         -- Write Ports
         wr_clk   => asicClk,
         wr_en    => r.trgBuffWr,
         din      => trgBuffDin,
         -- Read Ports
         rd_clk   => pgpRxClk,
         rd_en    => trgBuffRd,
         dout     => trgBuffDout,
         valid    => trgBuffValid);

   seq : process (asicClk, asicRst) is
   begin
      if (RST_ASYNC_G and asicRst = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(asicClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

   trgBuffTrgCnt <= trgBuffDout(TRGBUFF_WIDTH_C-1 downto 1);
   trgBuffSroEn  <= trgBuffDout(0);

end rtl;
