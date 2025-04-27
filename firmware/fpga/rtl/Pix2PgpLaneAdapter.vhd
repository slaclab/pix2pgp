-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp Lane Adapter; converts lane data to AXI-Stream
--              To-Do: implement trigger counter checking
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
use surf.AxiStreamPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpLaneAdapter is
   generic(
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1'  -- '1' for active high rst, '0' for active low
   );
   port(
      -- General Interface
      sysClk         : in  sl;
      sysRst         : in  sl := not(RST_POLARITY_G);
      -- Lane Interface
      rstDone        : out sl;
      frameMetaRd    : out sl;
      frameMetaDout  : in  slv(LANERX_FRAMELEN_BUFF_WIDTH_C-1 downto 0);
      frameMetaValid : in  sl;
      -- AXI
      mAxisMaster    : in  AxiStreamMasterType;
      mAxisSlave     : out AxiStreamSlaveType;
      -- ASIC Rx Interface
      laneError      : out sl;
      laneErrorAck   : in  sl;
      laneTxMaster   : out AxiStreamMasterType;
      laneTxSlave    : in  AxiStreamSlaveType);
end Pix2PgpLaneAdapter;

architecture rtl of Pix2PgpLaneAdapter is

   -- how much to stretch rstDone
   constant RST_DONE_WIDTH_C : natural := 10;

   -- axi-stream gearbox configuration
   constant SLAVE_AXI_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C    => false,
      TDATA_BYTES_C => ASIC_DATABUS_DWIDTH_C/8,
      TDEST_BITS_C  => 4,
      TID_BITS_C    => 0,
      TKEEP_MODE_C  => TKEEP_NORMAL_C,
      TUSER_BITS_C  => 4,
      TUSER_MODE_C  => TUSER_NORMAL_C);

   -- note that the bus becomes wider to have enough bandwidth to read-out all lanes fast enough
   constant MASTER_AXI_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C    => false,
      TDATA_BYTES_C => FPGA_DATABUS_DWIDTH_C/8,
      TDEST_BITS_C  => 4,
      TID_BITS_C    => 0,
      TKEEP_MODE_C  => TKEEP_NORMAL_C,
      TUSER_BITS_C  => 4,
      TUSER_MODE_C  => TUSER_NORMAL_C);

   signal reverseTxMaster : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal reverseTxSlave  : AxiStreamSlaveType  := AXI_STREAM_SLAVE_INIT_C;

begin

   -- To-Do: implement logic for these
   frameMetaRd <= frameMetaValid;
   laneError   <= '0';

   U_StretchErrorAck : entity surf.SynchronizerOneShot
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         PULSE_WIDTH_G  => RST_DONE_WIDTH_C)
      port map (
         clk     => sysClk,
         dataIn  => laneErrorAck,
         dataOut => rstDone);

   -----------------------------------------
   -- Axi-Stream Gearbox (1-to-8)
   -----------------------------------------
   U_Gearbox : entity surf.AxiStreamGearbox
      generic map(
         -- General Configurations
         TPD_G               => TPD_G,
         RST_POLARITY_G      => RST_POLARITY_G,
         RST_ASYNC_G         => RST_ASYNC_G,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => SLAVE_AXI_CONFIG_C,
         MASTER_AXI_CONFIG_G => MASTER_AXI_CONFIG_C)
      port map(
         -- Clock and reset
         axisClk     => sysClk,
         axisRst     => sysRst,
         -- Slave Port
         sAxisMaster => mAxisMaster,
         sSideBand   => (others => '0'),
         sAxisSlave  => mAxisSlave,
         -- Master Port
         mAxisMaster => reverseTxMaster,
         mSideBand   => open,
         mAxisSlave  => reverseTxSlave);

   -----------------------------------------
   -- Reverses on a per-word basis
   -----------------------------------------
   U_Reverse: entity pix2pgp.AxiStreamReverse
      generic map(
         TPD_G             => TPD_G,
         RST_ASYNC_G       => RST_ASYNC_G,
         RST_POLARITY_G    => RST_POLARITY_G,
         AXIS_FIFO_WIDTH_G => AXIS_FIFO_WIDTH_C,
         IB_DWIDTH_G       => ASIC_DATABUS_DWIDTH_C/8,
         OB_DWIDTH_G       => FPGA_DATABUS_DWIDTH_C/8)
      port map(
         -- General Interface
         sysClk     => sysClk,
         sysRst     => sysRst,
         -- Inbound Interface
         ibTxMaster => reverseTxMaster,
         ibTxSlave  => reverseTxSlave,
         -- Outbound Interface
         obTxMaster => laneTxMaster,
         obTxSlave  => laneTxSlave);

end rtl;
