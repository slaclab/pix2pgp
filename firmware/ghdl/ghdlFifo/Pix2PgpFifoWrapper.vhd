-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp FIFO Wrapper for GHDL use
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

entity Pix2PgpFifoWrapper is
   generic(
      TPD_G            : time    := 1 ns;
      RST_ASYNC_G      : boolean := false;
      RST_POLARITY_G   : sl      := '1';
      WR_DATA_WIDTH_G  : integer := 20;
      RD_DATA_WIDTH_G  : integer := 20;
      FULL_THRES_G     : integer := 6;
      ADDR_WIDTH_G     : integer := 12;
      DWARE_DEPTH_G    : integer := 32;
      DWARE_AF_LVL_G   : integer := 2;
      PIPE_STAGES_G    : natural := 0;
      FWFT_EN_G        : boolean := false;
      GEN_SYNC_FIFO_G  : boolean := false); -- 'false' generates a Clock-Domain-Crossing FIFO
   port(
      -- Resets
      rst      : in  sl;
      -- Write Interface
      wrClk    : in  sl;
      wrEn     : in  sl;
      din      : in  slv(WR_DATA_WIDTH_G-1 downto 0);
      aFullWr  : out sl;
      aEmptyWr : out sl;
      fullWr   : out sl := '0';
      emptyWr  : out sl := '0';
      -- Read Interface
      rdClk    : in  sl;
      rdEn     : in  sl;
      emptyRd  : out sl := '1';
      fullRd   : out sl;
      rdErr    : out sl;
      dout     : out slv(RD_DATA_WIDTH_G-1 downto 0));
end Pix2PgpFifoWrapper;

architecture rtl of Pix2PgpFifoWrapper is

   signal fullWrStandalone  : sl := '0';
   signal validRdStandalone : sl := '0';
   signal validWr           : sl := '0';

begin

   SYMM_GEN: if (WR_DATA_WIDTH_G = RD_DATA_WIDTH_G) generate
      U_StandaloneFifo : entity pix2pgp.Pix2PgpFifo
         generic map (
            TPD_G           => TPD_G,
            RST_ASYNC_G     => RST_ASYNC_G,
            RST_POLARITY_G  => RST_POLARITY_G,
            SYNTH_MODE_G    => "inferred",
            FWFT_EN_G       => FWFT_EN_G,
            GEN_SYNC_FIFO_G => GEN_SYNC_FIFO_G,
            PIPE_STAGES_G   => PIPE_STAGES_G,
            DATA_WIDTH_G    => WR_DATA_WIDTH_G,
            FULL_THRES_G    => FULL_THRES_G,
            ADDR_WIDTH_G    => ADDR_WIDTH_G)
         port map (
            rst       => rst,
            -- Write Interface
            wr_clk    => wrClk,
            wr_en     => wrEn,
            din       => din,
            prog_full => aFullWr,
            full      => fullWrStandalone,
            -- Read Interface
            rd_clk    => rdClk,
            rd_en     => rdEn,
            valid     => validRdStandalone,
            underflow => rdErr,
            dout      => dout);
   end generate SYMM_GEN;

   ASYMM_GEN: if (WR_DATA_WIDTH_G /= RD_DATA_WIDTH_G) generate
      U_StandaloneFifo : entity pix2pgp.Pix2PgpFifoMux
         generic map (
            TPD_G           => TPD_G,
            RST_ASYNC_G     => RST_ASYNC_G,
            RST_POLARITY_G  => RST_POLARITY_G,
            SYNTH_MODE_G    => "inferred",
            FWFT_EN_G       => FWFT_EN_G,
            GEN_SYNC_FIFO_G => GEN_SYNC_FIFO_G,
            PIPE_STAGES_G   => PIPE_STAGES_G,
            WR_DATA_WIDTH_G => WR_DATA_WIDTH_G,
            RD_DATA_WIDTH_G => RD_DATA_WIDTH_G,
            FULL_THRES_G    => FULL_THRES_G,
            ADDR_WIDTH_G    => ADDR_WIDTH_G)
         port map (
            rst       => rst,
            -- Write Interface
            wr_clk    => wrClk,
            wr_en     => wrEn,
            din       => din,
            prog_full => aFullWr,
            full      => fullWrStandalone,
            -- Read Interface
            rd_clk    => rdClk,
            rd_en     => rdEn,
            valid     => validRdStandalone,
            underflow => rdErr,
            dout      => dout);
   end generate ASYMM_GEN;

   U_syncFull : entity surf.Synchronizer
      generic map (
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         RST_POLARITY_G => RST_POLARITY_G,
         STAGES_G       => 2)
      port map (
         clk     => rdClk,
         rst     => rst,
         dataIn  => fullWrStandalone,
         dataOut => fullRd);

   U_syncEmpty : entity surf.Synchronizer
      generic map (
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         RST_POLARITY_G => RST_POLARITY_G,
         STAGES_G       => 2)
      port map (
         clk     => wrClk,
         rst     => rst,
         dataIn  => validRdStandalone,
         dataOut => validWr);

   aEmptyWr <= not(validWr); -- not really used in ghdl-based FIFOs
   emptyWr  <= not(validWr);
   emptyRd  <= not(validRdStandalone);
   fullWr   <= fullWrStandalone;

end rtl;
