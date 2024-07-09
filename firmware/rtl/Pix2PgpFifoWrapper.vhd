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

library dw06;
use dw06.dw06_components.all;

entity Pix2PgpFifoWrapper is
   generic(
      TPD_G            : time    := 1 ns;
      RST_ASYNC_G      : boolean := false;
      RST_POLARITY_G   : sl      := '1';
      WR_DATA_WIDTH_G  : integer := 20;
      RD_DATA_WIDTH_G  : integer := 20;
      ADDR_WIDTH_G     : integer := 12;
      DWARE_DEPTH_G    : integer := 32;
      DWARE_AF_LVL_G   : integer := 2;
      PIPE_STAGES_G    : natural := 0;
      FWFT_EN_G        : boolean := false;
      GEN_SYNC_FIFO_G  : boolean := false;
      GHDL_SIM_G       : boolean := false;
      SYNTHESIZE_G     : boolean := false);
   port(
      -- Resets
      rst     : in  sl;
      enable  : in  sl;
      -- Write Interface
      wrClk   : in  sl;
      wrEn    : in  sl;
      din     : in  slv(WR_DATA_WIDTH_G-1 downto 0);
      aFullWr : out sl;
      fullWr  : out sl := '0';
      emptyWr : out sl := '0';
      -- Read Interface
      rdClk   : in  sl;
      rdEn    : in  sl;
      emptyRd : out sl := '1';
      fullRd  : out sl;
      dout    : out slv(RD_DATA_WIDTH_G-1 downto 0));
end Pix2PgpFifoWrapper;

architecture rtl of Pix2PgpFifoWrapper is

   signal rstDwareFifo      : sl := '0';
   signal wrEnDwareFifo     : sl := '0';
   signal rdEnDwareFifo     : sl := '0';
   signal fullWrStandalone  : sl := '0';
   signal emptyRdStandalone : sl := '0';
   signal rstFifo           : sl := '0';

begin

   rstFifo <= (rst or not(enable)) when RST_POLARITY_G = '1' else (not(rst) or enable);

   GHDL_SIM_FLOW_GEN : if (GHDL_SIM_G = true) generate

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
               FULL_THRES_G    => DWARE_AF_LVL_G,
               ADDR_WIDTH_G    => ADDR_WIDTH_G)
            port map (
               rst       => rstFifo,
               -- Write Interface
               wr_clk    => wrClk,
               wr_en     => wrEn,
               din       => din,
               prog_full => aFullWr,
               full      => fullWrStandalone,
               -- Read Interface
               rd_clk    => rdClk,
               rd_en     => rdEn,
               empty     => emptyRdStandalone,
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
               FULL_THRES_G    => DWARE_AF_LVL_G,
               ADDR_WIDTH_G    => ADDR_WIDTH_G)
            port map (
               rst       => rstFifo,
               -- Write Interface
               wr_clk    => wrClk,
               wr_en     => wrEn,
               din       => din,
               prog_full => aFullWr,
               full      => fullWrStandalone,
               -- Read Interface
               rd_clk    => rdClk,
               rd_en     => rdEn,
               empty     => emptyRdStandalone,
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
            dataIn  => emptyRdStandalone,
            dataOut => emptyWr);

      fullWr  <= fullWrStandalone;
      emptyRd <= emptyRdStandalone;

   end generate GHDL_SIM_FLOW_GEN;

   ASIC_FLOW_GEN : if (GHDL_SIM_G = false) generate
      wrEnDwareFifo <= not(wrEn);
      rdEnDwareFifo <= not(rdEn);
      rstDwareFifo  <= not(rstFifo);

      SYMM_GEN: if (WR_DATA_WIDTH_G = RD_DATA_WIDTH_G) generate
         U_designwareFifo : entity dw06.DW_fifo_s2_sf
            generic map (
               width       => WR_DATA_WIDTH_G,
               depth       => DWARE_DEPTH_G,
               push_af_lvl => DWARE_AF_LVL_G,
               pop_af_lvl  => DWARE_AF_LVL_G,
               rst_mode    => 2)
            port map (
               rst_n      => rstDwareFifo,
               -- Write Interface
               clk_push   => wrClk,
               push_req_n => wrEnDwareFifo,
               data_in    => din,
               push_af    => aFullWr,
               push_full  => fullWr,
               push_empty => emptyWr,
               -- Read Interface
               clk_pop    => rdClk,
               pop_req_n  => rdEnDwareFifo,
               pop_empty  => emptyRd,
               pop_full   => fullRd,
               data_out   => dout);
      end generate SYMM_GEN;

      ASYMM_GEN: if (WR_DATA_WIDTH_G /= RD_DATA_WIDTH_G) generate
         U_designwareFifo : entity dw06.DW_asymfifo_s2_sf
            generic map (
               data_in_width  => WR_DATA_WIDTH_G,
               data_out_width => RD_DATA_WIDTH_G,
               depth          => DWARE_DEPTH_G,
               push_af_lvl    => DWARE_AF_LVL_G,
               pop_af_lvl     => DWARE_AF_LVL_G,
               rst_mode       => 2)
            port map (
               rst_n      => rstDwareFifo,
               flush_n    => rstDwareFifo,
               -- Write Interface
               clk_push   => wrClk,
               push_req_n => wrEnDwareFifo,
               data_in    => din,
               push_af    => aFullWr,
               push_full  => fullWr,
               push_empty => emptyWr,
               -- Read Interface
               clk_pop    => rdClk,
               pop_req_n  => rdEnDwareFifo,
               pop_empty  => emptyRd,
               pop_full   => fullRd,
               data_out   => dout);
      end generate ASYMM_GEN;

   end generate ASIC_FLOW_GEN;

end rtl;
