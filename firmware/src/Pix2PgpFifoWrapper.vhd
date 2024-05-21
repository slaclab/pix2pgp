-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp FIFO Wrapper
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

library dware;
use dware.DWpackages.all;

entity Pix2PgpFifoWrapper is
   generic(
      TPD_G            : time    := 1 ns;
      RST_ASYNC_G      : boolean := false;
      RST_POLARITY_G   : sl      := '1';
      WR_DATA_WIDTH_G  : natural := 20;
      RD_DATA_WIDTH_G  : natural := 20;
      ADDR_WIDTH_G     : natural := 12;
      GEN_SYNC_FIFO_G  : boolean := false;
      GHDL_SIM_G       : boolean := false;
      SYNTHESIZE_G     : boolean := false);
   port(
      -- Resets
      rst   : in  sl;
      -- Write Interface
      wrClk : in  sl;
      wrEn  : in  sl;
      din   : in  slv(WR_DATA_WIDTH_G-1 downto 0);
      full  : out sl := '0';
      -- Read Interface
      rdClk : in  sl;
      rdEn  : in  sl;
      empty : out sl := '1';
      dout  : out slv(RD_DATA_WIDTH_G-1 downto 0));
end Pix2PgpFifoWrapper;

architecture rtl of Pix2PgpFifoWrapper is

begin

   STANDALONE_FLOW_GEN : if (GHDL_SIM_G = true) generate

      SYMM_GEN: if (WR_DATA_WIDTH_G = RD_DATA_WIDTH_G) generate
         U_StandaloneFifo : entity pix2pgp.Pix2PgpFifo
            generic map (
               TPD_G           => TPD_G,
               RST_ASYNC_G     => RST_ASYNC_G,
               RST_POLARITY_G  => RST_POLARITY_G,
               SYNTH_MODE_G    => "inferred",
               FWFT_EN_G       => False,
               GEN_SYNC_FIFO_G => GEN_SYNC_FIFO_G,
               DATA_WIDTH_G    => WR_DATA_WIDTH_G,
               ADDR_WIDTH_G    => ADDR_WIDTH_G)
            port map (
               rst    => rst,
               -- Write Interface
               wr_clk => wrClk,
               wr_en  => wrEn,
               din    => din,
               -- Read Interface
               rd_clk => rdClk,
               rd_en  => rdEn,
               empty  => empty,
               dout   => dout);
      end generate SYMM_GEN;

      ASYMM_GEN: if (WR_DATA_WIDTH_G /= RD_DATA_WIDTH_G) generate
         U_StandaloneFifo : entity pix2pgp.Pix2PgpFifoMux
            generic map (
               TPD_G           => TPD_G,
               RST_ASYNC_G     => RST_ASYNC_G,
               RST_POLARITY_G  => RST_POLARITY_G,
               SYNTH_MODE_G    => "inferred",
               FWFT_EN_G       => True, -- set to True since the data fifo is asymmetric
               GEN_SYNC_FIFO_G => GEN_SYNC_FIFO_G,
               WR_DATA_WIDTH_G => WR_DATA_WIDTH_G,
               RD_DATA_WIDTH_G => RD_DATA_WIDTH_G,
               ADDR_WIDTH_G    => ADDR_WIDTH_G)
            port map (
               rst    => rst,
               -- Write Interface
               wr_clk => wrClk,
               wr_en  => wrEn,
               din    => din,
               -- Read Interface
               rd_clk => rdClk,
               rd_en  => rdEn,
               empty  => empty,
               dout   => dout);
      end generate ASYMM_GEN;

   end generate STANDALONE_FLOW_GEN;

   ASIC_SIM_FLOW_GEN : if (GHDL_SIM_G = false and SYNTHESIZE_G = false) generate

      -- vendor proprietary fifo placeholder
      -- remove this once you place the vendor FIFO
      assert (GHDL_SIM_G = false)
      report "[ERROR]: No vendor proprietary FIFO simulation behavioral model implemented yet!"
      severity failure;

   end generate ASIC_SIM_FLOW_GEN;

   ASIC_SYNTH_FLOW_GEN : if (SYNTHESIZE_G = true) generate

      -- vendor proprietary fifo placeholder
      -- remove this once you place the vendor FIFO
      assert (GHDL_SIM_G = false)
      report "[ERROR]: No vendor proprietary FIFO behavioral model implemented yet!"
      severity failure;

   end generate ASIC_SYNTH_FLOW_GEN;

end rtl;
