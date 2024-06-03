-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Adapter; converts a stream of valid to SOF/EOF
--              DRAFT! deploying to check resource utilization...
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
      DWARE_DEPTH_G   : integer := 12;
      GHDL_SIM_G      : boolean := false;
      SYNTHESIZE_G    : boolean := false);
   port(
      -- General Interface
      pgpClk   : in  sl;
      rst      : in  sl := not(RST_POLARITY_G);
      -- Gearbox Interface
      pgpValid : in sl;
      pgpData  : in slv(PGP_DWIDTH_C-1 downto 0);
      -- Pgp4TxLite Interface
      txReady  : in  sl;
      txValid  : out sl;
      txData   : out slv(PGP_DWIDTH_C-1 downto 0);
      txSof    : out sl;
      txEof    : out sl;
      txEofe   : out sl);
end Pix2PgpAdapter;

architecture rtl of Pix2PgpAdapter is

   signal fifoEmpty  : sl := '0';
   signal fifoRdEn   : sl := '0';
   signal txValidInt : sl := '0';
   signal fifoRdEnInt: sl := '0';
   signal txSofInt   : sl := '0';
   signal fifoDout   : slv(PGP_DWIDTH_C-1 downto 0) := (others => '0');

   type RegType is record
      -- i/o
      pgpValid   : sl;
      txReady    : sl;
      txData     : slv(PGP_DWIDTH_C-1 downto 0);
      txSof      : sl;
      txEof      : sl;
      txEofe     : sl;
      -- internal
      fifoEmpty  : sl;
      fifoRdEn   : sl;
      rdEnStrobe : sl;
      txValidInt : sl;
      wrEnCnt    : slv(3 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- i/o
      pgpValid   => '0',
      txReady    => '0',
      txData     => (others => '0'),
      txSof      => '0',
      txEof      => '0',
      txEofe     => '0',
      -- internal
      fifoEmpty  => '0',
      fifoRdEn   => '0',
      rdEnStrobe => '0',
      txValidInt => '0',
      wrEnCnt    => (others => '0'));

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Column Supervisor FSM
   ------------------------------------------------
   comb : process (r, rst, fifoEmpty, txReady, pgpValid, fifoRdEn, txValidInt, fifoRdEnInt) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- strobes
      v.rdEnStrobe := '0';
      v.txSof      := '0';
      v.txEof      := '0';

      -- Register inputs
      v.fifoEmpty   := fifoEmpty;
      v.txReady     := txReady;
      v.pgpValid    := pgpValid;
      v.fifoRdEn    := fifoRdEnInt;
      v.txValidInt  := txValidInt;

      -- wrEn counter management
      if (r.pgpValid = '1') then
         v.wrEnCnt := r.wrEnCnt + 1;
      end if;

      if (r.wrEnCnt >= toSlv(5, r.wrEnCnt'length) and r.txReady = '1') then
         v.wrEnCnt    := r.wrEnCnt - 5;
         v.rdEnStrobe := '1';
      end if;

      -- rising-edge detection
      if (v.txValidInt = '1' and r.txValidInt = '0') then
         v.txSof := '1';
      end if;

      -- falling-edge detection
      if (v.txValidInt = '0' and r.txValidInt = '1') then
         v.txEof := '1';
      end if;

      v.txEofe := '0';

      -- Outputs
      txSofInt <= r.txSof;
      txEof    <= r.txEof;
      txEofe   <= r.txEofe;
      fifoRdEn <= r.fifoRdEn;

      -- Reset
      if (RST_ASYNC_G = false and rst = '1') then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (pgpClk, rst) is
   begin
      if (RST_ASYNC_G and rst = '1') then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(pgpClk) then
         r     <= rin after TPD_G;
         txSof <= txSofInt after TPD_G;
      end if;
   end process seq;

   U_rdEnStretch : entity surf.SynchronizerOneShot
      generic map (
         TPD_G         => TPD_G,
         RST_ASYNC_G   => true,
         PULSE_WIDTH_G => 5)
      port map (
         clk     => pgpClk,
         rst     => rst,
         dataIn  => r.rdEnStrobe,
         dataOut => fifoRdEnInt);

   U_txValidInt : entity surf.SynchronizerOneShot
      generic map (
         TPD_G         => TPD_G,
         RST_ASYNC_G   => true,
         PULSE_WIDTH_G => 5)
      port map (
         clk     => pgpClk,
         rst     => rst,
         dataIn  => r.rdEnStrobe,
         dataOut => txValidInt);

   U_txValid : entity surf.Synchronizer
      generic map (
         TPD_G         => TPD_G,
         RST_ASYNC_G   => true)
      port map (
         clk     => pgpClk,
         rst     => rst,
         dataIn  => txValidInt,
         dataOut => txValid);

   U_PgpBuffer : entity pix2pgp.Pix2PgpFifoWrapper
      generic map (
         TPD_G           => TPD_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         GEN_SYNC_FIFO_G => false,
         WR_DATA_WIDTH_G => PGP_DWIDTH_C,
         RD_DATA_WIDTH_G => PGP_DWIDTH_C,
         DWARE_DEPTH_G   => DWARE_DEPTH_G,
         ADDR_WIDTH_G    => 8,
         GHDL_SIM_G      => GHDL_SIM_G,
         SYNTHESIZE_G    => SYNTHESIZE_G)
      port map (
         -- Resets
         rst   => rst,
         -- Write Interface
         wrClk => pgpClk,
         wrEn  => pgpValid,
         din   => pgpData,
         full  => open,
         -- Read Interface
         rdClk => pgpClk,
         rdEn  => fifoRdEn,
         empty => fifoEmpty,
         dout  => txData);

end rtl;
