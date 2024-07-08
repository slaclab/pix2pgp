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

entity Pix2PgpTb is
   generic(
      TPD_G                    : time     := 1 ns;
      RST_ASYNC_G              : boolean  := True;
      RST_POLARITY_G           : sl       := '1';
      GHDL_SIM_G               : boolean  := True;
      DATAFIFO_PIPE_G          : positive := 2;
      STATUSFIFO_PIPE_G        : positive := 2;
      DATAFIFO_FWFT_G          : boolean  := True;
      PIPELINE_BRIDGE_DATA_G   : boolean  := False;
      PIPELINE_BRIDGE_STATUS_G : boolean  := True;
      COLMANAGER_DEPTH_G       : integer  := 6;
      COLMANAGER_FULL_LVL_G    : integer  := 5;
      PGPADAPTER_DEPTH_G       : integer  := 6;
      PGPADAPTER_FULL_LVL_G    : integer  := 5;
      SUPER_FIFO_RD_DELAY_G    : natural  := 3;
      ARB_FIFO_RD_DELAY_G      : natural  := 1;
      ARB_DOUT_PIPE_G          : natural  := 2;
      NUM_VC_G                 : natural  := 1
   );
   port(
      -- General Interface
      clk      : in  sl;
      rst      : in  sl;
      sro      : in  sl;
      -- Pixel Interface
      tok      : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      tokFb    : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      ackN     : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      wrEn     : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      din      : in  Pix2PgpSparseDinArray;
      pause    : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- FPGA RX Interface
      pgpValid : out sl;
      pgpData  : out slv(39 downto 0));
end entity Pix2PgpTb;

architecture test of Pix2PgpTb is

   signal columnEnable : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := x"FFFFFF";

   signal txReady      : sl := '1';
   signal txValid      : sl := '0';
   signal txData       : slv(63 downto 0) := (others => '0');
   signal txSof        : sl := '0';
   signal txEof        : sl := '0';
   signal txEofe       : sl := '0';

   signal fillFifos    : sl := '0';
   signal fillCnt      : natural range 0 to 1023;

   signal phyTxValid  : sl := '0';
   signal phyTxReady  : sl := '1';
   signal phyTxData   : slv(65 downto 0) := (others => '0');

   signal pgpData32b  : slv(31 downto 0) := (others => '0');
   signal pgpData66b  : slv(65 downto 0) := (others => '0');
   signal pgpData32bValid : sl := '0';
   signal pgpData32bReady : sl := '0';
   signal pgpData66bValid : sl := '0';

   signal pgpRxCtrl   : AxiStreamCtrlArray(NUM_VC_G-1 downto 0) := (others => AXI_STREAM_CTRL_INIT_C);
   signal pgpRxOut     : Pgp4RxOutType := PGP4_RX_OUT_INIT_C;
   signal pgpRxMasters : AxiStreamMasterArray(NUM_VC_G-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);

begin

  -- Instantiate the design under test
   U_Pix2PgpTop : entity pix2pgp.Pix2PgpTop
      generic map (
         TPD_G                    => TPD_G,
         RST_ASYNC_G              => RST_ASYNC_G,
         RST_POLARITY_G           => RST_POLARITY_G,
         GHDL_SIM_G               => GHDL_SIM_G,
         DATAFIFO_FWFT_G          => DATAFIFO_FWFT_G,
         PIPELINE_BRIDGE_DATA_G   => PIPELINE_BRIDGE_DATA_G,
         PIPELINE_BRIDGE_STATUS_G => PIPELINE_BRIDGE_STATUS_G,
         COLMANAGER_DEPTH_G       => COLMANAGER_DEPTH_G,
         COLMANAGER_FULL_LVL_G    => COLMANAGER_FULL_LVL_G,
         PGPADAPTER_DEPTH_G       => PGPADAPTER_DEPTH_G,
         PGPADAPTER_FULL_LVL_G    => PGPADAPTER_FULL_LVL_G,
         DATAFIFO_PIPE_G          => DATAFIFO_PIPE_G,
         STATUSFIFO_PIPE_G        => STATUSFIFO_PIPE_G,
         SUPER_FIFO_RD_DELAY_G    => SUPER_FIFO_RD_DELAY_G,
         ARB_FIFO_RD_DELAY_G      => ARB_FIFO_RD_DELAY_G,
         ARB_DOUT_PIPE_G          => ARB_DOUT_PIPE_G)
      port map (
         -- General Interface
         sparseClk    => clk,
         pgpClk       => clk,
         rst          => rst,
         columnEnable => columnEnable,
         -- Column Manager Interface
         din          => din,
         wrEn         => wrEn,
         tok          => tok,
         tokFb        => tokFb,
         ackN         => ackN,
         pause        => pause,
         -- Pgp4TxLite Interface
         txReady      => txReady,
         txValid      => txValid,
         txData       => txData,
         txSof        => txSof,
         txEof        => txEof,
         txEofe       => txEofe);

    -- Instantiate the PGP4TxLiteWrapper
    U_Pgp4TxLiteWrapper : entity surf.Pgp4TxLiteWrapper
      port map(
        -- Clock and Reset
        clk        => clk,
        rst        => rst,
        -- 64-bit Input Framing Interface
        txReady    => txReady,
        txValid    => txValid,
        txData     => txData,
        txSof      => txSof,
        txEof      => txEof,
        txEofe     => txEofe,
        -- 66-bit Output Interface
        phyTxValid => phyTxValid,
        phyTxReady => phyTxReady,
        phyTxData  => phyTxData);

    U_SerializerGearbox : entity surf.Gearbox
      generic map (
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         SLAVE_WIDTH_G  => 66,
         MASTER_WIDTH_G => 32)
      port map (
         -- Clock and Reset
         clk            => clk,
         rst            => rst,
         -- Slave Interface
         slaveValid     => phyTxValid,
         slaveReady     => phyTxReady,
         slaveData      => phyTxData,
         slaveBitOrder  => '0',
         -- Master Interface
         masterBitOrder => '0',
         masterReady    => pgpData32bReady,
         masterValid    => pgpData32bValid,
         masterData     => pgpData32b);

     -------
     -- FPGA
     -------
    U_SerializerReverseGearbox : entity surf.Gearbox
      generic map (
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         SLAVE_WIDTH_G  => 32,
         MASTER_WIDTH_G => 66)
      port map (
         -- Clock and Reset
         clk            => clk,
         rst            => rst,
         -- Slave Interface
         slaveValid     => pgpData32bValid,
         slaveReady     => pgpData32bReady,
         slaveData      => pgpData32b,
         slaveBitOrder  => '0',
         -- Master Interface
         masterBitOrder => '0',
         masterReady    => '1', -- always ready
         masterValid    => pgpData66bValid,
         masterData     => pgpData66b);

    U_PgpRx : entity surf.Pgp4Rx
     generic map(
        TPD_G       => TPD_G,
        RST_ASYNC_G => RST_ASYNC_G,
        NUM_VC_G    => NUM_VC_G,
        SKIP_EN_G   => true,
        LITE_EN_G   => true)
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

     U_FpgaGearbox : entity surf.Gearbox
      generic map (
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         SLAVE_WIDTH_G  => 64,
         MASTER_WIDTH_G => 40)
      port map (
         -- Clock and Reset
         clk            => clk,
         rst            => rst,
         -- Slave Interface
         slaveValid     => pgpRxMasters(0).tvalid,
         slaveReady     => open,
         slaveData      => pgpRxMasters(0).tData(63 downto 0),
         slaveBitOrder  => '0',
         -- Master Interface
         masterBitOrder => '0',
         masterReady    => '1',
         masterValid    => pgpValid,
         masterData     => pgpData);

end architecture;
