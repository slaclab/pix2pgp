-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Firmware Target's Top Level
-------------------------------------------------------------------------------
-- This file is part of 'pix2pgp'.
-- It is subject to the license terms in the LICENSE.txt file found in the
-- top-level directory of this distribution and at:
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
-- No part of 'pix2pgp', including this file,
-- may be copied, modified, propagated, or distributed except according to
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiStreamPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

library work;

entity Pix2PgpThriglav is
   generic (
      TPD_G                : time                        := 1 ns;
      BUILD_INFO_G         : BuildInfoType;
      ROGUE_SIM_EN_G       : boolean                     := false;
      ROGUE_SIM_PORT_NUM_G : natural range 1024 to 49151 := 11000);
   port (
      -----------------------
      -- Application Ports --
      -----------------------
      -- System Ports
      digPwrEn      : out   sl;
      anaPwrEn      : out   sl;
      syncDigDcDc   : out   sl;
      syncAnaDcDc   : out   sl;
      syncDcDc      : out   slv(6 downto 0);
      daqTg         : in    sl;
      connTgOut     : out   sl;
      connMps       : out   sl;
      connRun       : in    sl;
      -- Fast ADC Ports
      adcSpiClk     : out   sl;
      adcSpiData    : inout sl;
      adcSpiCsL     : out   sl;
      adcPdwn       : out   sl;
      adcClkP       : out   sl;
      adcClkM       : out   sl;
      adcDoClkP     : in    sl;
      adcDoClkM     : in    sl;
      adcFrameClkP  : in    sl;
      adcFrameClkM  : in    sl;
      adcMonDoutP   : in    slv(4 downto 0);
      adcMonDoutN   : in    slv(4 downto 0);
      -- Slow ADC
      slowAdcSclk   : out   sl;
      slowAdcDin    : out   sl;
      slowAdcCsL    : out   sl;
      slowAdcRefClk : out   sl;
      slowAdcDout   : in    sl;
      slowAdcDrdy   : in    sl;
      slowAdcSync   : out   sl;
      -- Slow DACs Port
      sDacCsL       : out   slv(4 downto 0);
      hsDacCsL      : out   sl;
      hsDacLoad     : out   sl;
      dacClrL       : out   sl;
      dacSck        : out   sl;
      dacDin        : out   sl;
      -- ASIC Gbps Ports
      asicDataP     : in    slv(23 downto 0);
      asicDataN     : in    slv(23 downto 0);
      -- ASIC DM Ports
      asicDMSN      : in    sl;
      -- ASIC Control Ports
      asicR0        : out   sl;
      asicGlblRst   : out   sl;
      asicSro       : out   sl;
      asicInj       : out   sl;
      asicAcq       : out   sl;
      asicRoClkP    : out   slv(3 downto 0);
      asicRoClkN    : out   slv(3 downto 0);
      -- SACI Ports
      asicSaciCmd   : out   sl;
      asicSaciClk   : out   sl;
      asicSaciSel   : out   slv(2 downto 0);
      asicSaciRsp   : in    sl;
      -- Spare Ports
      spareHpP      : inout slv(11 downto 0);
      spareHpN      : inout slv(11 downto 0);
      spareHrP      : inout slv(5 downto 0);
      spareHrN      : inout slv(5 downto 0);
      -- Clock Jitter Cleaner
      cjcRstL       : out   sl;
      cjcRate       : out   slv(1 downto 0);
      cjcMode       : out   sl;
      cjcCsL        : out   sl;
      cjcSck        : out   sl;
      cjcSdi        : out   sl;
      cjcSdo        : in    sl;
      cjcClkInP     : out   slv(1 downto 0);
      cjcClkInN     : out   slv(1 downto 0);
      cjcClkOutP    : in    slv(1 downto 0);
      cjcClkOutN    : in    slv(1 downto 0);
      cjcClkLosL    : in    slv(1 downto 0);
      cjcPllLolL    : in    sl;
      -- GTH Ports
      gtRxP         : in    sl;
      gtRxN         : in    sl;
      gtTxP         : out   sl;
      gtTxN         : out   sl;
      gtRefP        : in    sl;
      gtRefN        : in    sl;
      smaRxP        : in    sl;
      smaRxN        : in    sl;
      smaTxP        : out   sl;
      smaTxN        : out   sl;
      ----------------
      -- Core Ports --
      ----------------
      -- Board IDs Ports
      snIoAdcCard   : inout sl := '1';
      snIoCarrStub  : in    sl;
      snIoCarrier   : inout sl := '1';
      -- QSFP Ports
      qsfpClkP      : in    sl;
      qsfpClkN      : in    sl;
      qsfpRxP       : in    slv(3 downto 0) := (others => '0');
      qsfpRxN       : in    slv(3 downto 0) := (others => '1');
      qsfpTxP       : out   slv(3 downto 0);
      qsfpTxN       : out   slv(3 downto 0);
      qsfpLpMode    : inout sl              := 'Z';
      qsfpModSel    : inout sl              := 'Z';
      qsfpInitL     : inout sl              := 'Z';
      qsfpRstL      : inout sl              := 'Z';
      qsfpPrstL     : inout sl              := 'Z';
      qsfpScl       : inout sl              := 'Z';
      qsfpSda       : inout sl              := 'Z';
      qsfpTimingClkP: in    sl;
      qsfpTimingClkN: in    sl;
      -- DDR Ports
      ddrClkP       : in    sl;
      ddrClkN       : in    sl;
      ddrBg         : out   sl;
      ddrCkP        : out   sl;
      ddrCkN        : out   sl;
      ddrCke        : out   sl;
      ddrCsL        : out   sl;
      ddrOdt        : out   sl;
      ddrAct        : out   sl;
      ddrRstL       : out   sl;
      ddrA          : out   slv(16 downto 0);
      ddrBa         : out   slv(1 downto 0);
      ddrDm         : inout slv(3 downto 0);
      ddrDq         : inout slv(31 downto 0);
      ddrDqsP       : inout slv(3 downto 0);
      ddrDqsN       : inout slv(3 downto 0);
      ddrPg         : in    sl              := '1';
      ddrPwrEn      : out   sl;
      -- SYSMON Ports
      vPIn          : in    sl              := '0';
      vNIn          : in    sl              := '1');
end Pix2PgpThriglav;

architecture top_level of Pix2PgpThriglav is

   signal axilReadMaster  : AxiLiteReadMasterType;
   signal axilReadSlave   : AxiLiteReadSlaveType;
   signal axilWriteMaster : AxiLiteWriteMasterType;
   signal axilWriteSlave  : AxiLiteWriteSlaveType;

   signal axisMasters : AxiStreamMasterArray(3 downto 0);
   signal axisSlaves  : AxiStreamSlaveArray(3 downto 0);

   signal auxMasters : AxiStreamMasterArray(1 downto 0);
   signal auxSlaves  : AxiStreamSlaveArray(1 downto 0);

   signal axiReadMaster  : AxiReadMasterType;
   signal axiReadSlave   : AxiReadSlaveType;
   signal axiWriteMaster : AxiWriteMasterType;
   signal axiWriteSlave  : AxiWriteSlaveType;

   signal sysClk : sl;
   signal sysRst : sl;
   signal mbIrq  : slv(7 downto 0);
   -- snIO and Dig monitoring share signals
   signal asicDM          : sl;

begin

--   U_App : entity work.Application
--      generic map (
--         TPD_G             => TPD_G,
--         BUILD_INFO_G      => BUILD_INFO_G,
--         SIMULATION_G      => ROGUE_SIM_EN_G)
--      port map (
--         ----------------------
--         -- Top Level Interface
--         ----------------------
--         -- System Clock and Reset
--         sysClk           => sysClk,
--         sysRst           => sysRst,
--         -- AXI-Lite Register Interface (sysClk domain)
--         -- Register Address Range = [0x80000000:0xFFFFFFFF]
--         sAxilReadMaster  => axilReadMaster,
--         sAxilReadSlave   => axilReadSlave,
--         sAxilWriteMaster => axilWriteMaster,
--         sAxilWriteSlave  => axilWriteSlave,
--         -- AXI Stream, one per QSFP lane (sysClk domain)
--         mAxisMasters     => axisMasters,
--         mAxisSlaves      => axisSlaves,
--         -- Auxiliary AXI Stream, (sysClk domain)
--         -- 0 is pseudo scope, 1 is slow adc monitoring
--         mAuxAxisMasters  => auxMasters,
--         mAuxAxisSlaves   => auxSlaves,
--         -- DDR's AXI Memory Interface (sysClk domain)
--         -- DDR Address Range = [0x00000000:0x3FFFFFFF]
--         mAxiReadMaster   => axiReadMaster,
--         mAxiReadSlave    => axiReadSlave,
--         mAxiWriteMaster  => axiWriteMaster,
--         mAxiWriteSlave   => axiWriteSlave,
--         -- Microblaze's Interrupt bus (sysClk domain)
--         mbIrq            => mbIrq,
--         -----------------------
--         -- Application Ports --
--         -----------------------
--         -- System Ports
--         digPwrEn         => digPwrEn,
--         anaPwrEn         => anaPwrEn,
--         syncDigDcDc      => syncDigDcDc,
--         syncAnaDcDc      => syncAnaDcDc,
--         syncDcDc         => syncDcDc,
--         daqTg            => daqTg,
--         connTgOut        => connTgOut,
--         connMps          => connMps,
--         connRun          => connRun,
--         -- Fast ADC Ports
--         adcSpiClk        => adcSpiClk,
--         adcSpiData       => adcSpiData,
--         adcSpiCsL        => adcSpiCsL,
--         adcPdwn          => adcPdwn,
--         adcClkP          => adcClkP,
--         adcClkM          => adcClkM,
--         adcDoClkP        => adcDoClkP,
--         adcDoClkM        => adcDoClkM,
--         adcFrameClkP     => adcFrameClkP,
--         adcFrameClkM     => adcFrameClkM,
--         adcMonDoutP      => adcMonDoutP,
--         adcMonDoutN      => adcMonDoutN,
--         -- Slow ADC
--         slowAdcSclk      => slowAdcSclk,
--         slowAdcDin       => slowAdcDin,
--         slowAdcCsL       => slowAdcCsL,
--         slowAdcRefClk    => slowAdcRefClk,
--         slowAdcDout      => slowAdcDout,
--         slowAdcDrdy      => slowAdcDrdy,
--         slowAdcSync      => slowAdcSync,
--         -- Slow DACs Port
--         sDacCsL          => sDacCsL,
--         hsDacCsL         => hsDacCsL,
--         hsDacLoad        => hsDacLoad,
--         dacClrL          => dacClrL,
--         dacSck           => dacSck,
--         dacDin           => dacDin,
--         -- ASIC Gbps Ports
--         asicDataP        => asicDataP,
--         asicDataN        => asicDataN,
--         -- ASIC Control Ports
--         asicR0           => asicR0,
--         asicGlblRst      => asicGlblRst,
--         asicInj          => asicInj,
--         asicAcq          => asicAcq,
--         asciClkSerP      => asicRoClkP,
--         asciClkSerN      => asicRoClkN,
--         asicDMSN         => snIoCarrStub,
--         -- SACI Ports
--         asicSaciCmd      => asicSaciCmd,
--         asicSaciClk      => asicSaciClk,
--         asicSaciSel      => asicSaciSel,
--         asicSaciRsp      => asicSaciRsp,
--         -- Spare Ports
--         spareHpP         => spareHpP,
--         spareHpN         => spareHpN,
--         spareHrP         => spareHrP,
--         spareHrN         => spareHrN,
--         --timing GTH ports
--         gtTimingRxP      => qsfpRxP(3),
--         gtTimingRxN      => qsfpRxN(3),
--         gtTimingTxP      => qsfpTxP(3),
--         gtTimingTxN      => qsfpTxN(3),
--         -- Clock Jitter Cleaner
--         cjcRstL          => cjcRstL,
--         cjcRate          => cjcRate,
--         cjcMode          => cjcMode,
--         cjcCsL           => cjcCsL,
--         cjcSck           => cjcSck,
--         cjcSdi           => cjcSdi,
--         cjcSdo           => cjcSdo,
--         cjcClkInP        => cjcClkInP,
--         cjcClkInN        => cjcClkInN,
--         cjcClkOutP       => cjcClkOutP,
--         cjcClkOutN       => cjcClkOutN,
--         cjcClkLosL       => cjcClkLosL,
--         cjcPllLolL       => cjcPllLolL,
--         -- GTH Ports
--         gtRxP            => gtRxP,
--         gtRxN            => gtRxN,
--         gtTxP            => gtTxP,
--         gtTxN            => gtTxN,
--         gtRefP           => gtRefP,
--         gtRefN           => gtRefN,
--         smaRxP           => smaRxP,
--         smaRxN           => smaRxN,
--         smaTxP           => smaTxP,
--         smaTxN           => smaTxN
--      );

--   U_Core : entity epix_hr_core.EpixHrCore
--      generic map (
--         TPD_G                => TPD_G,
--         NUM_LANES_G          => 3,
--         RATE_G               => "6.25Gbps",
--         BUILD_INFO_G         => BUILD_INFO_G,
--         ROGUE_SIM_EN_G       => ROGUE_SIM_EN_G,
--         ROGUE_SIM_PORT_NUM_G => ROGUE_SIM_PORT_NUM_G)
--      port map (
--         ----------------------
--         -- Top Level Interface
--         ----------------------
--         -- System Clock and Reset
--         sysClk           => sysClk,
--         sysRst           => sysRst,
--         -- AXI-Lite Register Interface (sysClk domain)
--         -- Register Address Range = [0x80000000:0xFFFFFFFF]
--         mAxilReadMaster  => axilReadMaster,
--         mAxilReadSlave   => axilReadSlave,
--         mAxilWriteMaster => axilWriteMaster,
--         mAxilWriteSlave  => axilWriteSlave,
--         -- AXI Stream, one per QSFP lane (sysClk domain)
--         sAxisMasters     => axisMasters(2 downto 0),
--         sAxisSlaves      => axisSlaves(2 downto 0),
--         -- Auxiliary AXI Stream, (sysClk domain)
--         -- 0 is pseudo scope, 1 is slow adc monitoring
--         sAuxAxisMasters  => auxMasters,
--         sAuxAxisSlaves   => auxSlaves,
--         -- DDR's AXI Memory Interface (sysClk domain)
--         -- DDR Address Range = [0x00000000:0x3FFFFFFF]
--         sAxiReadMaster   => axiReadMaster,
--         sAxiReadSlave    => axiReadSlave,
--         sAxiWriteMaster  => axiWriteMaster,
--         sAxiWriteSlave   => axiWriteSlave,
--         -- Microblaze's Interrupt bus (sysClk domain)
--         mbIrq            => mbIrq,
--         ----------------
--         -- Core Ports --
--         ----------------
--         -- Board IDs Ports
--         snIoAdcCard      => snIoAdcCard,
--         snIoCarrier      => snIoCarrier,
--         snCarrierOut     => asicDM,
--         -- QSFP Ports
--         qsfpRxP          => qsfpRxP(2 downto 0),
--         qsfpRxN          => qsfpRxN(2 downto 0),
--         qsfpTxP          => qsfpTxP(2 downto 0),
--         qsfpTxN          => qsfpTxN(2 downto 0),
--         qsfpClkP         => qsfpClkP,
--         qsfpClkN         => qsfpClkN,
--         qsfpLpMode       => qsfpLpMode,
--         qsfpModSel       => qsfpModSel,
--         qsfpInitL        => qsfpInitL,
--         qsfpRstL         => qsfpRstL,
--         qsfpPrstL        => qsfpPrstL,
--         qsfpScl          => qsfpScl,
--         qsfpSda          => qsfpSda,
--         -- DDR Ports
--         ddrClkP          => ddrClkP,
--         ddrClkN          => ddrClkN,
--         ddrBg            => ddrBg,
--         ddrCkP           => ddrCkP,
--         ddrCkN           => ddrCkN,
--         ddrCke           => ddrCke,
--         ddrCsL           => ddrCsL,
--         ddrOdt           => ddrOdt,
--         ddrAct           => ddrAct,
--         ddrRstL          => ddrRstL,
--         ddrA             => ddrA,
--         ddrBa            => ddrBa,
--         ddrDm            => ddrDm,
--         ddrDq            => ddrDq,
--         ddrDqsP          => ddrDqsP,
--         ddrDqsN          => ddrDqsN,
--         ddrPg            => ddrPg,
--         ddrPwrEn         => ddrPwrEn,
--         -- SYSMON Ports
--         vPIn             => vPIn,
--         vNIn             => vNIn);

end top_level;
