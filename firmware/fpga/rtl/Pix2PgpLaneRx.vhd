-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp Single-Lane Receiver
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

entity Pix2PgpLaneRx is
   generic(
      TPD_G          : time     := 1 ns;
      RST_ASYNC_G    : boolean  := false;
      RST_POLARITY_G : sl       := '1'  -- '1' for active high rst, '0' for active low
   );
   port(
      -- General Interface
      pgpClk   : in  sl;
      pgpRst   : in  sl := not(RST_POLARITY_G);
      sysClk   : in  sl;
      sysRst   : in  sl := not(RST_POLARITY_G);
      -- RX FIFO Interface
      pgpValid : in  sl;
      pgpData  : in  slv(DATABUS_DWIDTH_C-1 downto 0);
      pgpRd    : out sl;
      -- Framer Interface
      ready    : out sl;
      noHits   : out sl;
      colHits  : out slv(BITMAX_COL_MANAGERS_C-1 downto 0);
      ibValid  : in  sl;
      dout     : out slv(DWIDTH_G-1 downto 0);
      obValid  : out sl
   );
end Pix2PgpLaneRx;

architecture rtl of Pix2PgpLaneRx is

   type RegType is record
      din      : slv(DWIDTH_G-1 downto 0);
      ibValid  : sl;
      dout     : slv(DWIDTH_G-1 downto 0);
      obValid  : sl;
      flag     : sl;
   end record RegType;

   constant REG_INIT_C : RegType := (
      din      => (others => '0'),
      ibValid  => '0',
      dout     => (others => '0'),
      obValid  => '0',
      flag     => '0'
   );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   -----------------------------
   -- First Buffer Level
   -----------------------------
   U_dataFifo : entity surf.Fifo
      generic map (
         TPD_G           => TPD_G,
         GEN_SYNC_FIFO_G => false, -- false = dual-clock FIFO
         MEMORY_TYPE_G   => "block",
         FWFT_EN_G       => true,
         DATA_WIDTH_G    => DATABUS_DWIDTH_C,
         ADDR_WIDTH_G    => LANE_RX_FIFO_ADDR_WIDTH_C)
      port map (
         rst      => sysRst,
         -- Write Ports
         wr_clk   => pgpClk,
         wr_en    => pgpValid,
         din      => pgpData,
         overflow => pgpFifoFull,
         -- Read Ports
         rd_clk   => sysClk,
         rd_en    => pgpFifoRd,
         dout     => pgpFifoDout,
         valid    => pgpFifoValid);

   comb : process (din, r, rst, ibValid) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Register input
      v.din     := din;
      v.ibValid := ibValid;

      -- Check if ready to process data
      if (((v.flag = '0') and (v.ibValid = '1' and REG_DIN_G = false))
      or ((v.flag = '0') and (r.ibValid = '1' and REG_DIN_G = true))
      ) then
         -- Set a flow control flag
         v.flag := '1';
      end if;

      -- main body of processing that involves checking of the v.flag...

      -- Outputs
      if REG_DOUT_G then
         dout    <= r.dout;
         obValid <= r.obValid;
      else
         dout    <= v.dout;
         obValid <= v.obValid;
      end if;

      -- Reset
      if (RST_ASYNC_G = false and rst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (clk, rst) is
   begin
      if (RST_ASYNC_G and rst = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(clk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

end rtl;
