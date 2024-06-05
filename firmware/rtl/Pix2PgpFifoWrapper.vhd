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

entity Pix2PgpFifoWrapper is
   generic(
      TPD_G            : time    := 1 ns;
      RST_ASYNC_G      : boolean := false;
      RST_POLARITY_G   : sl      := '1';
      WR_DATA_WIDTH_G  : integer := 20;
      RD_DATA_WIDTH_G  : integer := 20;
      ADDR_WIDTH_G     : integer := 12;
      DWARE_DEPTH_G    : integer := 32;
      PIPE_STAGES_G    : natural := 0;
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

      signal rstDwareFifo  : sl := '0';
      signal wrEnDwareFifo : sl := '0';
      signal rdEnDwareFifo : sl := '0';

      signal fullWrDomain  : sl := '0';

   component DW_asymfifo_s2_sf is
      generic(
         data_in_width  : INTEGER  ;
         data_out_width : INTEGER  ;
         depth : INTEGER  := 8;
         push_ae_lvl : INTEGER  := 2;
         push_af_lvl : INTEGER  := 2;
         pop_ae_lvl : INTEGER  := 2;
         pop_af_lvl : INTEGER  := 2;
         err_mode : INTEGER  := 0;
         push_sync : INTEGER  := 2;
         pop_sync : INTEGER  := 2;
         rst_mode : INTEGER  := 1;
         byte_order : INTEGER  := 0);
      port(
         clk_push : in std_logic;
         clk_pop : in std_logic;
         rst_n : in std_logic;
         push_req_n : in std_logic;
         flush_n : in std_logic;
         pop_req_n : in std_logic;
         data_in : in std_logic_vector(data_in_width-1 downto 0);
         push_empty : out std_logic;
         push_ae : out std_logic;
         push_hf : out std_logic;
         push_af : out std_logic;
         push_full : out std_logic;
         ram_full : out std_logic;
         part_wd : out std_logic;
         push_error : out std_logic;
         pop_empty : out std_logic;
         pop_ae : out std_logic;
         pop_hf : out std_logic;
         pop_af : out std_logic;
         pop_full : out std_logic;
         pop_error : out std_logic;
         data_out : out std_logic_vector(data_out_width-1 downto 0 )
      );
   end component;

   component DW_fifo_s2_sf
      generic (
         width : INTEGER  := 8;
         depth : INTEGER  := 8;
         push_ae_lvl : INTEGER  := 2;
         push_af_lvl : INTEGER  := 2;
         pop_ae_lvl : INTEGER  := 2;
         pop_af_lvl : INTEGER  := 2;
         err_mode : INTEGER  := 0;
         push_sync : INTEGER  := 2;
         pop_sync : INTEGER  := 2;
         rst_mode : INTEGER  := 0);
      port(
         clk_push : in std_logic;
         clk_pop : in std_logic;
         rst_n : in std_logic;
         push_req_n : in std_logic;
         pop_req_n : in std_logic;
         data_in : in std_logic_vector(width-1 downto 0);
         push_empty : out std_logic;
         push_ae : out std_logic;
         push_hf : out std_logic;
         push_af : out std_logic;
         push_full : out std_logic;
         push_error : out std_logic;
         pop_empty : out std_logic;
         pop_ae : out std_logic;
         pop_hf : out std_logic;
         pop_af : out std_logic;
         pop_full : out std_logic;
         pop_error : out std_logic;
         data_out : out std_logic_vector( width-1 downto 0 ));
end component;

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
               PIPE_STAGES_G   => PIPE_STAGES_G,
               DATA_WIDTH_G    => WR_DATA_WIDTH_G,
               ADDR_WIDTH_G    => ADDR_WIDTH_G)
            port map (
               rst    => rst,
               -- Write Interface
               wr_clk => wrClk,
               wr_en  => wrEn,
               din    => din,
               full   => fullWrDomain,
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
               PIPE_STAGES_G   => PIPE_STAGES_G,
               WR_DATA_WIDTH_G => WR_DATA_WIDTH_G,
               RD_DATA_WIDTH_G => RD_DATA_WIDTH_G,
               ADDR_WIDTH_G    => ADDR_WIDTH_G)
            port map (
               rst    => rst,
               -- Write Interface
               wr_clk => wrClk,
               wr_en  => wrEn,
               din    => din,
               full   => fullWrDomain,
               -- Read Interface
               rd_clk => rdClk,
               rd_en  => rdEn,
               empty  => empty,
               dout   => dout);
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
            dataIn  => fullWrDomain,
            dataOut => full);

   end generate STANDALONE_FLOW_GEN;

   ASIC_SIM_FLOW_GEN : if (GHDL_SIM_G = false and SYNTHESIZE_G = false) generate

      -- vendor proprietary fifo placeholder
      -- remove this once you place the vendor FIFO
      assert (GHDL_SIM_G = false and SYNTHESIZE_G = false)
      report "[ERROR]: No vendor proprietary FIFO simulation behavioral model implemented yet!"
      severity failure;

   end generate ASIC_SIM_FLOW_GEN;

   ASIC_SYNTH_FLOW_GEN : if (SYNTHESIZE_G = true) generate
      rstDwareFifo  <= not(rst);
      wrEnDwareFifo <= not(wrEn);
      rdEnDwareFifo <= not(rdEn);

      SYMM_GEN: if (WR_DATA_WIDTH_G = RD_DATA_WIDTH_G) generate
         U_designwareSynthFifo : DW_fifo_s2_sf
            generic map (
               width => WR_DATA_WIDTH_G,
               depth => DWARE_DEPTH_G)
            port map (
               rst_n      => rstDwareFifo,
               -- Write Interface
               clk_push   => wrClk,
               push_req_n => wrEnDwareFifo,
               data_in    => din,
               --push_full  => full,
               -- Read Interface
               clk_pop    => rdClk,
               pop_req_n  => rdEnDwareFifo,
               pop_empty  => empty,
               pop_full   => full,
               data_out   => dout);
      end generate SYMM_GEN;

      ASYMM_GEN: if (WR_DATA_WIDTH_G /= RD_DATA_WIDTH_G) generate
         U_designwareSynthFifo : DW_asymfifo_s2_sf
            generic map (
               data_in_width  => WR_DATA_WIDTH_G,
               data_out_width => RD_DATA_WIDTH_G,
               depth          => DWARE_DEPTH_G)
            port map (
               rst_n      => rstDwareFifo,
               flush_n    => rstDwareFifo,
               -- Write Interface
               clk_push   => wrClk,
               push_req_n => wrEnDwareFifo,
               data_in    => din,
               --push_full  => full,
               -- Read Interface
               clk_pop    => rdClk,
               pop_req_n  => rdEnDwareFifo,
               pop_empty  => empty,
               pop_full   => full,
               data_out   => dout);
      end generate ASYMM_GEN;
   end generate ASIC_SYNTH_FLOW_GEN;

end rtl;
