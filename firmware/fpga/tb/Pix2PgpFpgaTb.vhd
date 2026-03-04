library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

-- required for writing/reading std_logic etc.
use std.textio.all;
use ieee.std_logic_textio.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.SsiPkg.all;
use surf.Pgp4Pkg.all;
use surf.AxiStreamPacketizer2Pkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpAsicPkg.all;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpFpgaTb is
   generic(
      TPD_G          : time      := 1 ns;
      RST_ASYNC_G    : boolean   := True;
      RST_POLARITY_G : std_logic := '1';
      FPGA_SYNTH_G   : boolean   := True;
      NUM_VC_G       : natural   := 1
   );
   port(
      -- General Interface
      pgpRxClk     : in  sl;
      phyRxClk     : in  sl;
      rst          : in  sl := not RST_POLARITY_G;
      linkReady    : out sl;
      -- Pix2Pgp Interface
      pgpDin       : in  slv(SER_DWIDTH_C-1 downto 0);
      pgpDinValid  : in  sl;
      pgpDinReady  : out sl;
      -- FPGA RX Interface
      pgp4RxMaster : out AxiStreamMasterType;
      pgp4RxSlave  : in  AxiStreamSlaveType := AXI_STREAM_SLAVE_INIT_C;
      -- Debug Output
      pgpDoutValid : out sl;
      pgpDout      : out slv(PIX2PGP_DATABUS_DWIDTH_C-1 downto 0));
end entity Pix2PgpFpgaTb;

architecture test of Pix2PgpFpgaTb is

   signal pgpData66b      : slv(65 downto 0) := (others => '0');
   signal pgpData66bValid : sl := '0';

   signal pgpRxCtrl   : AxiStreamCtrlArray(NUM_VC_G-1 downto 0) := (others => AXI_STREAM_CTRL_INIT_C);
   signal pgpRxOut     : Pgp4RxOutType := PGP4_RX_OUT_INIT_C;
   signal pgpRxMasters : AxiStreamMasterArray(NUM_VC_G-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);

   signal remRxLinkReady : sl := '0';
   signal locRxLinkReady : sl := '0';

   signal gboxMaster     : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;

begin

    U_SerializerReverseGearbox : entity surf.Gearbox
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         SLAVE_WIDTH_G  => SER_DWIDTH_C,
         MASTER_WIDTH_G => PGP_DWIDTH_C+2)
      port map (
         -- Clock and Reset
         clk            => phyRxClk,
         rst            => rst,
         -- Slave Interface
         slaveValid     => pgpDinValid,
         slaveReady     => pgpDinReady,
         slaveData      => pgpDin,
         slaveBitOrder  => '0',
         -- Master Interface
         masterBitOrder => '0',
         masterReady    => '1', -- always ready
         masterValid    => pgpData66bValid,
         masterData     => pgpData66b);

    U_PgpRx : entity surf.Pgp4Rx
     generic map(
        TPD_G          => TPD_G,
        RST_POLARITY_G => RST_POLARITY_G,
        RST_ASYNC_G    => RST_ASYNC_G,
        NUM_VC_G       => NUM_VC_G,
        LITE_EN_G      => true)
     port map(
        -- User Transmit interface
        pgpRxClk     => pgpRxClk,
        pgpRxRst     => rst,
        pgpRxOut     => pgpRxOut,
        pgpRxMasters => pgpRxMasters,
        pgpRxCtrl    => pgpRxCtrl,

        -- Status of local receive fifos
        remRxFifoCtrl  => open,
        remRxLinkReady => remRxLinkReady,
        locRxLinkReady => locRxLinkReady,

        -- PHY interface
        phyRxClk      => phyRxClk,
        phyRxRst      => rst,
        phyRxInit     => open,
        phyRxActive   => '1',
        phyRxValid    => pgpData66bValid,
        phyRxHeader   => pgpData66b(65 downto 64),
        phyRxData     => pgpData66b(63 downto 0),
        phyRxStartSeq => '0',
        phyRxSlip     => open);

   U_FpgaGearbox : entity surf.AxiStreamGearbox
      generic map(
         -- General Configurations
         TPD_G               => TPD_G,
         RST_POLARITY_G      => RST_POLARITY_G,
         RST_ASYNC_G         => RST_ASYNC_G,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => ASIC_TX_AXI_CONFIG_C,
         MASTER_AXI_CONFIG_G => ASIC_DATA_AXI_CONFIG_C)
      port map(
         -- Clock and reset
         axisClk     => pgpRxClk,
         axisRst     => rst,
         -- Slave Port
         sAxisMaster => pgpRxMasters(0),
         sSideBand   => (others => '0'),
         sAxisSlave  => open,
         -- Master Port
         mAxisMaster => gboxMaster,
         mSideBand   => open,
         mAxisSlave  => AXI_STREAM_SLAVE_FORCE_C);

   linkReady <= remRxLinkReady and locRxLinkReady;

   pgp4RxMaster <= gboxMaster;

   pgpDoutValid <= gboxMaster.tValid;
   pgpDout      <= gboxMaster.tData(PIX2PGP_DATABUS_DWIDTH_C-1 downto 0);

end architecture;
