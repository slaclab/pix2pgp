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
      pgpClk              : in  sl;
      rst                 : in  sl := not(RST_POLARITY_G);
      -- Arbiter Interface
      arbiterDvalid       : in  sl;
      arbiterDout         : in  slv(DATABUS_DWIDTH_C-1 downto 0);
      arbiterGearboxReady : out sl;
      -- PGP Interface
      pgpReady            : in  sl;
      pgpValid            : out sl;
      pgpData             : out slv(PGP_DWIDTH_C-1 downto 0));
end Pix2PgpGearboxWrapper;

architecture rtl of Pix2PgpGearboxWrapper is

   constant GEARBOX_OUTPUT_WIDTH_C  : natural := DATABUS_DWIDTH_C*8;
   signal pgpGearboxDataWordValid   : sl := '0';
   signal pgpGearboxDataWord        : slv(GEARBOX_OUTPUT_WIDTH_C-1 downto 0) := (others => '0');
   signal arbiterGearboxWriteIndex  : slv(bitSize(GEARBOX_OUTPUT_WIDTH_C) downto 0);
   signal pgpGearboxWriteIndex      : slv(bitSize(PGP_DWIDTH_C) downto 0) := (others => '0');
   signal pgpGearboxReady           : sl := '0';

   type RegType is record
      -- i/o
      arbiterDvalid : sl;
      arbiterDout   : slv(DATABUS_DWIDTH_C-1 downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- i/o
      arbiterDvalid => '0',
      arbiterDout   => (others => '0'));

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   -- safeguards
   assert (GEARBOX_OUTPUT_WIDTH_C rem DATABUS_DWIDTH_C = 0)
   report "[ERROR]: GEARBOX_OUTPUT_WIDTH_C/DATABUS_DWIDTH_C ratio is not an integer!"
   severity failure;

   assert (GEARBOX_OUTPUT_WIDTH_C rem PGP_DWIDTH_C = 0)
   report "[ERROR]: GEARBOX_OUTPUT_WIDTH_C/64-bit PGP input bus ratio is not an integer!"
   severity failure;

   ------------------------------------------------
   -- Adapter FSM
   ------------------------------------------------
   comb : process (r, rst, arbiterDvalid, arbiterDout) is

      variable v : RegType;

   begin

      -- Latch the current value
      v := r;


      -- Register inputs
      v.arbiterDvalid := arbiterDvalid;
      v.arbiterDout   := arbiterDout;
      --v.arbiterStart    := arbiterStart;
      --v.statusFifoError := statusFifoError;
      --v.dataFifoError   := dataFifoError;
      --v.overOccError    := overOccError;
      --v.alignError      := alignError;
      --v.colBitmask      := colBitmask;
      --v.trgNum          := trgNum;

      --v.eventEmpty      := not(uOr(r.colBitmask));

      -- Outputs
      --dataRd <= r.dataRd;
      --colSel <= r.colSel;

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
         r <= rin after TPD_G;
      end if;
   end process seq;

   -----------------
   -- 40:320 Gearbox
   -----------------
   U_Arbiter_Gearbox : entity pix2pgp.Pix2PgpGearbox
      generic map (
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         SLAVE_WIDTH_G  => DATABUS_DWIDTH_C,
         MASTER_WIDTH_G => GEARBOX_OUTPUT_WIDTH_C)
      port map (
         -- Clock and Reset
         clk            => pgpClk,
         rst            => rst,
         -- Slave Interface
         slaveValid     => r.arbiterDvalid,
         slaveData      => r.arbiterDout,
         slaveReady     => arbiterGearboxReady,
         writeIndex     => arbiterGearboxWriteIndex,
         slaveBitOrder  => '0',
         -- Master Interface
         masterBitOrder => '0',
         masterReady    => pgpGearboxReady,
         masterValid    => pgpGearboxDataWordValid,
         masterData     => pgpGearboxDataWord);

   -----------------
   -- 320:64 Gearbox
   -----------------
   U_PGP_Gearbox : entity pix2pgp.Pix2PgpGearbox
      generic map (
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         SLAVE_WIDTH_G  => GEARBOX_OUTPUT_WIDTH_C,
         MASTER_WIDTH_G => 64)
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
