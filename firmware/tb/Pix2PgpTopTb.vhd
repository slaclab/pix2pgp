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

entity Pix2PgpTopTb is
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
      COLMANAGER_FULL_LVL_G    : natural  := 3;
      PGPADAPTER_FULL_LVL_G    : natural  := 3;
      SUPER_FIFO_RD_DELAY_G    : natural  := 3;
      ARB_FIFO_RD_DELAY_G      : natural  := 1;
      ARB_DOUT_PIPE_G          : natural  := 2;
      NUM_VC_G                 : natural  := 1
   );
end entity Pix2PgpTopTb;

architecture test of Pix2PgpTopTb is

   constant CLK_PERIOD_C : time := 5.384 ns;

   signal clk          : sl := '0';
   signal rst          : sl := '1';
   signal columnEnable : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := x"FFFFFF";

   signal tok          : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '1');
   signal tokFb        : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal ackN         : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '1');
   signal wrEn         : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal pause        : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal din          : Pix2PgpSparseDinArray := (others => (others => '0'));

   signal txReady      : sl := '1';
   signal txValid      : sl := '0';
   signal txData       : slv(63 downto 0) := (others => '0');
   signal txSof        : sl := '0';
   signal txEof        : sl := '0';
   signal txEofe       : sl := '0';

   signal fillFifos    : sl := '0';
   signal fillCnt      : natural range 0 to 1023;

   type hitLenArray is array (0 to NUM_OF_COL_MANAGERS_C-1) of slv(9 downto 0);
   signal hitLen  : hitLenArray := (others => (others => '0'));
   signal overOcc : sl := '0';
   signal sro     : sl := '0';

   signal phyTxValid  : sl := '0';
   signal phyTxReady  : sl := '1';
   signal phyTxData   : slv(65 downto 0) := (others => '0');

   signal pgpData32b  : slv(31 downto 0) := (others => '0');
   signal pgpData66b  : slv(65 downto 0) := (others => '0');
   signal pgpData32bValid : sl := '0';
   signal pgpData32bReady : sl := '0';
   signal pgpData66bValid : sl := '0';
   signal pgpData40bValid  : sl := '0';
   signal pgpData40bData :  slv(39 downto 0) := (others => '0');

   signal pgpRxCtrl   : AxiStreamCtrlArray(NUM_VC_G-1 downto 0) := (others => AXI_STREAM_CTRL_INIT_C);
   signal pgpRxOut     : Pgp4RxOutType := PGP4_RX_OUT_INIT_C;
   signal pgpRxMasters : AxiStreamMasterArray(NUM_VC_G-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);

begin

  -- rst and clk
  clk <= not clk after CLK_PERIOD_C - TPD_G;
  rst <= '1', '0' after CLK_PERIOD_C*200;

   -------
   -- ASIC
   -------
   GEN_DUMMY_PIXEL: for col in 0 to NUM_OF_COL_MANAGERS_C-1 generate
      U_DummyPixel : entity pix2pgp.DummyPixel
         generic map(
            TPD_G        => TPD_G,
            RST_ASYNC_G  => RST_ASYNC_G,
            WAIT_FB_G    => 2,
            WAIT_ACKN_G  => 2,
            WAIT_WREN_G  => 2,
            COL_ID_G     => col)
         port map(
            clk     => clk,
            rst     => rst,
            sro     => sro,
            pause   => pause(col),
            hitLen  => hitLen(col),
            overOcc => overOcc,
            tok     => tok(col),
            tokFb   => tokFb(col),
            ackN    => ackN(col),
            wrEn    => wrEn(col),
            dout    => din(col));
   end generate GEN_DUMMY_PIXEL;

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
         COLMANAGER_FULL_LVL_G    => COLMANAGER_FULL_LVL_G,
         DATAFIFO_PIPE_G          => DATAFIFO_PIPE_G,
         PGPADAPTER_FULL_LVL_G    => PGPADAPTER_FULL_LVL_G,
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
         masterValid    => pgpData40bValid,
         masterData     => pgpData40bData);

  -- Generate the test stimulus
  stimulus: process begin

    -- Wait for the rst to be released before
    wait until (rst = '0');
    for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
      -- only even number of events please
      hitLen(col) <= toSlv(0, hitLen(col)'length);
    end loop;

    wait for CLK_PERIOD_C*4200; -- extend wait to align pgp protocol
      sro <= '1';
    wait for CLK_PERIOD_C*2;
      sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  hitLen(5) <= toSlv(3, hitLen(5)'length);
    --  hitLen(6) <= toSlv(1, hitLen(6)'length);
    --  hitLen(7) <= toSlv(2, hitLen(7)'length);
    --  hitLen(8) <= toSlv(5, hitLen(8)'length);
    --  hitLen(9) <= toSlv(4, hitLen(9)'length);
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  hitLen(5) <= toSlv(8, hitLen(5)'length);
    --  hitLen(6) <= toSlv(6, hitLen(6)'length);
    --  hitLen(7) <= toSlv(3, hitLen(7)'length);
    --  hitLen(8) <= toSlv(5, hitLen(8)'length);
    --  hitLen(9) <= toSlv(1, hitLen(9)'length);
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
    --     hitLen(col) <= toSlv(5, hitLen(col)'length);
    --  end loop;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    wait for CLK_PERIOD_C*186;
      hitLen(3) <= toSlv(24, hitLen(5)'length);
      hitLen(4) <= toSlv(2, hitLen(5)'length);
      hitLen(5) <= toSlv(8, hitLen(5)'length);
      hitLen(6) <= toSlv(6, hitLen(6)'length);
      hitLen(7) <= toSlv(24, hitLen(7)'length);
      hitLen(8) <= toSlv(5, hitLen(8)'length);
      hitLen(9) <= toSlv(1, hitLen(9)'length);
      sro  <= '1';
    wait for CLK_PERIOD_C*2;
      sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
    --    hitLen(col) <= toSlv(0, hitLen(col)'length);
    --  end loop;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    -- do not touch
    wait;
    -- do not touch

  end process stimulus;

  writeDataProcess: process(clk)

    -- variables for file-writing
    file myFile  : text open write_mode is "pix2pgpRxDataDump.dat";
    variable row : line;

  begin
    if (rising_edge(clk)) then
      -- first check if the rst is low
      if (rst = '0') then
        -- then check if the valid flag is high
        if pgpData40bValid = '1' then
          -- syntax: write(row_variable,what_to_write,
          -- justification(right/left), trailing_whitespaces);
          -- writeline(file_variable, row_variable);
          hwrite(row, pgpData40bData, right, 0);
          writeline(myFile,row);
        end if;
      end if;
    end if;
  end process;

end architecture;
