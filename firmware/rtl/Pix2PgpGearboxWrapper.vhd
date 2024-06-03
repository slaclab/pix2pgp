-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: PIX2PGP Interface Adapter
--              Features gearboxes that move the data from the local bus widths
--              to the native 64-bit PGP4 input width
--              If stale words have remained inside the first gearbox,
--              dummy headers are written to flush them out
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

entity Pix2PgpGearboxWrapper is
   generic(
      TPD_G           : time     := 1 ns;
      RST_ASYNC_G     : boolean  := false;
      RST_POLARITY_G  : sl       := '1');
   port(
      -- General Interface
      pgpClk     : in  sl;
      rst        : in  sl := not(RST_POLARITY_G);
      -- Arbiter Interface
      arbValid   : in  sl;
      arbDout    : in  slv(DATABUS_DWIDTH_C-1 downto 0);
      arbReady   : out sl;
      writeIndex : out slv(bitSize(GEARBOX_OUTPUT_WIDTH_C) downto 0);
      -- PGP Interface
      pgpReady   : in  sl;
      pgpValid   : out sl;
      pgpData    : out slv(PGP_DWIDTH_C-1 downto 0));
end Pix2PgpGearboxWrapper;

architecture rtl of Pix2PgpGearboxWrapper is

   signal pgpGearboxDataWordValid   : sl := '0';
   signal pgpGearboxDataWord        : slv(GEARBOX_OUTPUT_WIDTH_C-1 downto 0) := (others => '0');
   signal arbiterGearboxWriteIndex  : slv(bitSize(GEARBOX_OUTPUT_WIDTH_C) downto 0);
   signal pgpGearboxWriteIndex      : slv(bitSize(PGP_DWIDTH_C) downto 0) := (others => '0');
   signal pgpGearboxReady           : sl := '0';

begin

   -- safeguards
   assert (GEARBOX_OUTPUT_WIDTH_C rem DATABUS_DWIDTH_C = 0)
   report "[ERROR]: GEARBOX_OUTPUT_WIDTH_C/DATABUS_DWIDTH_C ratio is not an integer!"
   severity failure;

   assert (GEARBOX_OUTPUT_WIDTH_C rem PGP_DWIDTH_C = 0)
   report "[ERROR]: GEARBOX_OUTPUT_WIDTH_C/64-bit PGP input bus ratio is not an integer!"
   severity failure;
   -----------------
   -- 40:320 Gearbox
   -----------------
   U_Arbiter_Gearbox : entity pix2pgp.Pix2PgpGearbox
      generic map (
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         RST_POLARITY_G => RST_POLARITY_G,
         SLAVE_WIDTH_G  => DATABUS_DWIDTH_C,
         MASTER_WIDTH_G => GEARBOX_OUTPUT_WIDTH_C)
      port map (
         -- Clock and Reset
         clk            => pgpClk,
         rst            => rst,
         -- Slave Interface
         slaveValid     => arbValid,
         slaveData      => arbDout,
         slaveReady     => arbReady,
         writeIndex     => arbiterGearboxWriteIndex,
         slaveBitOrder  => '0',
         -- Master Interface
         masterBitOrder => '0',
         masterReady    => pgpGearboxReady,
         masterValid    => pgpGearboxDataWordValid,
         masterData     => pgpGearboxDataWord);

   writeIndex <= arbiterGearboxWriteIndex;

   -----------------
   -- 320:64 Gearbox
   -----------------
   U_PGP_Gearbox : entity pix2pgp.Pix2PgpGearbox
      generic map (
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         RST_POLARITY_G => RST_POLARITY_G,
         SLAVE_WIDTH_G  => GEARBOX_OUTPUT_WIDTH_C,
         MASTER_WIDTH_G => PGP_DWIDTH_C)
      port map (
         -- Clock and Reset
         clk            => pgpClk,
         rst            => rst,
         -- Slave Interface
         slaveValid     => pgpGearboxDataWordValid,
         slaveData      => pgpGearboxDataWord,
         slaveReady     => pgpGearboxReady,
         writeIndex     => pgpGearboxWriteIndex,
         slaveBitOrder  => '0',
         -- Master Interface
         masterBitOrder => '0',
         masterReady    => pgpReady,
         masterValid    => pgpValid,
         masterData     => pgpData);

end rtl;
