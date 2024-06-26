-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Adapter for PGP. Temporarily stores data into a FIFO;
--              checks the status of the 'txReady' from the PGP interface;
--              asserts valid, sof, eof accordingly
--
-- Important!   The frame size is fixed to 5x64-bit words (320 bits);
--              The arbiter monitors the amount of 40-bit words sent to the
--              40:64 gearbox. 8x40-bit words (*also* 320 bits)
--              should be written into the gearbox to keep things in check;
--              if a smaller amount of 40-bit words is written and a timeout
--              is reached, the arbiter stuffs the gearbox with dummy headers;
--              this functionality allows for the last data to be TX'd
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

entity Pix2PgpAdapter is
   generic(
      TPD_G           : time     := 1 ns;
      RST_ASYNC_G     : boolean  := false;
      RST_POLARITY_G  : sl       := '1';
      DWARE_DEPTH_G   : integer  := 12;
      GHDL_SIM_G      : boolean  := false;
      SYNTHESIZE_G    : boolean  := false);
   port(
      -- General Interface
      pgpClk   : in  sl;
      rst      : in  sl := not(RST_POLARITY_G);
      -- Gearbox Interface
      pgpValid : in  sl;
      pgpData  : in  slv(PGP_DWIDTH_C-1 downto 0);
      pgpReady : out sl;
      -- Pgp4TxLite Interface
      txReady  : in   sl;
      txValid  : out  sl;
      txData   : out  slv(PGP_DWIDTH_C-1 downto 0);
      txSof    : out  sl;
      txEof    : out  sl;
      txEofe   : out  sl);
end Pix2PgpAdapter;

architecture rtl of Pix2PgpAdapter is

   type StateType is (
      IDLE_S,
      PARSE_DATA_S);

   type RegType is record
      -- i/o
      txReady  : sl;
      txValid  : sl;
      txSof    : sl;
      txEof    : sl;
      -- internal
      fifoRdEn : sl;
      frameCnt : slv(2 downto 0);
      state    : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- i/o
      txReady  => '0',
      txValid  => '0',
      txSof    => '0',
      txEof    => '0',
      -- internal
      fifoRdEn => '0',
      frameCnt => (others => '0'),
      state    => IDLE_S);

   signal fifoEmpty : sl      := '0';
   signal fifoRdEn  : sl      := '0';
   signal pgpFull   : sl      := '0';
   signal r         : RegType := REG_INIT_C;
   signal rin       : RegType;

begin

   ------------------------------------------------
   -- Adapter FSM
   ------------------------------------------------
   comb : process (r, rst, fifoEmpty, txReady) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      v.fifoRdEn := '0';

      -- flow control check
      if (txReady = '1') then
         v.txValid := '0';
         v.txSof   := '0';
         v.txEof   := '0';
      end if;


      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- if fifo not empty, read first word
         when IDLE_S =>
            v.frameCnt := (others => '0');

            if fifoEmpty = '0' and v.txValid = '0' then
               v.txValid  := '1';
               v.fifoRdEn := '1';
               v.txSof    := '1';
               v.frameCnt := r.frameCnt + 1;
               v.state    := PARSE_DATA_S;
            end if;

         ----------------------------------------------------------------------
         -- parse the data from the selected data bus
         when PARSE_DATA_S =>
            if fifoEmpty = '0' and v.txValid = '0' then
               v.txValid  := '1';
               v.fifoRdEn := '1';
               v.frameCnt := r.frameCnt + 1;

               if r.frameCnt = 4 then
                  v.txEof := '1';
                  v.state := IDLE_S;
               end if;
            end if;

      end case;

      -- Outputs
      fifoRdEn <= v.fifoRdEn;
      txValid  <= r.txValid;
      txSof    <= r.txSof;
      txEof    <= r.txEof;
      txEofe   <= '0';

      -- Reset
      if (RST_ASYNC_G = false and rst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (pgpClk, rst) is
   begin
      if (RST_ASYNC_G and rst = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(pgpClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

   U_PgpBuffer : entity pix2pgp.Pix2PgpFifoWrapper
      generic map (
         TPD_G           => TPD_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         GEN_SYNC_FIFO_G => false,
         FWFT_EN_G       => false,
         WR_DATA_WIDTH_G => PGP_DWIDTH_C,
         RD_DATA_WIDTH_G => PGP_DWIDTH_C,
         DWARE_DEPTH_G   => DWARE_DEPTH_G,
         ADDR_WIDTH_G    => 4,
         GHDL_SIM_G      => GHDL_SIM_G,
         SYNTHESIZE_G    => SYNTHESIZE_G)
      port map (
         -- Resets
         rst    => rst,
         -- Write Interface
         wrClk  => pgpClk,
         wrEn   => pgpValid,
         din    => pgpData,
         fullWr => pgpFull,
         -- Read Interface
         rdClk  => pgpClk,
         rdEn   => fifoRdEn,
         empty  => fifoEmpty,
         fullRd => open,
         dout   => txData);

   pgpReady <= not(pgpFull);

end rtl;
