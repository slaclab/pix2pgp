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
      TPD_G                      : time     := 1 ns;
      RST_ASYNC_G                : boolean  := True;
      RST_POLARITY_G             : sl       := '1';
      DATAFIFO_PIPE_G            : positive := 2;
      STATUSFIFO_PIPE_G          : positive := 2;
      PIPELINE_BRIDGE_DATA_G     : boolean  := False;
      PIPELINE_BRIDGE_STATUS_G   : boolean  := True;
      COLMANAGER_DATA_DEPTH_G    : integer  := 6;
      COLMANAGER_DATA_AF_LVL_G   : integer  := 1;
      COLMANAGER_STATUS_DEPTH_G  : integer  := 4;
      COLMANAGER_STATUS_AF_LVL_G : integer  := 1;
      ADAPTER_DEPTH_G            : integer  := 6;
      ADAPTER_AF_LVL_G           : integer  := 1;
      SUPER_FIFO_RD_DELAY_G      : natural  := 3;
      ARB_DOUT_PIPE_G            : natural  := 2;
      NUM_VC_G                   : natural  := 1
   );
   port(
      -- General Interface
      sparseClk    : in  sl;
      pgpClk       : in  sl;
      rst          : in  sl;
      sro          : in  sl;
      -- Pixel Interface
      sof          : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      eof          : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      overOcc      : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      ackN         : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      wrEn         : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      din          : in  Pix2PgpSparseDinArray;
      busy         : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      pause        : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- FPGA Interface
      pgpDout      : out slv(31 downto 0);
      pgpDoutValid : out sl;
      pgpDoutReady : in  sl
   );
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

begin

  -- Instantiate the design under test
   U_Pix2PgpTop : entity pix2pgp.Pix2PgpTop
      generic map (
         TPD_G                      => TPD_G,
         RST_ASYNC_G                => RST_ASYNC_G,
         RST_POLARITY_G             => RST_POLARITY_G,
         PIPELINE_BRIDGE_DATA_G     => PIPELINE_BRIDGE_DATA_G,
         PIPELINE_BRIDGE_STATUS_G   => PIPELINE_BRIDGE_STATUS_G,
         COLMANAGER_DATA_DEPTH_G    => COLMANAGER_DATA_DEPTH_G,
         COLMANAGER_DATA_AF_LVL_G   => COLMANAGER_DATA_AF_LVL_G,
         COLMANAGER_STATUS_DEPTH_G  => COLMANAGER_STATUS_DEPTH_G,
         COLMANAGER_STATUS_AF_LVL_G => COLMANAGER_STATUS_AF_LVL_G,
         ADAPTER_DEPTH_G            => ADAPTER_DEPTH_G,
         ADAPTER_AF_LVL_G           => ADAPTER_AF_LVL_G,
         DATAFIFO_PIPE_G            => DATAFIFO_PIPE_G,
         STATUSFIFO_PIPE_G          => STATUSFIFO_PIPE_G,
         SUPER_FIFO_RD_DELAY_G      => SUPER_FIFO_RD_DELAY_G,
         ARB_DOUT_PIPE_G            => ARB_DOUT_PIPE_G)
      port map (
         -- General Interface
         sparseClk    => sparseClk,
         pgpClk       => pgpClk,
         rst          => rst,
         columnEnable => columnEnable,
         -- Column Manager Interface
         din          => din,
         wrEn         => wrEn,
         sof          => sof,
         eof          => eof,
         overOcc      => overOcc,
         ackN         => ackN,
         busy         => busy,
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
        clk        => pgpClk,
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
         clk            => pgpClk,
         rst            => rst,
         -- Slave Interface
         slaveValid     => phyTxValid,
         slaveReady     => phyTxReady,
         slaveData      => phyTxData,
         slaveBitOrder  => '0',
         -- Master Interface
         masterBitOrder => '0',
         masterReady    => pgpDoutReady,
         masterValid    => pgpDoutValid,
         masterData     => pgpDout);

end architecture;
