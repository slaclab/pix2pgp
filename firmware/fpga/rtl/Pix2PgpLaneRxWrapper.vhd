-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Wrapper for Pix2Pgp Single-Lane Receiver
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
use surf.AxiLitePkg.all;
use surf.AxiStreamPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpAsicPkg.all;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpLaneRxWrapper is
   generic(
      TPD_G                  : time     := 1 ns;
      RST_ASYNC_G            : boolean  := false;
      RST_POLARITY_G         : sl       := '1';  -- '1' for active high rst, '0' for active low
      LANE_ID_G              : natural  := 0;
      META_FIFO_ADDR_WIDTH_G : positive := 6;
      LANE_FIFO_ADDR_WIDTH_G : positive := 8;
      LANE_MON_GEN_G         : boolean  := false;
      LANE_MON_CNT_WIDTH_G   : positive := 16);
   port(
      -- General Interface
      laneClk         : in  sl;
      laneRst         : in  sl := not(RST_POLARITY_G);
      pgpRxRst        : in  sl := not(RST_POLARITY_G);
      config          : in  Pix2PgpStreamRxConfigType;
      linkDown        : in  sl;
      -- ASIC Data Lane Interface
      pgp4RxMaster    : in  AxiStreamMasterType;
      pgp4RxSlave     : out AxiStreamSlaveType;
      -- Supervisor Interface
      laneStatus      : out Pix2PgpLaneStatusType;
      laneMetaRd      : in  sl;
      -- Monitoring Output Interface
      laneMon         : out Pix2PgpLaneStatusType;
      -- Merger Interface
      laneRxMaster    : out AxiStreamMasterType;
      laneRxSlave     : in  AxiStreamSlaveType;
      -- AXI-Lite Interface (sync'd to pgpRxClk domain)
      axilReadMaster  : in  AxiLiteReadMasterType  := AXI_LITE_READ_MASTER_INIT_C;
      axilReadSlave   : out AxiLiteReadSlaveType   := AXI_LITE_READ_SLAVE_INIT_C;
      axilWriteMaster : in  AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
      axilWriteSlave  : out AxiLiteWriteSlaveType  := AXI_LITE_WRITE_SLAVE_INIT_C);
end Pix2PgpLaneRxWrapper;

architecture rtl of Pix2PgpLaneRxWrapper is

   signal frameMetaRd    : sl := '0';
   signal frameMetaDout  : slv(LANERX_META_DWIDTH_C-1 downto 0) := (others => '0');
   signal frameMetaValid : sl := '0';
   signal laneRxFull     : sl := '0';
   signal monState       : slv(STATE_MON_WIDTH_C-1 downto 0)        := (others => '0');
   signal monDin         : slv(PIX2PGP_DATABUS_DWIDTH_C-1 downto 0) := (others => '0');
   signal status         : Pix2PgpLaneStatusType     := DEFAULT_PIX2PGP_LANESTATUS_C;

begin

   U_Lane: entity pix2pgp.Pix2PgpLaneRx
      generic map(
         TPD_G                  => TPD_G,
         RST_ASYNC_G            => RST_ASYNC_G,
         RST_POLARITY_G         => RST_POLARITY_G,
         META_FIFO_ADDR_WIDTH_G => META_FIFO_ADDR_WIDTH_G,
         LANE_FIFO_ADDR_WIDTH_G => LANE_FIFO_ADDR_WIDTH_G)
      port map(
         -- General Interface
         laneClk        => laneClk,
         laneRst        => laneRst,
         config         => config,
         monState       => monState,
         monDin         => monDin,
         -- RX FIFO Interface
         pgp4RxMaster   => pgp4RxMaster,
         pgp4RxSlave    => pgp4RxSlave,
         -- StreamRx Interface
         frameMetaRd    => frameMetaRd,
         frameMetaDout  => frameMetaDout,
         frameMetaValid => frameMetaValid,
         laneRxFull     => laneRxFull,
         -- AXI-Stream to StreamRx
         obAxisMaster   => laneRxMaster,
         obAxisSlave    => laneRxSlave);

   GEN_MON : if LANE_MON_GEN_G generate

      U_LaneMon: entity pix2pgp.Pix2PgpLaneMon
         generic map(
            TPD_G           => TPD_G,
            RST_ASYNC_G     => RST_ASYNC_G,
            RST_POLARITY_G  => RST_POLARITY_G,
            LANE_ID_G       => LANE_ID_G,
            MON_CNT_WIDTH_G => LANE_MON_CNT_WIDTH_G)
         port map(
         -- General Interface
         pgpRxClk        => laneClk, -- same as pgpRxClk
         pgpRxRst        => pgpRxRst,
         -- Lane Interface
         laneDown        => linkDown,
         laneStatus      => status,
         config          => config,
         monState        => monState,
         monDin          => monDin,
         -- Monitoring Output
         laneMon         => laneMon,
         -- AXI-Lite Interface  (sync'd to pgpRxClk domain)
         axilReadMaster  => axilReadMaster,
         axilReadSlave   => axilReadSlave,
         axilWriteMaster => axilWriteMaster,
         axilWriteSlave  => axilWriteSlave);

   end generate GEN_MON;

   frameMetaRd        <= laneMetaRd;
   status.valid       <= frameMetaValid;
   status.overflow    <= laneRxFull;
   status.overOcc     <= frameMetaDout(LANE_OVEROCC_POS_C);
   status.pause       <= frameMetaDout(LANE_PAUSE_POS_C);
   status.pauseError  <= frameMetaDout(LANE_PAUSE_ERROR_POS_C);
   status.decError    <= frameMetaDout(LANE_DEC_ERROR_POS_C);
   status.trgCnt      <= frameMetaDout(LANE_TRGCNT_POS_C);
   status.eventHitmask <= frameMetaDout(LANE_HITMASK_POS_C);
   status.frameSize   <= frameMetaDout(LANE_SIZE_POS_C);

   laneStatus <= status;

end rtl;
