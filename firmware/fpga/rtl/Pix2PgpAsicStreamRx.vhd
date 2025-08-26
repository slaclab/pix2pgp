-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp ASIC Stream Receiver
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
use surf.AxiLitePkg.all;
use surf.AxiStreamPkg.all;
use surf.SsiPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpAsicPkg.all;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpAsicStreamRx is
   generic(
      TPD_G                  : time     := 1 ns;
      RST_ASYNC_G            : boolean  := false;
      RST_POLARITY_G         : sl       := '1';  -- '1' for active high rst, '0' for active low
      ASIC_RST_POLARITY_G    : sl       := '0';  -- '1' for active high rst, '0' for active low
      ASIC_ID_G              : natural  := 0;
      LANE_PIPE_STAGES_G     : natural  := 1;
      TRG_FIFO_ADDR_WIDTH_G  : positive := 6;
      META_FIFO_ADDR_WIDTH_G : positive := 6;
      AXIS_FIFO_ADDR_WIDTH_G : positive := 6);
   port(
      -- General Interface
      pgpRxClk        : in  sl;
      pgpRxRst        : in  sl := not(RST_POLARITY_G);
      -- ASIC Domain Interface
      asicClk         : in  sl;
      asicRst         : in  sl; -- active-low always
      asicSro         : in  sl;
      asicSroEn       : in  sl;
      -- PGP4Rx Input Interface (on pgpRxClk domain)
      pgp4RxMaster    : in  AxiStreamMasterArray;
      pgp4RxSlave     : out AxiStreamSlaveArray;
      pgp4RxLinkUp    : in  slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- AXI-Stream Output Interface (on pgpRxClk domain)
      asicRxMaster    : out AxiStreamMasterType;
      asicRxSlave     : in  AxiStreamSlaveType;
      -- AXI-Lite Interface
      axilClk         : in  sl;
      axilRst         : in  sl;
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType);
end Pix2PgpAsicStreamRx;

architecture rtl of Pix2PgpAsicStreamRx is

   signal laneRxMasters  : AxiStreamMasterArray(NUM_OF_SERIALIZERS_C-1 downto 0)
                         := (others => AXI_STREAM_MASTER_INIT_C);
   signal laneRxSlaves   : AxiStreamSlaveArray(NUM_OF_SERIALIZERS_C-1 downto 0)
                         := (others => AXI_STREAM_SLAVE_INIT_C);

   signal trgBuffRd      : sl := '0';
   signal trgBuffSroEn   : sl := '0';
   signal trgBuffValid   : sl := '0';
   signal config         : Pix2PgpStreamRxConfigType := DEFAULT_PIX2PGP_STREAMRX_CONFIG_C;
   signal trgBuffTrgCnt  : slv(TRGCNT_WIDTH_C-1 downto 0)       := (others => '0');
   signal fpgaTrgCnt     : slv(TRGCNT_WIDTH_C-1 downto 0)       := (others => '0');
   signal laneRst        : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal laneStatus     : Pix2PgpLaneStatusArray := (others => DEFAULT_PIX2PGP_LANESTATUS_C);
   signal asicStatus     : Pix2PgpLaneStatusArray := (others => DEFAULT_PIX2PGP_LANESTATUS_C);

   signal mergerBusy     : sl := '0';
   signal laneMetaRd     : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal lanePostError  : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal pgp4RxLinkDown : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal reqDrop        : sl := '0';
   signal reqNominal     : sl := '0';
   signal reqPause       : sl := '0';

   signal usrRst         : sl := '0';
   signal glblRst        : sl := not(RST_POLARITY_G);

begin

   -----------------
   -- Lane Receivers
   -----------------
   GEN_LANE: for lane in 0 to NUM_OF_SERIALIZERS_C-1 generate

      U_LaneWrapper: entity pix2pgp.Pix2PgpLaneRxWrapper
         generic map(
            TPD_G                  => TPD_G,
            RST_ASYNC_G            => RST_ASYNC_G,
            RST_POLARITY_G         => RST_POLARITY_G,
            PIPE_STAGES_G          => LANE_PIPE_STAGES_G,
            META_FIFO_ADDR_WIDTH_G => META_FIFO_ADDR_WIDTH_G,
            AXIS_FIFO_ADDR_WIDTH_G => AXIS_FIFO_ADDR_WIDTH_G)
         port map(
            -- General Interface
            laneClk        => pgpRxClk,
            laneRst        => laneRst(lane),
            config         => config,
            -- RX FIFO Interface
            pgp4RxMaster   => pgp4RxMaster(lane),
            pgp4RxSlave    => pgp4RxSlave(lane),
            -- ASIC Rx Interface
            lanePostError  => lanePostError(lane),
            laneStatus     => laneStatus(lane),
            laneMetaRd     => laneMetaRd(lane),
            laneRxMaster   => laneRxMasters(lane),
            laneRxSlave    => laneRxSlaves(lane));

   end generate GEN_LANE;

   ------------------
   -- Lane Supervisor
   ------------------
   U_LaneSupervisor: entity pix2pgp.Pix2PgpLaneSupervisor
      generic map(
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         RST_POLARITY_G => RST_POLARITY_G)
      port map(
         -- General Interface
         pgpRxClk       => pgpRxClk,
         pgpRxRst       => glblRst,
         config         => config,
         pgp4RxLinkUp   => pgp4RxLinkUp,
         pgp4RxLinkDown => pgp4RxLinkDown,
         -- Lane Interface
         laneRst        => laneRst,
         laneStatus     => laneStatus,
         laneMetaRd     => laneMetaRd,
         lanePostError  => lanePostError,
         -- Trigger Buffer Interface
         trgBuffTrgCnt  => trgBuffTrgCnt,
         trgBuffSroEn   => trgBuffSroEn,
         trgBuffValid   => trgBuffValid,
         trgBuffRd      => trgBuffRd,
         -- Lane Merger Interface
         mergerBusy     => mergerBusy,
         asicStatus     => asicStatus,
         fpgaTrgCnt     => fpgaTrgCnt,
         reqDrop        => reqDrop,
         reqNominal     => reqNominal,
         reqPause       => reqPause);

   --------------
   -- Lane Merger
   --------------
   U_LaneMerger: entity pix2pgp.Pix2PgpLaneMerger
      generic map(
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         RST_POLARITY_G => RST_POLARITY_G,
         ASIC_ID_G      => ASIC_ID_G)
      port map(
         -- General Interface
         pgpRxClk      => pgpRxClk,
         pgpRxRst      => glblRst,
         config        => config,
         -- Supervisor Interface
         mergerBusy    => mergerBusy,
         asicStatus    => asicStatus,
         fpgaTrgCnt    => fpgaTrgCnt,
         reqDrop       => reqDrop,
         reqNominal    => reqNominal,
         reqPause      => reqPause,
         -- Lane AXI-Stream Input Interface
         laneRxMasters => laneRxMasters,
         laneRxSlaves  => laneRxSlaves,
         -- AXI-Stream Output Interface (on pgpRxClk domain)
         asicRxMaster  => asicRxMaster,
         asicRxSlave   => asicRxSlave);

   ------------------
   -- Trigger Manager
   ------------------
   U_TriggerManager: entity pix2pgp.Pix2PgpTriggerManager
      generic map(
         TPD_G                 => TPD_G,
         RST_ASYNC_G           => RST_ASYNC_G,
         ASIC_RST_POLARITY_G   => ASIC_RST_POLARITY_G,
         LOGIC_RST_POLARITY_G  => RST_POLARITY_G,
         TRG_FIFO_ADDR_WIDTH_G => TRG_FIFO_ADDR_WIDTH_G)
      port map(
         -- General Interface
         asicClk       => asicClk,
         asicRst       => asicRst,
         pgpRxClk      => pgpRxClk,
         pgpRxRst      => glblRst,
         -- ASIC Control Interface
         asicSro       => asicSro,
         asicSroEn     => asicSroEn,
         -- Lane Supervisor Interface
         trgBuffRd     => trgBuffRd,
         trgBuffTrgCnt => trgBuffTrgCnt,
         trgBuffSroEn  => trgBuffSroEn,
         trgBuffValid  => trgBuffValid);

   -------------------
   -- Axi-Lite Manager
   -------------------
   U_AxiLiteManager: entity pix2pgp.Pix2PgpAxiLiteManager
      generic map(
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         RST_POLARITY_G => RST_POLARITY_G)
      port map(
         -- General Interface
         pgpRxClk        => pgpRxClk,
         pgpRxRst        => pgpRxRst,
         usrRst          => usrRst,
         config          => config,
         -- Internal Module Interface
         mergerBusy      => mergerBusy,
         laneDown        => pgp4RxLinkDown,
         asicStatus      => asicStatus,
         fpgaTrgCnt      => fpgaTrgCnt,
         -- AXI-Lite Interface
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMaster,
         axilReadSlave   => axilReadSlave,
         axilWriteMaster => axilWriteMaster,
         axilWriteSlave  => axilWriteSlave);


   glblRst <= (pgpRxRst or usrRst) when (RST_POLARITY_G = '1') else
              (pgpRxRst and not usrRst);

end rtl;
