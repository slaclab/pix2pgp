-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp Trigger Management Logic
--
-- Buffers Start-Of-Readout (SRO) triggers along with their coupled
-- fpga-trigger-counter value and DAQ flag, so the Lane Supervisor can drive
-- the receiver in lock-step with the ASIC-facing trigger stream.
--
-- For ASICs that rely on an external End-Of-Readout (ERO) trigger to close-out
-- their events (EN_ERO_C = True in Pix2PgpAsicPkg), a second FIFO is
-- instantiated to buffer ERO strobes alongside the fpga-trigger-counter value
-- of the SRO they close. The Lane Supervisor uses these entries to for event
-- close-out (see Pix2PgpLaneSupervisor).
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
      asicEro       : in  sl := '0'; -- unused when EN_ERO_C = False
      sysDaq        : in  sl;
      -- Lane Supervisor Interface (SRO buffer)
      sroBuffRd     : in  sl;
      sroBuffTrgCnt : out slv(TRGCNT_WIDTH_C-1 downto 0);
      sroBuffSroEn  : out sl;
      sroBuffSysDaq : out sl;
      sroBuffValid  : out sl;
      -- Lane Supervisor Interface (ERO buffer, only meaningful when EN_ERO_C)
      eroBuffRd     : in  sl := '0';
      eroBuffTrgCnt : out slv(TRGCNT_WIDTH_C-1 downto 0);
      eroBuffValid  : out sl);
end Pix2PgpTriggerManager;

architecture rtl of Pix2PgpTriggerManager is

   constant SROBUFF_WIDTH_C : natural := TRGCNT_WIDTH_C + 2; -- trigger-counter plus SroEn, sysDaq
   constant EROBUFF_WIDTH_C : natural := TRGCNT_WIDTH_C;     -- trigger-counter of the closing SRO

   signal sroBuffDin    : slv(SROBUFF_WIDTH_C-1 downto 0) := (others => '0');
   signal sroBuffDout   : slv(SROBUFF_WIDTH_C-1 downto 0) := (others => '0');

   signal eroBuffDin    : slv(EROBUFF_WIDTH_C-1 downto 0) := (others => '0');
   signal eroBuffDout   : slv(EROBUFF_WIDTH_C-1 downto 0) := (others => '0');

   signal asicRxRst     : sl := not(LOGIC_RST_POLARITY_G);
   signal fifoRst       : sl := not(LOGIC_RST_POLARITY_G);
   signal cfgRst        : sl := '0';

   signal rstFpgaTrgCnt : sl := '0';
   signal incrSroEnLow  : sl := '0';

   type RegType is record
      asicSro    : sl;
      asicEro    : sl;
      sysDaq     : sl;
      sroBuffDaq : sl;
      sroBuffWr  : sl;
      eroBuffWr  : sl;
      fpgaTrgCnt : slv(TRGCNT_WIDTH_C-1 downto 0);
      eroTrgCnt  : slv(TRGCNT_WIDTH_C-1 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      asicSro    => '0',
      asicEro    => '0',
      sysDaq     => '0',
      sroBuffDaq => '0',
      sroBuffWr  => '0',
      eroBuffWr  => '0',
      fpgaTrgCnt => (others => '1'),
      eroTrgCnt  => (others => '1'));

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   -------------------------------------------------------------------------------------------------
   -------------------------------------------------------------------------------------------------
   comb : process (asicSro, asicEro, asicRst, cfgRst, asicSroEn, rstFpgaTrgCnt, sysDaq,
                   incrSroEnLow, r) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Register inputs
      v.asicSro := asicSro;
      v.asicEro := asicEro;

      -- Defaults
      v.sroBuffWr  := '0';
      v.eroBuffWr  := '0';
      v.sroBuffDaq := '0';
      v.sysDaq     := sysDaq;

      -----------------
      -- SRO management
      -----------------
      -- SRO posedge detection
      if v.asicSro = '1' and r.asicSro = '0' then

         if asicSroEn = '1' or (asicSroEn = '0' and incrSroEnLow = '1') then
            v.fpgaTrgCnt := r.fpgaTrgCnt + 1;
         end if;

      end if;

      -- SRO negedge detection
      if v.asicSro = '0' and r.asicSro = '1' then
         v.sroBuffWr := '1';

         -- daq should be high while sro is toggling;
         -- otherwise no data are forwarded downstream
         if r.sysDaq = '1' then
            v.sroBuffDaq := '1';
         end if;

      end if;

      -----------------
      -- ERO management
      -----------------
      -- ERO posedge detection;
      -- note that it is assumed that the sequence SRO->ERO->SRO->... is never broken
      -- (it is the external trigger logic's responsibility to retain this)
      if v.asicEro = '1' and r.asicEro = '0' and EN_ERO_C then
         v.eroTrgCnt := r.fpgaTrgCnt;
      end if;

      -- ERO negedge detection
      if v.asicEro = '0' and r.asicEro = '1' and EN_ERO_C then
         v.eroBuffWr := '1';
      end if;

      -- Trigger Counter-only reset
      if rstFpgaTrgCnt = '1' then
         v.fpgaTrgCnt := (others => '1');
         v.eroTrgCnt  := (others => '1');
      end if;

      -- Reset
      if (RST_ASYNC_G = false and (asicRst = ASIC_RST_POLARITY_G or cfgRst = '1')) then
         v := REG_INIT_C;
      end if;

      -- Outputs
      sroBuffDin <= r.fpgaTrgCnt & asicSroEn & r.sroBuffDaq;
      eroBuffDin <= r.eroTrgCnt;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (asicClk, asicRst, cfgRst) is
   begin
      if (RST_ASYNC_G and (asicRst = ASIC_RST_POLARITY_G or cfgRst = '1')) then
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
         dataOut => asicRxRst);

   U_SyncCfgRst : entity surf.Synchronizer
      generic map (
         TPD_G   => TPD_G)
      port map (
         clk     => asicClk,
         dataIn  => config.triggerless,
         dataOut => cfgRst);

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
   -- SRO Buffer
   ----------------------------------------
   U_SroBuffer : entity surf.Fifo
      generic map (
         TPD_G           => TPD_G,
         RST_POLARITY_G  => LOGIC_RST_POLARITY_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         GEN_SYNC_FIFO_G => false,
         MEMORY_TYPE_G   => "block",
         FWFT_EN_G       => true,
         DATA_WIDTH_G    => SROBUFF_WIDTH_C,
         ADDR_WIDTH_G    => TRG_FIFO_ADDR_WIDTH_G)
      port map (
         rst      => fifoRst,
         -- Write Ports
         wr_clk   => asicClk,
         wr_en    => r.sroBuffWr,
         din      => sroBuffDin,
         -- Read Ports
         rd_clk   => pgpRxClk,
         rd_en    => sroBuffRd,
         dout     => sroBuffDout,
         valid    => sroBuffValid);

   sroBuffTrgCnt <= sroBuffDout(SROBUFF_WIDTH_C-1 downto 2);
   sroBuffSroEn  <= sroBuffDout(1);
   sroBuffSysDaq <= sroBuffDout(0);

   ----------------------------------------
   -- ERO Buffer (selective)
   ----------------------------------------
   GEN_ERO : if EN_ERO_C generate

      U_EroBuffer : entity surf.Fifo
         generic map (
            TPD_G           => TPD_G,
            RST_POLARITY_G  => LOGIC_RST_POLARITY_G,
            RST_ASYNC_G     => RST_ASYNC_G,
            GEN_SYNC_FIFO_G => false,
            MEMORY_TYPE_G   => "block",
            FWFT_EN_G       => true,
            DATA_WIDTH_G    => EROBUFF_WIDTH_C,
            ADDR_WIDTH_G    => TRG_FIFO_ADDR_WIDTH_G)
         port map (
            rst      => fifoRst,
            -- Write Ports
            wr_clk   => asicClk,
            wr_en    => r.eroBuffWr,
            din      => eroBuffDin,
            -- Read Ports
            rd_clk   => pgpRxClk,
            rd_en    => eroBuffRd,
            dout     => eroBuffDout,
            valid    => eroBuffValid);

      eroBuffTrgCnt <= eroBuffDout;

   end generate GEN_ERO;

   fifoRst <= ite(toBoolean(LOGIC_RST_POLARITY_G),
                 (asicRxRst or cfgRst),
                 (asicRxRst and not(cfgRst)));

   GEN_NO_ERO : if not EN_ERO_C generate
      eroBuffTrgCnt <= (others => '0');
      eroBuffValid  <= '0';
   end generate GEN_NO_ERO;

end rtl;
