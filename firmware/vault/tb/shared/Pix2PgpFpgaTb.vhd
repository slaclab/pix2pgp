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
      clk         : in  sl;
      rst         : in  sl := not RST_POLARITY_G;
      -- Pix2Pgp Interface
      pgpDin      : in  slv(31 downto 0);
      pgpDinValid : in  sl;
      pgpDinReady : out sl;
      -- FPGA RX Interface
      pgpValid    : out sl;
      pgpData     : out slv(DATABUS_DWIDTH_C-1 downto 0));
end entity Pix2PgpFpgaTb;

architecture test of Pix2PgpFpgaTb is

   signal pgpData66b      : slv(65 downto 0) := (others => '0');
   signal pgpData66bValid : sl := '0';

   signal pgpRxCtrl   : AxiStreamCtrlArray(NUM_VC_G-1 downto 0) := (others => AXI_STREAM_CTRL_INIT_C);
   signal pgpRxOut     : Pgp4RxOutType := PGP4_RX_OUT_INIT_C;
   signal pgpRxMasters : AxiStreamMasterArray(NUM_VC_G-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);

   signal pgpTxSlave   : AxiStreamSlaveType;
   signal pgpTxMaster  : AxiStreamMasterType;

   -- axi-stream gearbox configuration
   constant SLAVE_AXI_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C         => false,
      TDATA_BYTES_C      => PGP_DWIDTH_C/8,
      TDEST_BITS_C       => 4,
      TID_BITS_C         => 0,
      TKEEP_MODE_C       => TKEEP_NORMAL_C,
      TUSER_BITS_C       => 4,
      TUSER_MODE_C       => TUSER_NORMAL_C);

   constant MASTER_AXI_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C         => false,
      TDATA_BYTES_C      => DATABUS_DWIDTH_C/8,
      TDEST_BITS_C       => 4,
      TID_BITS_C         => 0,
      TKEEP_MODE_C       => TKEEP_NORMAL_C,
      TUSER_BITS_C       => 4,
      TUSER_MODE_C       => TUSER_NORMAL_C);

begin

    U_SerializerReverseGearbox : entity surf.Gearbox
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         SLAVE_WIDTH_G  => 32,
         MASTER_WIDTH_G => 66)
      port map (
         -- Clock and Reset
         clk            => clk,
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
        SKIP_EN_G      => false,
        LITE_EN_G      => true)
     port map(
        -- User Transmit interface
        pgpRxClk     => clk,
        pgpRxRst     => rst,
        pgpRxOut     => pgpRxOut,
        pgpRxMasters => pgpRxMasters,
        pgpRxCtrl    => pgpRxCtrl,

        -- Status of local receive fifos
        remRxFifoCtrl  => open,
        remRxLinkReady => open,
        locRxLinkReady => open,

        -- PHY interface
        phyRxClk      => clk,
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
         SLAVE_AXI_CONFIG_G  => SLAVE_AXI_CONFIG_C,
         MASTER_AXI_CONFIG_G => MASTER_AXI_CONFIG_C)
      port map(
         -- Clock and reset
         axisClk     => clk,
         axisRst     => rst,
         -- Slave Port
         sAxisMaster => pgpRxMasters(0),
         sSideBand   => (others => '0'),
         sAxisSlave  => open,
         -- Master Port
         mAxisMaster => pgpTxMaster,
         mSideBand   => open,
         mAxisSlave  => pgpTxSlave);

   pgpTxSlave.tReady <= '1';
   pgpValid          <= pgpTxMaster.tValid;
   pgpData           <= pgpTxMaster.tData(DATABUS_DWIDTH_C-1 downto 0);

   -- Instantiate the design under test

end architecture;
