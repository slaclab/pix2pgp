-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Wrapper for Pix2PgpAsicStreamRx;
--              to-be-used for verification purposes;
--              keeping ports non-complex to comply with sysVerilog
--
-- How-To Change from ASIC to ASIC:
-- What needs to be edited is:
-- 1. entity port definitions:
--    the number of pgpDin0, pgpDin1, pgpDin2, ...etc.
--    i. (same amount as number of lanes, or NUM_OF_SERIALIZERS_C)
--
-- 2. port-to-signal allocation (bottom of architecture):
--    the allocation of pgpDin0, pgpDin1, pgpDin2... to the pgpDin(i) array:
--     i.    pgpDin(0) <= pgpDin0;
--     ii.   pgpDin(1) <= pgpDin1;
--     iii.  ...etc.
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
use surf.SsiPkg.all;
use surf.Pgp4Pkg.all;
use surf.AxiStreamPacketizer2Pkg.all;
use surf.AxiLitePkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpAsicPkg.all;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpSparkPixSFpgaRxTop is
   generic(
      TPD_G                  : time      := 1 ns;
      RST_ASYNC_G            : boolean   := True;
      RST_POLARITY_G         : std_logic := '1';
      NUM_VC_G               : natural   := 1;
      AXIS_FIFO_ADDR_WIDTH_G : positive  := 11;
      TUSER_WIDTH_G          : positive  := 8;
      TID_WIDTH_G            : positive  := 8;
      TDEST_WIDTH_G          : positive  := 8;
      -- IP Integrator AXI Stream Configuration
      AXIS_CONFIG_G          : AxiStreamConfigType := ssiAxiStreamConfig(16));
   port (
      -- General Interface
      pgpRxClk        : in  std_logic;
      sro             : in  std_logic;
      daq             : in  std_logic;
      rst             : in  std_logic := not RST_POLARITY_G;
      asicRstL        : in  std_logic;
      -- Pix2Pgp Interface
      pgpDin0         : in  std_logic_vector(SER_DWIDTH_C-1 downto 0);
      pgpDin1         : in  std_logic_vector(SER_DWIDTH_C-1 downto 0);
      pgpDin2         : in  std_logic_vector(SER_DWIDTH_C-1 downto 0);
      pgpDin3         : in  std_logic_vector(SER_DWIDTH_C-1 downto 0);
      pgpDin4         : in  std_logic_vector(SER_DWIDTH_C-1 downto 0);
      pgpDin5         : in  std_logic_vector(SER_DWIDTH_C-1 downto 0);
      pgpDin6         : in  std_logic_vector(SER_DWIDTH_C-1 downto 0);
      pgpDin7         : in  std_logic_vector(SER_DWIDTH_C-1 downto 0);
      pgpDinValid     : in  std_logic_vector(NUM_OF_SERIALIZERS_C-1 downto 0);
      pgpDinReady     : out std_logic_vector(NUM_OF_SERIALIZERS_C-1 downto 0);
      linkReady       : out std_logic_vector(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- AXI interface
      axisClk         : out std_logic;
      axisRst         : out std_logic;
      m_axis_aresetn  : in  std_logic;
      m_axis_aclk     : in  std_logic;
      m_axis_tvalid   : out std_logic;
      m_axis_tdata    : out std_logic_vector((8*AXIS_CONFIG_G.TDATA_BYTES_C)-1 downto 0);
      m_axis_tstrb    : out std_logic_vector(AXIS_CONFIG_G.TDATA_BYTES_C-1 downto 0);
      m_axis_tkeep    : out std_logic_vector(AXIS_CONFIG_G.TDATA_BYTES_C-1 downto 0);
      m_axis_tlast    : out std_logic;
      m_axis_tdest    : out std_logic_vector(TDEST_WIDTH_G-1 downto 0);
      m_axis_tid      : out std_logic_vector(TID_WIDTH_G-1 downto 0);
      m_axis_tuser    : out std_logic_vector(TUSER_WIDTH_G-1 downto 0);
      m_axis_tready   : in  std_logic;
      stream_rx_tlast : out std_logic);

end entity Pix2PgpSparkPixSFpgaRxTop;

architecture behav of Pix2PgpSparkPixSFpgaRxTop is

   type pgpDataAsicType is array (0 to NUM_OF_SERIALIZERS_C-1) of slv(SER_DWIDTH_C-1 downto 0);

   signal pgpDin         : pgpDataAsicType := (others => (others => '0'));

   signal pgp4RxMaster   : AxiStreamMasterArray(0 to NUM_OF_SERIALIZERS_C-1) := (others => AXI_STREAM_MASTER_INIT_C);
   signal pgp4RxSlave    : AxiStreamSlaveArray(0 to NUM_OF_SERIALIZERS_C-1) := (others => AXI_STREAM_SLAVE_INIT_C);

   signal asicRxMaster   : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal asicRxSlave    : AxiStreamSlaveType  := AXI_STREAM_SLAVE_FORCE_C; -- force to ready

   signal allLanesMaster : AxiStreamMasterArray(0 to NUM_OF_SERIALIZERS_C-1) := (others => AXI_STREAM_MASTER_INIT_C);
   signal allLanesSlave  : AxiStreamSlaveArray(0 to NUM_OF_SERIALIZERS_C-1)  := (others => AXI_STREAM_SLAVE_INIT_C);

   signal pgp4RxLinkUp : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal ipIntegratorMaster : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal ipIntegratorSlave  : AxiStreamSlaveType  := AXI_STREAM_SLAVE_FORCE_C; -- force to ready

   signal axiFifoRst : sl := '0';

begin

   -- lanes
   GEN_LANE: for lane in 0 to NUM_OF_SERIALIZERS_C-1 generate

      -- pgp4 wrapper
      U_FPGA : entity pix2pgp.Pix2PgpFpgaTb
       generic map(
          TPD_G          => TPD_G,
          RST_ASYNC_G    => false,
          RST_POLARITY_G => RST_POLARITY_G,
          NUM_VC_G       => NUM_VC_G)
       port map(
          -- General Interface
          pgpRxClk     => pgpRxClk,
          phyRxClk     => pgpRxClk,
          rst          => rst,
          linkReady    => pgp4RxLinkUp(lane),
          -- Pix2Pgp Interface
          pgpDin       => pgpDin(lane),
          pgpDinValid  => pgpDinValid(lane),
          pgpDinReady  => pgpDinReady(lane),
          -- FPGA RX Interface
          pgp4RxMaster => pgp4RxMaster(lane),
          pgp4RxSlave  => pgp4RxSlave(lane));

   end generate GEN_LANE;

   -- asic stream receiver and merger
   U_ASIC_STREAM_RX : entity pix2pgp.Pix2PgpAsicStreamRx
      generic map(
         TPD_G                  => TPD_G,
         RST_ASYNC_G            => false,
         RST_POLARITY_G         => RST_POLARITY_G,
         ASIC_ID_G              => 0,
         LANE_PIPE_STAGES_G     => 1,
         TRG_FIFO_ADDR_WIDTH_G  => 6,
         META_FIFO_ADDR_WIDTH_G => 6,
         AXIS_FIFO_ADDR_WIDTH_G => AXIS_FIFO_ADDR_WIDTH_G,
         AXIL_BASE_ADDR_G       => x"0800_0000")
      port map(
         -- General Interface
         pgpRxClk        => pgpRxClk,
         pgpRxRst        => rst,
         -- ASIC Domain Interface
         asicClk         => pgpRxClk,
         asicRst         => asicRstL,
         asicSro         => sro,
         asicSroEn       => '1',
         sysDaq          => daq,
         -- PGP4Rx Interface (on pgpRxClk domain)
         pgp4RxMaster    => pgp4RxMaster,
         pgp4RxSlave     => pgp4RxSlave,
         pgp4RxLinkUp    => pgp4RxLinkUp,
         -- AXI-Stream Rx Interface (on pgpRxClk domain)
         asicRxMaster    => asicRxMaster,
         asicRxSlave     => asicRxSlave,
         -- AXI-Lite Interface
         axilClk         => pgpRxClk,
         axilRst         => rst,
         axilReadMaster  => AXI_LITE_READ_MASTER_INIT_C,
         axilReadSlave   => open,
         axilWriteMaster => AXI_LITE_WRITE_MASTER_INIT_C,
         axilWriteSlave  => open);

   U_Fifo : entity surf.AxiStreamFifoV2
      generic map (
         -- General Configurations
         TPD_G               => TPD_G,
         RST_ASYNC_G         => RST_ASYNC_G,
         -- FIFO configurations
         FIFO_ADDR_WIDTH_G   => AXIS_FIFO_ADDR_WIDTH_G,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => PIX2PGP_FPGA_AXI_CONFIG_C,
         MASTER_AXI_CONFIG_G => AXIS_CONFIG_G)
      port map (
         -- Slave Port
         sAxisClk    => pgpRxClk,
         sAxisRst    => axiFifoRst,
         sAxisMaster => asicRxMaster,
         sAxisSlave  => asicRxSlave,
         -- Status Port
         -- Master Port
         mAxisClk    => m_axis_aclk,
         mAxisRst    => axiFifoRst,
         mAxisMaster => ipIntegratorMaster,
         mAxisSlave  => ipIntegratorSlave);

   -- Map PgpRxMasters to AXI
   U_axisMaster : entity surf.MasterAxiStreamIpIntegrator
      generic map (
         INTERFACENAME   => "M_AXIS",
         TUSER_WIDTH     => TUSER_WIDTH_G,
         TID_WIDTH       => TID_WIDTH_G,
         TDEST_WIDTH     => TDEST_WIDTH_G,
         TDATA_NUM_BYTES => AXIS_CONFIG_G.TDATA_BYTES_C)
      port map (
         -- IP Integrator AXI Stream Interface
         M_AXIS_ACLK    => m_axis_aclk,
         M_AXIS_ARESETN => m_axis_aresetn,
         M_AXIS_TVALID  => m_axis_tvalid,
         M_AXIS_TDATA   => m_axis_tdata,
         M_AXIS_TSTRB   => m_axis_tstrb,
         M_AXIS_TKEEP   => m_axis_tkeep,
         M_AXIS_TLAST   => m_axis_tlast,
         M_AXIS_TDEST   => m_axis_tdest,
         M_AXIS_TID     => m_axis_tid,
         M_AXIS_TUSER   => m_axis_tuser,
         M_AXIS_TREADY  => m_axis_tready,
         -- SURF AXI Stream Interface
         axisClk        => axisClk,        -- same as SlaveAxiStreamIpIntegrator
         axisRst        => axisRst,        -- same as SlaveAxiStreamIpIntegrator
         axisMaster     => ipIntegratorMaster,
         axisSlave      => ipIntegratorSlave);

   linkReady <= pgp4RxLinkUp;

   axiFifoRst <= ite(toBoolean(RST_POLARITY_G), rst, not(rst));

   stream_rx_tlast <= asicRxMaster.tLast;

   -- expand as necessary
   pgpDin(0) <= pgpDin0;
   pgpDin(1) <= pgpDin1;
   pgpDin(2) <= pgpDin2;
   pgpDin(3) <= pgpDin3;
   pgpDin(4) <= pgpDin4;
   pgpDin(5) <= pgpDin5;
   pgpDin(6) <= pgpDin6;
   pgpDin(7) <= pgpDin7;

end behav;
