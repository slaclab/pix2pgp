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


entity PgpTb is
end entity PgpTb;

architecture test of PgpTb is

   constant TPD_C                    : time    := 1 ns;
   constant RST_ASYNC_C              : boolean := True;
   constant RST_POLARITY_C           : sl := '1';
   constant GHDL_SIM_C               : boolean := True;
   constant SYNTHESIZE_C             : boolean := False;
   constant PGPADAPTER_DEPTH_C       : integer := 6;
   constant NUM_VC_C                 : natural := 1;
   --
   constant CLK_PERIOD_C             : time := 5.384 ns;

   signal clk          : sl := '0';
   signal rst          : sl := '1';
   signal start        : sl := '0';

   signal pgpValid     : sl := '0';
   signal pgpData      : slv(PGP_DWIDTH_C-1 downto 0) := (others => '0');

   signal txReady      : sl := '1';
   signal txValid      : sl := '0';
   signal txData       : slv(63 downto 0) := (others => '0');
   signal txSof        : sl := '0';
   signal txEof        : sl := '0';
   signal txEofe       : sl := '0';

   signal phyTxValid  : sl := '0';
   signal phyTxReady  : sl := '1';
   signal phyTxData   : slv(65 downto 0) := (others => '0');

   signal pgpData32b  : slv(31 downto 0) := (others => '0');
   signal pgpData66b  : slv(65 downto 0) := (others => '0');
   signal pgpData32bValid : sl := '0';
   signal pgpData32bReady : sl := '0';
   signal pgpData66bValid : sl := '0';

   signal pgpRxCtrl   : AxiStreamCtrlArray(NUM_VC_C-1 downto 0) := (others => AXI_STREAM_CTRL_INIT_C);
   signal pgpRxOut     : Pgp4RxOutType := PGP4_RX_OUT_INIT_C;
   signal pgpRxMasters : AxiStreamMasterArray(NUM_VC_C-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);

begin

  -- rst and clk
  clk <= not clk after CLK_PERIOD_C - TPD_C;
  rst <= '1', '0' after CLK_PERIOD_C*200;

   -------
   -- ASIC
   -------

   -----------------------------------------
   -- PGP FIFO adapter
   -----------------------------------------
   U_Adapter: entity pix2pgp.Pix2PgpAdapter
      generic map(
         TPD_G           => TPD_C,
         RST_ASYNC_G     => RST_ASYNC_C,
         RST_POLARITY_G  => RST_POLARITY_C,
         DWARE_DEPTH_G   => PGPADAPTER_DEPTH_C,
         GHDL_SIM_G      => GHDL_SIM_C,
         SYNTHESIZE_G    => SYNTHESIZE_C)
      port map(
         -- General Interface
         pgpClk     => clk,
         rst        => rst,
         -- Gearbox Interface
         pgpValid   => pgpValid,
         pgpData    => pgpData,
         pgpReady   => open,
         -- Pgp4TxLite Interface
         txReady    => txReady,
         txValid    => txValid,
         txData     => txData,
         txSof      => txSof,
         txEof      => txEof,
         txEofe     => txEofe);

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
         TPD_G          => TPD_C,
         RST_ASYNC_G    => RST_ASYNC_C,
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
         TPD_G          => TPD_C,
         RST_ASYNC_G    => RST_ASYNC_C,
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
        TPD_G              => TPD_C,
        RST_ASYNC_G        => RST_ASYNC_C,
        NUM_VC_G           => NUM_VC_C,
        SKIP_EN_G          => true,
        LITE_EN_G          => true)
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

  -- Generate the test stimulus
  stimulus: process begin

    -- Wait for the rst to be released before
    wait until (rst = '0');

    wait for CLK_PERIOD_C*4000; -- extend wait to align pgp protocol
      start <= '1';

    -- do not touch
    wait;
    -- do not touch

  end process stimulus;

  writeFrameProcess: process(clk)
    variable writeIndex : integer := 0;
  begin
    if (rising_edge(clk)) then
      if (rst = '0') then
        if (writeIndex < 5 and start = '1') then
          writeIndex := writeIndex + 1;
          pgpValid   <= '1';
          pgpData    <= conv_std_logic_vector(writeIndex, pgpData'length);
        else
          writeIndex := writeIndex;
          pgpValid   <= '0';
          pgpData    <= (others => '0');
        end if;
      else
        writeIndex := 0;
        pgpValid   <= '0';
        pgpData    <= (others => '0');
      end if;
    end if;
  end process;

  writeDataProcess: process(clk)

    -- variables for file-writing
    file myFile  : text open write_mode is "pgpTbDump.dat";
    variable row : line;

  begin
    if (rising_edge(clk)) then
      -- first check if the rst is low
      if (rst = '0') then
        -- then check if the valid flag is high
        if pgpRxMasters(0).tvalid = '1' then
          -- syntax: write(row_variable,what_to_write,
          -- justification(right/left), trailing_whitespaces);
          -- writeline(file_variable, row_variable);
          hwrite(row, pgpRxMasters(0).tData(63 downto 0), right, 0);
          writeline(myFile,row);
        end if;
      end if;
    end if;
  end process;


end architecture;