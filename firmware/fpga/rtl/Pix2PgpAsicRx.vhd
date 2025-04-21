-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp ASIC Stream Receiver;
--              Merges all inbound data lanes into a single AXI stream
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
use surf.AxiStreamPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpAsicRx is
   generic(
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1'  -- '1' for active high rst, '0' for active low
   );
   port(
      -- General Interface
      asicClk      : in  sl;
      asicRst      : in  sl := not(RST_POLARITY_G);
      pgpClk       : in  sl;
      pgpRst       : in  sl := not(RST_POLARITY_G);
      sysClk       : in  sl;
      sysRst       : in  sl := not(RST_POLARITY_G);
      -- PGP4Rx Interface
      pgpValid     : in  slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      pgpData      : in  Pix2PgpFpgaRxDataArray;
      pgpReady     : out slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- AXI-Stream Rx Interface
      asicTxMaster : out AxiStreamMasterType;
      asicTxSlave  : in  AxiStreamSlaveType);
end Pix2PgpAsicRx;

architecture rtl of Pix2PgpAsicRx is

   signal frameDataRd    : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal frameDataDout  : Pix2PgpFpgaRxDataArray := (others => DEFAULT_PIX2PGP_DATABUS_C);
   signal frameDataFull  : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal frameMetaRd    : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal frameMetaDout  : Pix2PgpFpgaRxMetaArray := (others => DEFAULT_PIX2PGP_FPGARX_METABUS_C);
   signal frameMetaValid : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal laneTxMaster   : AxiStreamMasterArray(NUM_OF_SERIALIZERS_C-1 downto 0)
                         := (others => AXI_STREAM_MASTER_INIT_C);
   signal laneTxSlave    : AxiStreamSlaveArray(NUM_OF_SERIALIZERS_C-1 downto 0)
                         := (others => AXI_STREAM_SLAVE_INIT_C);

   signal laneError      : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal laneErrorAck   : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

begin

   GEN_LANE: for lane in 0 to NUM_OF_SERIALIZERS_C-1 generate

      U_Lane: entity pix2pgp.Pix2PgpLaneRx
         generic map(
            TPD_G          => TPD_G,
            RST_ASYNC_G    => RST_ASYNC_G,
            RST_POLARITY_G => RST_POLARITY_G)
         port map(
            -- General Interface
            pgpClk         => pgpClk,
            pgpRst         => pgpRst,
            sysClk         => sysClk,
            sysRst         => sysRst,
            -- RX FIFO Interface
            pgpValid       => pgpValid(lane),
            pgpData        => pgpData(lane).data,
            pgpReady       => pgpReady(lane),
            -- Adapter Interface
            frameDataRd    => frameDataRd(lane),
            frameDataDout  => frameDataDout(lane).data,
            frameDataFull  => frameDataFull(lane),
            frameMetaRd    => frameMetaRd(lane),
            frameMetaDout  => frameMetaDout(lane).metaData,
            frameMetaValid => frameMetaValid(lane));

      U_Adapter: entity pix2pgp.Pix2PgpLaneAdapter
         generic map(
            TPD_G          => TPD_G,
            RST_ASYNC_G    => RST_ASYNC_G,
            RST_POLARITY_G => RST_POLARITY_G)
         port map(
            -- General Interface
            sysClk         => sysClk,
            sysRst         => sysRst,
            -- Lane Interface
            frameDataRd    => frameDataRd(lane),
            frameDataDout  => frameDataDout(lane).data,
            frameDataFull  => frameDataFull(lane),
            frameMetaRd    => frameMetaRd(lane),
            frameMetaDout  => frameMetaDout(lane).metaData,
            frameMetaValid => frameMetaValid(lane),
            -- ASIC Rx Interface
            laneError      => laneError(lane),
            laneErrorAck   => laneErrorAck(lane),
            laneTxMaster   => laneTxMaster(lane),
            laneTxSlave    => laneTxSlave(lane));

   end generate GEN_LANE;

end rtl;
