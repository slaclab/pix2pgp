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
use pix2pgp.Pix2PgpAsicPkg.all;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpTriggerManager is
   generic(
      TPD_G                 : time     := 1 ns;
      RST_ASYNC_G           : boolean  := false;
      ASIC_RST_POLARITY_G   : sl       := '1';  -- '1' for active high rst, '0' for active low
      LOGIC_RST_POLARITY_G  : sl       := '1';  -- '1' for active high rst, '0' for active low
      TRG_FIFO_ADDR_WIDTH_G : positive := 6);
   port(
      -- General Interface
      asicClk       : in  sl;
      asicRst       : in  sl := not(ASIC_RST_POLARITY_G);
      pgpRxClk      : in  sl;
      pgpRxRst      : in  sl := not(LOGIC_RST_POLARITY_G);
      config        : in  Pix2PgpStreamRxConfigType;
      -- ASIC Control Interface
      asicSro       : in  sl;
      asicSroEn     : in  sl;
      sysDaq        : in  sl;
      -- Lane Supervisor Interface
      trgBuffRd     : in  sl;
      trgBuffTrgCnt : out slv(TRGCNT_WIDTH_C-1 downto 0);
      trgBuffSroEn  : out sl;
      trgBuffSysDaq : out sl;
      trgBuffValid  : out sl);
end Pix2PgpTriggerManager;

architecture rtl of Pix2PgpTriggerManager is

   constant TRGBUFF_WIDTH_C : natural := TRGCNT_WIDTH_C + 2; -- trigger-counter plus SroEn, sysDaq

   signal trgBuffDin    : slv(TRGBUFF_WIDTH_C-1 downto 0) := (others => '0');
   signal trgBuffDout   : slv(TRGBUFF_WIDTH_C-1 downto 0) := (others => '0');

   signal fifoRst       : sl := not(LOGIC_RST_POLARITY_G);

   signal rstFpgaTrgCnt : sl := '0';
   signal incrSroEnLow  : sl := '0';

   type RegType is record
      asicSro    : sl;
      sysDaq     : sl;
      trgBuffDaq : sl;
      trgBuffWr  : sl;
      fpgaTrgCnt : slv(TRGCNT_WIDTH_C-1 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      asicSro    => '0',
      sysDaq     => '0',
      trgBuffDaq => '0',
      trgBuffWr  => '0',
      fpgaTrgCnt => (others => '1'));

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   -------------------------------------------------------------------------------------------------
   -------------------------------------------------------------------------------------------------
   comb : process (asicSro, asicRst, asicSroEn, rstFpgaTrgCnt, sysDaq, incrSroEnLow, r) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Register input
      v.asicSro := asicSro;

      -- Defaults
      v.trgBuffWr  := '0';
      v.trgBuffDaq := '0';
      v.sysDaq     := sysDaq;

      -- posedge detection
      if v.asicSro = '1' and r.asicSro = '0' then

         if asicSroEn = '1' then
            v.fpgaTrgCnt := r.fpgaTrgCnt + 1;
         end if;

         if asicSroEn = '0' and incrSroEnLow = '1' then
            v.fpgaTrgCnt := r.fpgaTrgCnt + 1;
         end if;

      end if;

      -- negedge detection
      if v.asicSro = '0' and r.asicSro = '1' then
         v.trgBuffWr := '1';

         -- daq and sro signals should be identical;
         -- otherwise no data are forwarded downstream
         if v.sysDaq = '0' and r.sysDaq = '1' then
            v.trgBuffDaq := '1';
         end if;

      end if;

      trgBuffDin <= r.fpgaTrgCnt & asicSroEn & r.trgBuffDaq;

      -- Trigger Counter-only reset
      if rstFpgaTrgCnt = '1' then
         v.fpgaTrgCnt := (others => '1');
      end if;

      -- Reset
      if (RST_ASYNC_G = false and asicRst = ASIC_RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (asicClk, asicRst) is
   begin
      if (RST_ASYNC_G and asicRst = ASIC_RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(asicClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;
   -------------------------------------------------------------------------------------------------
   -------------------------------------------------------------------------------------------------

   U_SyncRst : entity surf.Synchronizer
      generic map (
         TPD_G   => TPD_G)
      port map (
         clk     => asicClk,
         dataIn  => pgpRxRst,
         dataOut => fifoRst);

   U_SyncRstFpgaTrgCnt : entity surf.Synchronizer
      generic map (
         TPD_G   => TPD_G)
      port map (
         clk     => asicClk,
         dataIn  => config.rstFpgaTrgCnt,
         dataOut => rstFpgaTrgCnt);

   U_SyncIncrSroEnLow : entity surf.Synchronizer
      generic map (
         TPD_G   => TPD_G)
      port map (
         clk     => asicClk,
         dataIn  => config.incrSroEnLow,
         dataOut => incrSroEnLow);

   ----------------------------------------
   -- Trigger/SRO Buffer
   ----------------------------------------
   U_TriggerBuffer : entity surf.Fifo
      generic map (
         TPD_G           => TPD_G,
         RST_POLARITY_G  => LOGIC_RST_POLARITY_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         GEN_SYNC_FIFO_G => false,
         MEMORY_TYPE_G   => "block",
         FWFT_EN_G       => true,
         DATA_WIDTH_G    => TRGBUFF_WIDTH_C,
         ADDR_WIDTH_G    => TRG_FIFO_ADDR_WIDTH_G)
      port map (
         rst      => fifoRst,
         -- Write Ports
         wr_clk   => asicClk,
         wr_en    => r.trgBuffWr,
         din      => trgBuffDin,
         -- Read Ports
         rd_clk   => pgpRxClk,
         rd_en    => trgBuffRd,
         dout     => trgBuffDout,
         valid    => trgBuffValid);

   trgBuffTrgCnt <= trgBuffDout(TRGBUFF_WIDTH_C-1 downto 2);
   trgBuffSroEn  <= trgBuffDout(1);
   trgBuffSysDaq <= trgBuffDout(0);

end rtl;
