-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp FIFO Wrapper for Vivado/VCS/Synopsys use
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

   component DW_asymfifo_s2_sf is
      generic(
         data_in_width  : integer;
         data_out_width : integer;
         depth          : integer := 8;
         push_ae_lvl    : integer := 2;
         push_af_lvl    : integer := 2;
         pop_ae_lvl     : integer := 2;
         pop_af_lvl     : integer := 2;
         err_mode       : integer := 0;
         push_sync      : integer := 2;
         pop_sync       : integer := 2;
         rst_mode       : integer := 1;
         byte_order     : integer := 0);
      port(
         clk_push   : in  std_logic;
         clk_pop    : in  std_logic;
         rst_n      : in  std_logic;
         push_req_n : in  std_logic;
         flush_n    : in  std_logic;
         pop_req_n  : in  std_logic;
         data_in    : in  std_logic_vector(data_in_width-1 downto 0);
         push_empty : out std_logic;
         push_ae    : out std_logic;
         push_hf    : out std_logic;
         push_af    : out std_logic;
         push_full  : out std_logic;
         ram_full   : out std_logic;
         part_wd    : out std_logic;
         push_error : out std_logic;
         pop_empty  : out std_logic;
         pop_ae     : out std_logic;
         pop_hf     : out std_logic;
         pop_af     : out std_logic;
         pop_full   : out std_logic;
         pop_error  : out std_logic;
         data_out   : out std_logic_vector(data_out_width-1 downto 0 )
      );
   end component;

   component DW_fifo_s2_sf
      generic (
         width       : integer := 8;
         depth       : integer := 8;
         push_ae_lvl : integer := 2;
         push_af_lvl : integer := 2;
         pop_ae_lvl  : integer := 2;
         pop_af_lvl  : integer := 2;
         err_mode    : integer := 0;
         push_sync   : integer := 2;
         pop_sync    : integer := 2;
         rst_mode    : integer := 0);
      port(
         clk_push    : in  std_logic;
         clk_pop     : in  std_logic;
         rst_n       : in  std_logic;
         push_req_n  : in  std_logic;
         pop_req_n   : in  std_logic;
         data_in     : in  std_logic_vector(width-1 downto 0);
         push_empty  : out std_logic;
         push_ae     : out std_logic;
         push_hf     : out std_logic;
         push_af     : out std_logic;
         push_full   : out std_logic;
         push_error  : out std_logic;
         pop_empty   : out std_logic;
         pop_ae      : out std_logic;
         pop_hf      : out std_logic;
         pop_af      : out std_logic;
         pop_full    : out std_logic;
         pop_error   : out std_logic;
         data_out    : out std_logic_vector( width-1 downto 0 ));
   end component;

   signal rstDwareFifo      : sl := '0';
   signal wrEnDwareFifo     : sl := '0';
   signal rdEnDwareFifo     : sl := '0';
   signal rstFifo           : sl := '0';
   signal validWr           : sl := '0';

begin

   rstFifo <= (rst or not(enable)) when RST_POLARITY_G = '1' else (not(rst) or enable);

   wrEnDwareFifo <= not(wrEn);
   rdEnDwareFifo <= not(rdEn);
   rstDwareFifo  <= not(rstFifo);

   SYMM_GEN: if (WR_DATA_WIDTH_G = RD_DATA_WIDTH_G) generate
      U_designwareFifo : DW_fifo_s2_sf
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
      U_designwareFifo : DW_asymfifo_s2_sf
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

end rtl;
