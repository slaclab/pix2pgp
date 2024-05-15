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
      DATA_WIDTH_G     : natural := 20;
      ADDR_WIDTH_G     : natural := 12;
      GEN_SYNC_FIFO_G  : boolean := false;
      STANDALONE_G     : boolean := false);
   port(
      -- Resets
      rst   : in  sl;
      -- Write Interface
      wrClk : in  sl;
      wrEn  : in  sl;
      din   : in  slv(DATA_WIDTH_G-1 downto 0);
      full  : out sl := '0';
      -- Read Interface
      rdClk : in  sl;
      rdEn  : in  sl;
      empty : out sl := '1';
      dout  : out slv(DATA_WIDTH_G-1 downto 0));
end Pix2PgpFifoWrapper;

architecture rtl of Pix2PgpFifoWrapper is

begin

   STANDALONE_FLOW_GEN : if (STANDALONE_G = true) generate

      U_StandaloneFifo : entity surf.Fifo
         generic map (
            TPD_G           => TPD_G,
            RST_ASYNC_G     => RST_ASYNC_G,
            RST_POLARITY_G  => RST_POLARITY_G,
            GEN_SYNC_FIFO_G => GEN_SYNC_FIFO_G,
            DATA_WIDTH_G    => DATA_WIDTH_G,
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

   end generate STANDALONE_FLOW_GEN;

   ASIC_FLOW_GEN : if (STANDALONE_G = false) generate

      -- vendor proprietary fifo placeholder
      assert STANDALONE_G = false report "[ERROR]: No vendor proprietary FIFO implemented yet" severity error;

   end generate ASIC_FLOW_GEN;


end rtl;
