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
use surf.AxiLitePkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpAsicPkg.all;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpThriglavTopTb is
   generic(
      TPD_G                     : time     := 1 ns;
      RST_ASYNC_G               : boolean  := true;
      RST_POLARITY_G            : sl       := '0';
      FPGA_SYNTH_G              : boolean  := false;
      PIPELINE_DATA_G           : boolean  := false;
      PIPELINE_STATUS_G         : boolean  := true;
      BENCHMARKING_G            : boolean  := false;
      TIMEOUT_LIMIT_WIDTH_G     : positive := 16;
      COLMANAGER_DATA_DEPTH_G   : integer  := 8;
      COLMANAGER_STATUS_DEPTH_G : integer  := 8;
      DATAFIFO_PIPE_G           : natural  := 1;
      STATUSFIFO_PIPE_G         : natural  := 1;
      NUM_VC_G                  : natural  := 1
   );
   port (
    dummyIn : in sl
  );

end entity Pix2PgpThriglavTopTb;

-- * about the AF_LVL_G flags:
-- the surf-based fifos issue their almost-full/prog-full when wr_index = AF_LVL_G;
-- the synopsys fifos raise their flag when wr_index = DEPTH_G-AF_LVL_G;
-- i.e. for the synopsys fifos, the AF_LVL_G denotes the amount of empty memory spaces before
-- the almost-full flag is asserted

architecture test of Pix2PgpThriglavTopTb is

   constant CLK_PERIOD_SPARSE_C : time := 50.0   ns; -- matrix clock of ASIC
   constant CLK_PERIOD_PGP_C    : time := 5.3846 ns; -- also the PHY clock that is sent to ASIC
   constant CLK_PERIOD_PGP_RX_C : time := 5.3846 ns; -- internal-to-FPGA
   constant CLK_PERIOD_SYS_C    : time := 6.25   ns; -- sysClk (AXI-Stream)
   constant REV_RST_POLARITY_C  : sl   := not(RST_POLARITY_G);

   --constant AXIS_CONFIG_C : AxiStreamConfigType := PIX2PGP_FPGA_AXI_CONFIG_C;
   constant AXIS_CONFIG_C : AxiStreamConfigType := ssiAxiStreamConfig(16);

   signal sparseClk : sl := '0';
   signal pgpClk    : sl := '0';
   signal pgpRxClk  : sl := '0';
   signal rst       : sl := '0';
   signal sro       : sl := '0';
   signal sroFinal  : sl := '0';
   signal ero       : sl := '0';
   signal eroFinal  : sl := '0';
   signal eroDly    : sl := '0';
   signal revRst    : sl := '0';
   signal sysClk    : sl := '0';
   signal axiFifoRst: sl := '0';

   type asicArray is array (0 to NUM_OF_SERIALIZERS_C-1) of slv(NUM_OF_COL_MANAGERS_C-1 downto 0);

   signal tokFb     : asicArray := (others => (others => '1'));
   signal sof       : asicArray := (others => (others => '1'));
   signal eof       : asicArray := (others => (others => '0'));
   signal overOcc   : asicArray := (others => (others => '0'));
   signal busy      : asicArray := (others => (others => '0'));
   signal ackN      : asicArray := (others => (others => '1'));
   signal wrEn      : asicArray := (others => (others => '0'));
   signal pause     : asicArray := (others => (others => '0'));
   signal pauseAck  : asicArray := (others => (others => '0'));
   signal sparseBusy: asicArray := (others => (others => '0'));

   type asicDinArray is array (0 to NUM_OF_SERIALIZERS_C-1) of Pix2PgpSparseDinArray;
   signal din : asicDinArray := (others => (others =>  (others => '0')));

   type hitLenArray is array (0 to NUM_OF_COL_MANAGERS_C-1) of slv(15 downto 0);

   type metaHitLenArray is array (0 to NUM_OF_SERIALIZERS_C-1) of hitLenArray;

   signal hitLen  : metaHitLenArray := (others => (others => (others => '0')));

   type pgpDataAsicType is array (0 to NUM_OF_SERIALIZERS_C-1) of slv(31 downto 0);

   signal pgpDataAsic      : pgpDataAsicType := (others => (others => '0'));
   signal pgpDataAsicValid : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal pgpDataAsicReady : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal pgp4RxLinkUp     : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal pgpDataAsicValidVec : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal pgp4RxMaster : AxiStreamMasterArray(0 to NUM_OF_SERIALIZERS_C-1) := (others => AXI_STREAM_MASTER_INIT_C);
   signal pgp4RxSlave : AxiStreamSlaveArray(0 to NUM_OF_SERIALIZERS_C-1) := (others => AXI_STREAM_SLAVE_INIT_C);

   signal asicRxMaster   : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal asicRxSlave    : AxiStreamSlaveType  := AXI_STREAM_SLAVE_FORCE_C; -- force to ready

   signal ipIntegratorMaster : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal ipIntegratorSlave  : AxiStreamSlaveType  := AXI_STREAM_SLAVE_FORCE_C; -- force to ready

   signal m_axis_tvalid  : sl := '0';
   signal m_axis_tdata   : slv(AXIS_CONFIG_C.TDATA_BYTES_C*8-1 downto 0) := (others => '0');
   signal m_axis_tstrb   : slv(AXIS_CONFIG_C.TDATA_BYTES_C-1 downto 0)   := (others => '0');
   signal m_axis_tkeep   : slv(AXIS_CONFIG_C.TDATA_BYTES_C-1 downto 0)   := (others => '0');
   signal m_axis_tlast   : sl := '0';
   signal m_axis_tdest   : slv(7 downto 0) := (others => '0');
   signal m_axis_tid     : slv(7 downto 0) := (others => '0');
   signal m_axis_tuser   : slv(7 downto 0) := (others => '0');

   signal cfgSel            : sl := '1';
   signal cfgTimeoutLimit   : slv(11 downto 0) := toSlv(0,  12);
   signal cfgPauseLimit     : slv(11 downto 0) := toSlv(12, 12);
   signal cfgColumnEnable   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '1');
   signal cfgColBusy        : slv(NUM_OF_SERIALIZERS_C-1 downto 0)  := (others => '0');
   signal cfgColDataEmpty   : slv(NUM_OF_SERIALIZERS_C-1 downto 0)  := (others => '1');
   signal cfgColStatusEmpty : slv(NUM_OF_SERIALIZERS_C-1 downto 0)  := (others => '1');
   signal cfgSuperBusy      : slv(NUM_OF_SERIALIZERS_C-1 downto 0)  := (others => '0');
   signal cfgArbBusy        : slv(NUM_OF_SERIALIZERS_C-1 downto 0)  := (others => '0');

   -- benchmarking
   signal rstCnt            : sl := '0';
   signal cfgColBusyDel     : sl := '0';
   signal cfgSuperBusyDel   : sl := '0';
   signal colBusyCnt        : slv(31 downto 0) := (others => '0');
   signal superBusyCnt      : slv(31 downto 0) := (others => '0');
   signal totalLatencyCnt   : slv(31 downto 0) := (others => '0');

   constant OCC_BENCHMARK_COUNT : positive := 38;
   constant IGNORE_ERO_C        : boolean  := BENCHMARKING_G;

   type RealArrayType is array (0 to OCC_BENCHMARK_COUNT-1) of real;
   type IntArrayType  is array (0 to OCC_BENCHMARK_COUNT-1) of integer;

   signal colBusyArray      : IntArrayType := (others => 0);
   signal superBusyArray    : IntArrayType := (others => 0);
   signal totalLatencyArray : IntArrayType := (others => 0);

   signal occArray : RealArrayType := (
      0  => 0.5,  1  => 1.0,  2  => 1.5,  3  => 2.0,  4  => 2.5,  5  => 3.0,
      6  => 3.5,  7  => 4.0,  8  => 4.5,  9  => 5.0,  10 => 5.5,  11 => 6.0,
      12 => 6.5,  13 => 7.0,  14 => 7.5,  15 => 8.0,  16 => 8.5,  17 => 9.0,
      18 => 9.5,  19 => 10.0, 20 => 15.0, 21 => 20.0, 22 => 25.0, 23 => 30.0,
      24 => 35.0, 25 => 40.0, 26 => 45.0, 27 => 50.0, 28 => 55.0, 29 => 60.0,
      30 => 65.0, 31 => 70.0, 32 => 75.0, 33 => 80.0, 34 => 85.0, 35 => 90.0,
      36 => 95.0, 37 => 100.0
   );

   signal colHitsArray : IntArrayType := (
      0  => 3,   1  => 6,   2  => 9,   3  => 12,  4  => 16,  5  => 19,
      6  => 22,  7  => 25,  8  => 28,  9  => 32,  10 => 35,  11 => 38,
      12 => 41,  13 => 44,  14 => 48,  15 => 51,  16 => 54,  17 => 57,
      18 => 60,  19 => 64,  20 => 96,  21 => 128, 22 => 160, 23 => 192,
      24 => 224, 25 => 256, 26 => 288, 27 => 320, 28 => 352, 29 => 384,
      30 => 416, 31 => 448, 32 => 480, 33 => 512, 34 => 544, 35 => 576,
      36 => 608, 37 => 640
   );

begin

   -- clocks
   U_ClkRst_pgpClk : entity surf.ClkRst
      generic map (
         CLK_PERIOD_G      => CLK_PERIOD_PGP_C,
         CLK_DELAY_G       => 1 ns,
         RST_START_DELAY_G => 0 ns,
         RST_HOLD_TIME_G   => 5 us,
         SYNC_RESET_G      => true)
      port map (
         clkP => pgpClk,
         clkN => open);

   U_ClkRst_sparseClk : entity surf.ClkRst
      generic map (
         CLK_PERIOD_G      => CLK_PERIOD_SPARSE_C,
         CLK_DELAY_G       => 1 ns,
         RST_START_DELAY_G => 0 ns,
         RST_HOLD_TIME_G   => 5 us,
         SYNC_RESET_G      => true)
      port map (
         clkP => sparseClk,
         clkN => open);

   U_ClkRst_pgpRxClk : entity surf.ClkRst
      generic map (
         CLK_PERIOD_G      => CLK_PERIOD_PGP_RX_C,
         CLK_DELAY_G       => 1 ns,
         RST_START_DELAY_G => 0 ns,
         RST_HOLD_TIME_G   => 5 us,
         SYNC_RESET_G      => true)
      port map (
         clkP => pgpRxClk,
         clkN => open);

   U_ClkRst_sysClk : entity surf.ClkRst
      generic map (
         CLK_PERIOD_G      => CLK_PERIOD_SYS_C,
         CLK_DELAY_G       => 1 ns,
         RST_START_DELAY_G => 0 ns,
         RST_HOLD_TIME_G   => 5 us,
         SYNC_RESET_G      => true)
      port map (
         clkP => sysClk,
         clkN => open);

  issueSroProcess: process(sparseClk)
  begin
    if (rising_edge(sparseClk)) then
      if sro = '1' and sroFinal = '0' then
        sroFinal <= sro;
      else
        sroFinal <= '0';
      end if;
    end if;
  end process;

  issueEroProcess: process(sparseClk)
  begin
    if (rising_edge(sparseClk)) then
      eroDly <= ero;
      if ero = '1' and eroDly = '0' then
        eroFinal <= ero;
      else
        eroFinal <= '0';
      end if;
    end if;
  end process;


   --------
   -- Pixel
   --------
   GEN_SERIALIZER: for ser in 0 to NUM_OF_SERIALIZERS_C-1 generate

      GEN_DUMMY_PIXEL: for col in 0 to NUM_OF_COL_MANAGERS_C-1 generate
         U_DummyPixel : entity pix2pgp.DummyThriglavPixel
            generic map(
              TPD_G           => TPD_G,
              RST_ASYNC_G     => RST_ASYNC_G,
              RST_POLARITY_G  => RST_POLARITY_G,
              IGNORE_ERO_G    => IGNORE_ERO_C,
              WAIT_WREN_G     => 3,
              SER_ID_G        => ser,
              COL_ID_G        => col)
            port map(
              clk        => sparseClk,
              df_reset_n => rst,
              sro        => sroFinal,
              ero        => eroFinal,
              hitLen     => hitLen(ser)(col),
              pause      => pause(ser)(col),
              pauseAck   => pauseAck(ser)(col),
              sof        => sof(ser)(col),
              eof        => eof(ser)(col),
              overOcc    => overOcc(ser)(col),
              wrEn       => wrEn(ser)(col),
              dout       => din(ser)(col));
      end generate GEN_DUMMY_PIXEL;

         ------
         -- UUT
         ------
         U_Uut : entity pix2pgp.Pix2PgpThriglavTop
            generic map(
               TPD_G                      => TPD_G,
               RST_ASYNC_G                => RST_ASYNC_G,
               RST_POLARITY_G             => RST_POLARITY_G,
               DATAFIFO_PIPE_G            => DATAFIFO_PIPE_G,
               STATUSFIFO_PIPE_G          => STATUSFIFO_PIPE_G,
               PIPELINE_DATA_G            => PIPELINE_DATA_G,
               PIPELINE_STATUS_G          => PIPELINE_STATUS_G,
               COLMANAGER_DATA_DEPTH_G    => COLMANAGER_DATA_DEPTH_G,
               COLMANAGER_STATUS_DEPTH_G  => COLMANAGER_STATUS_DEPTH_G)
            port map(
               sparseClk         => sparseClk,
               sparseRst         => rst,
               pgpClk            => pgpClk,
               pgpRst            => rst,
               pgpHardRst        => rst,
               cfgSel            => cfgSel,
               cfgTimeoutLimit   => cfgTimeoutLimit,
               cfgPauseLimit     => cfgPauseLimit,
               cfgColumnEnable   => cfgColumnEnable,
               cfgColBusy        => cfgColBusy(ser),
               cfgColDataEmpty   => cfgColDataEmpty(ser),
               cfgColStatusEmpty => cfgColStatusEmpty(ser),
               cfgSuperBusy      => cfgSuperBusy(ser),
               cfgArbBusy        => cfgArbBusy(ser),
               pause             => pause(ser),
               sof               => sof(ser),
               eof               => eof(ser),
               busy              => busy(ser),
               overOcc           => overOcc(ser),
               pauseAck          => pauseAck(ser),
               wrEn              => wrEn(ser),
               din0              => din(ser)(0),
               din1              => din(ser)(1),
               din2              => din(ser)(2),
               din3              => din(ser)(3),
               din4              => din(ser)(4),
               din5              => din(ser)(5),
               din6              => din(ser)(6),
               din7              => din(ser)(7),
               din8              => din(ser)(8),
               din9              => din(ser)(9),
               din10             => din(ser)(10),
               din11             => din(ser)(11),
               din12             => din(ser)(12),
               din13             => din(ser)(13),
               din14             => din(ser)(14),
               din15             => din(ser)(15),
               din16             => din(ser)(16),
               din17             => din(ser)(17),
               din18             => din(ser)(18),
               din19             => din(ser)(19),
               din20             => din(ser)(20),
               din21             => din(ser)(21),
               din22             => din(ser)(22),
               din23             => din(ser)(23),
               din24             => din(ser)(24),
               din25             => din(ser)(25),
               din26             => din(ser)(26),
               din27             => din(ser)(27),
               din28             => din(ser)(28),
               din29             => din(ser)(29),
               din30             => din(ser)(30),
               din31             => din(ser)(31),
               din32             => din(ser)(32),
               din33             => din(ser)(33),
               din34             => din(ser)(34),
               din35             => din(ser)(35),
               din36             => din(ser)(36),
               din37             => din(ser)(37),
               din38             => din(ser)(38),
               din39             => din(ser)(39),
               din40             => din(ser)(40),
               din41             => din(ser)(41),
               din42             => din(ser)(42),
               din43             => din(ser)(43),
               din44             => din(ser)(44),
               din45             => din(ser)(45),
               din46             => din(ser)(46),
               din47             => din(ser)(47),
               din48             => din(ser)(48),
               din49             => din(ser)(49),
               pgpDout           => pgpDataAsic(ser),
               pgpDoutValid      => pgpDataAsicValid(ser),
               pgpDoutReady      => pgpDataAsicReady(ser));

   end generate GEN_SERIALIZER;

   -------
   -- FPGA
   -------
   revRst <= not(rst);

   GEN_LANE: for lane in 0 to NUM_OF_SERIALIZERS_C-1 generate

      -- pgp4 wrapper
      U_FPGA : entity pix2pgp.Pix2PgpFpgaTb
       generic map(
          TPD_G          => TPD_G,
          RST_ASYNC_G    => false,
          RST_POLARITY_G => REV_RST_POLARITY_C,
          FPGA_SYNTH_G   => FPGA_SYNTH_G,
          NUM_VC_G       => NUM_VC_G)
       port map(
          -- General Interface
          pgpRxClk     => pgpRxClk,
          phyRxClk     => pgpClk,
          rst          => revRst,
          linkReady    => pgp4RxLinkUp(lane),
          -- Pix2Pgp Interface
          pgpDin       => pgpDataAsic(lane),
          pgpDinValid  => pgpDataAsicValid(lane),
          pgpDinReady  => pgpDataAsicReady(lane),
          -- FPGA RX Interface
          pgp4RxMaster => pgp4RxMaster(lane),
          pgp4RxSlave  => pgp4RxSlave(lane));

   end generate GEN_LANE;

   -- asic stream receiver and merger
   U_ASIC_STREAM_RX : entity pix2pgp.Pix2PgpAsicStreamRx
      generic map(
         TPD_G                  => TPD_G,
         RST_ASYNC_G            => false,
         RST_POLARITY_G         => REV_RST_POLARITY_C,
         ASIC_ID_G              => 0,
         LANE_PIPE_STAGES_G     => 1,
         TRG_FIFO_ADDR_WIDTH_G  => 6,
         META_FIFO_ADDR_WIDTH_G => 6,
         AXIS_FIFO_ADDR_WIDTH_G => 6)
      port map(
         -- General Interface
         pgpRxClk        => pgpRxClk,
         pgpRxRst        => revRst,
         -- ASIC Domain Interface
         asicClk         => sparseClk,
         asicRst         => rst,
         asicSro         => sroFinal,
         asicSroEn       => '1',
         -- PGP4Rx Interface (on pgpRxClk domain)
         pgp4RxMaster    => pgp4RxMaster,
         pgp4RxSlave     => pgp4RxSlave,
         pgp4RxLinkUp    => pgp4RxLinkUp,
         -- AXI-Stream Rx Interface (on pgpRxClk domain)
         asicRxMaster    => asicRxMaster,
         asicRxSlave     => asicRxSlave,
         -- AXI-Lite Interface
         axilClk         => pgpRxClk,
         axilRst         => revRst,
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
         FIFO_ADDR_WIDTH_G   => 11,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => PIX2PGP_FPGA_AXI_CONFIG_C,
         MASTER_AXI_CONFIG_G => AXIS_CONFIG_C)
      port map (
         -- Slave Port
         sAxisClk    => pgpRxClk,
         sAxisRst    => axiFifoRst,
         sAxisMaster => asicRxMaster,
         sAxisSlave  => asicRxSlave,
         -- Status Port
         -- Master Port
         mAxisClk    => sysClk,
         mAxisRst    => axiFifoRst,
         mAxisMaster => ipIntegratorMaster,
         mAxisSlave  => ipIntegratorSlave);

   axiFifoRst <= ite(toBoolean(REV_RST_POLARITY_C), revRst, not(revRst));

   -- Map PgpRxMasters to AXI
   axiMaster : entity surf.MasterAxiStreamIpIntegrator
      generic map (
         INTERFACENAME   => "M_AXIS",
         TUSER_WIDTH     => 8,
         TID_WIDTH       => 8,
         TDEST_WIDTH     => 8,
         TDATA_NUM_BYTES => AXIS_CONFIG_C.TDATA_BYTES_C)
      port map (
         -- IP Integrator AXI Stream Interface
         M_AXIS_ACLK    => sysClk,
         M_AXIS_ARESETN => '1',
         M_AXIS_TVALID  => m_axis_tvalid,
         M_AXIS_TDATA   => m_axis_tdata,
         M_AXIS_TSTRB   => m_axis_tstrb,
         M_AXIS_TKEEP   => m_axis_tkeep,
         M_AXIS_TLAST   => m_axis_tlast,
         M_AXIS_TDEST   => m_axis_tdest,
         M_AXIS_TID     => m_axis_tid,
         M_AXIS_TUSER   => m_axis_tuser,
         M_AXIS_TREADY  => '1',
         -- SURF AXI Stream Interface
         axisClk        => open,
         axisRst        => open,
         axisMaster     => ipIntegratorMaster,
         axisSlave      => ipIntegratorSlave);

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
GEN_REGULAR_PROC: if not(BENCHMARKING_G) generate

  -- Generate the test stimulus
  regularStimulus: process begin

    -- do not touch begin
    ----------------------------------------------
    ----------------------------------------------
    -- issue reset here
    wait for CLK_PERIOD_SPARSE_C;
      rstCnt <= '1'; -- keep the benchmarking counters in reset
      rst    <= RST_POLARITY_G;
    wait for CLK_PERIOD_SPARSE_C*100;
      rst  <= not(RST_POLARITY_G);

    -- Wait for the rst to be released before doing anything else
    wait until (rst = not(RST_POLARITY_G));
    for ser in 0 to NUM_OF_SERIALIZERS_C-1 loop
       for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
         hitLen(ser)(col) <= toSlv(0, hitLen(ser)(col)'length);
       end loop;
    end loop;

    wait for CLK_PERIOD_SPARSE_C*2100; -- extend wait to align pgp protocol
      sro <= '1';
    wait for CLK_PERIOD_SPARSE_C*2;
      sro <= '0';
    wait for CLK_PERIOD_SPARSE_C*300;
      ero <= '1';
    wait for CLK_PERIOD_SPARSE_C*2;
      ero <= '0';
    ----------------------------------------------
    ----------------------------------------------
    -- do not touch end

    -- regular stimuli begin
    ----------------------------------------------
    ----------------------------------------------
     wait for CLK_PERIOD_SPARSE_C*50;
         sro <= '1';
     wait for CLK_PERIOD_SPARSE_C*2;
         sro <= '0';
     wait for CLK_PERIOD_SPARSE_C*300;
         ero <= '1';
     wait for CLK_PERIOD_SPARSE_C*2;
         ero <= '0';

   -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   wait for CLK_PERIOD_SPARSE_C*50;
   -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   ---------------------------------------
   for i in 0 to 12 loop
   ---------------------------------------
   hitLen(0)(0) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(1) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(2) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(3) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(4) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(6) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(7) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(10) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(11) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(12) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(13) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(14) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(15) <= toSlv(9, hitLen(0)(0)'length);
   hitLen(0)(16) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(21) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(22) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(23) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(24) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(25) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(0)(26) <= toSlv(8, hitLen(0)(0)'length);
   hitLen(0)(27) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(28) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(29) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(30) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(31) <= toSlv(7, hitLen(0)(0)'length);
   hitLen(0)(32) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(33) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(34) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(35) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(36) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(37) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(38) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(39) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(40) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(41) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(42) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(43) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(44) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(45) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(46) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(47) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(48) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(49) <= toSlv(0, hitLen(0)(0)'length);
   ---------------------------------------
   ---------------------------------------
   hitLen(1)(0) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(3) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(6) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(7) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(9) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(10) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(11) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(12) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(13) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(14) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(17) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(18) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(19) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(20) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(23) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(24) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(25) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(26) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(27) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(28) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(29) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(30) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(31) <= toSlv(7, hitLen(0)(0)'length);
   hitLen(1)(32) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(33) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(34) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(35) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(36) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(37) <= toSlv(6, hitLen(0)(0)'length);
   hitLen(1)(38) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(39) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(40) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(41) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(42) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(43) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(44) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(45) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(46) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(47) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(48) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(49) <= toSlv(0, hitLen(0)(0)'length);
   ---------------------------------------
   ---------------------------------------
   ---------------------------------------
  wait for CLK_PERIOD_SPARSE_C*50;
      sro <= '1';
  wait for CLK_PERIOD_SPARSE_C*2;
      sro <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    wait for CLK_PERIOD_SPARSE_C*300;
      ero <= '1';
    wait for CLK_PERIOD_SPARSE_C*2;
      ero <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wait for CLK_PERIOD_SPARSE_C*50;
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   ---------------------------------------
   hitLen(0)(0) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(2) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(3) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(5) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(7) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(10) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(11) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(12) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(13) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(14) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(16) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(17) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(18) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(19) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(20) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(21) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(22) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(23) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(24) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(25) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(26) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(27) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(28) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(29) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(30) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(31) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(32) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(33) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(34) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(35) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(36) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(37) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(38) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(39) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(40) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(41) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(42) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(43) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(44) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(45) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(46) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(47) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(48) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(49) <= toSlv(1, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(1)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(2) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(3) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(4) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(5) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(6) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(7) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(8) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(9) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(11) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(12) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(13) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(14) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(15) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(17) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(19) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(20) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(21) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(22) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(23) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(24) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(25) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(26) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(27) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(28) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(29) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(30) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(31) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(32) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(33) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(34) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(35) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(36) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(37) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(38) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(39) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(40) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(41) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(42) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(43) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(44) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(45) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(46) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(47) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(48) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(49) <= toSlv(2, hitLen(0)(0)'length);
   ---------------------------------------
   ---------------------------------------
   ---------------------------------------
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     wait for CLK_PERIOD_SPARSE_C*50;
         sro <= '1';
     wait for CLK_PERIOD_SPARSE_C*2;
         sro <= '0';
    wait for CLK_PERIOD_SPARSE_C*300;
      ero <= '1';
    wait for CLK_PERIOD_SPARSE_C*2;
      ero <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wait for CLK_PERIOD_SPARSE_C*50;
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   ---------------------------------------
   hitLen(0)(0) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(2) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(3) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(4) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(5) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(6) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(7) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(9) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(0)(10) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(11) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(12) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(0)(13) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(14) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(15) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(17) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(18) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(19) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(0)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(23) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(24) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(25) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(26) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(27) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(28) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(29) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(30) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(31) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(32) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(33) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(34) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(0)(35) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(36) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(37) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(38) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(39) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(0)(40) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(0)(41) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(42) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(43) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(44) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(45) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(0)(46) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(47) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(48) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(49) <= toSlv(5, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(1)(0) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(1) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(2) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(3) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(4) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(6) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(7) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(8) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(9) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(10) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(11) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(12) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(13) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(14) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(15) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(17) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(18) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(19) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(20) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(21) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(22) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(23) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(24) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(25) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(26) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(27) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(28) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(29) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(30) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(31) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(32) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(33) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(34) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(35) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(36) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(37) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(38) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(39) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(40) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(41) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(42) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(43) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(44) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(45) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(46) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(47) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(48) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(49) <= toSlv(2, hitLen(0)(0)'length);
   ---------------------------------------
   ---------------------------------------
   ---------------------------------------
     wait for CLK_PERIOD_SPARSE_C*50;
         sro <= '1';
     wait for CLK_PERIOD_SPARSE_C*2;
         sro <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    wait for CLK_PERIOD_SPARSE_C*300;
      ero <= '1';
    wait for CLK_PERIOD_SPARSE_C*2;
      ero <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wait for CLK_PERIOD_SPARSE_C*50;
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   ---------------------------------------
   hitLen(0)(0) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(3) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(4) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(5) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(6) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(7) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(9) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(11) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(12) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(13) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(14) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(15) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(16) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(18) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(19) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(21) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(23) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(24) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(25) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(26) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(27) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(28) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(29) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(30) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(31) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(32) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(33) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(34) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(35) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(36) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(37) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(38) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(39) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(40) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(41) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(42) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(43) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(44) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(45) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(46) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(47) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(48) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(49) <= toSlv(4, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(1)(0) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(3) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(4) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(5) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(6) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(7) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(8) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(11) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(12) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(13) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(14) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(16) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(17) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(18) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(20) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(21) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(22) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(23) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(24) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(25) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(26) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(27) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(28) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(29) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(30) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(31) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(32) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(33) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(34) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(35) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(36) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(37) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(38) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(39) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(40) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(41) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(42) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(43) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(44) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(45) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(46) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(47) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(48) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(49) <= toSlv(2, hitLen(0)(0)'length);
   ---------------------------------------
   ---------------------------------------
   ---------------------------------------
     wait for CLK_PERIOD_SPARSE_C*50;
         sro <= '1';
     wait for CLK_PERIOD_SPARSE_C*2;
         sro <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    wait for CLK_PERIOD_SPARSE_C*300;
      ero <= '1';
    wait for CLK_PERIOD_SPARSE_C*2;
      ero <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wait for CLK_PERIOD_SPARSE_C*50;
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   ---------------------------------------
   hitLen(0)(0) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(1) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(3) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(4) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(5) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(6) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(7) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(8) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(9) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(11) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(12) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(13) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(14) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(15) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(16) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(17) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(19) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(21) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(22) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(23) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(24) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(25) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(26) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(27) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(28) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(29) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(30) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(31) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(32) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(33) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(34) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(35) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(36) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(37) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(38) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(39) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(40) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(41) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(42) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(43) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(44) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(45) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(46) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(47) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(48) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(49) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(1)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(2) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(3) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(4) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(7) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(9) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(10) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(11) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(12) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(13) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(15) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(16) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(17) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(19) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(21) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(22) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(23) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(24) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(25) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(26) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(27) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(28) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(29) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(30) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(31) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(32) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(33) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(34) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(35) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(36) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(37) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(38) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(39) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(40) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(41) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(42) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(43) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(44) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(45) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(46) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(47) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(48) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(49) <= toSlv(3, hitLen(0)(0)'length);

   ---------------------------------------
   ---------------------------------------
   ---------------------------------------
wait for CLK_PERIOD_SPARSE_C*50;
   sro <= '1';
wait for CLK_PERIOD_SPARSE_C*2;
   sro <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    wait for CLK_PERIOD_SPARSE_C*300;
      ero <= '1';
    wait for CLK_PERIOD_SPARSE_C*2;
      ero <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wait for CLK_PERIOD_SPARSE_C*50;
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   ---------------------------------------
   hitLen(0)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(2) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(3) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(5) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(6) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(7) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(0)(8) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(10) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(0)(11) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(0)(12) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(13) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(14) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(16) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(0)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(18) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(19) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(0)(20) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(21) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(0)(22) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(23) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(24) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(25) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(26) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(0)(27) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(28) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(0)(29) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(30) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(31) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(32) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(33) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(34) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(35) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(36) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(37) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(38) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(39) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(40) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(41) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(42) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(43) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(44) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(45) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(46) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(47) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(48) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(49) <= toSlv(1, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(1)(0) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(2) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(3) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(4) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(6) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(7) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(9) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(10) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(11) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(12) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(13) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(15) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(17) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(19) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(21) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(23) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(24) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(25) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(26) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(27) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(28) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(29) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(30) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(31) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(32) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(33) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(34) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(35) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(36) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(37) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(38) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(39) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(40) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(41) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(42) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(43) <= toSlv(5, hitLen(0)(0)'length);
   hitLen(1)(44) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(45) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(46) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(47) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(48) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(49) <= toSlv(5, hitLen(0)(0)'length);
   ---------------------------------------
   ---------------------------------------
   ---------------------------------------
  wait for CLK_PERIOD_SPARSE_C*50;
      sro <= '1';
  wait for CLK_PERIOD_SPARSE_C*2;
      sro <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    wait for CLK_PERIOD_SPARSE_C*300;
      ero <= '1';
    wait for CLK_PERIOD_SPARSE_C*2;
      ero <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wait for CLK_PERIOD_SPARSE_C*50;
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   ---------------------------------------
   hitLen(0)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(2) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(3) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(4) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(6) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(7) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(9) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(10) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(11) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(12) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(13) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(14) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(15) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(17) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(18) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(19) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(21) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(23) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(24) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(25) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(26) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(27) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(28) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(29) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(30) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(31) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(32) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(33) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(34) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(35) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(36) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(37) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(38) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(39) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(40) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(41) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(42) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(43) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(44) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(45) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(46) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(47) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(48) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(49) <= toSlv(4, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(1)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(1) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(2) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(3) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(5) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(7) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(9) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(10) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(12) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(13) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(14) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(15) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(16) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(17) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(19) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(21) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(23) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(24) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(25) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(26) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(27) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(28) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(29) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(30) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(31) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(32) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(33) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(34) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(35) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(36) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(37) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(38) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(39) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(40) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(41) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(42) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(43) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(44) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(45) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(46) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(47) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(48) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(49) <= toSlv(3, hitLen(0)(0)'length);
   ---------------------------------------
   ---------------------------------------
   ---------------------------------------
wait for CLK_PERIOD_SPARSE_C*50;
   sro <= '1';
wait for CLK_PERIOD_SPARSE_C*2;
   sro <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wait for CLK_PERIOD_SPARSE_C*800;
   ero <= '1';
wait for CLK_PERIOD_SPARSE_C*2;
   ero <= '0';

   -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   wait for CLK_PERIOD_SPARSE_C*93;
end loop;


   -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     ----------------------------------------------
     ----------------------------------------------
     -- regular stimuli end

       -- do not touch begin
       wait;
       -- do not touch end

  end process regularStimulus;

end generate GEN_REGULAR_PROC;

 -------------------------------------------------------------
 -------------------------------------------------------------
 -------------------------------------------------------------

GEN_BENCHMARK_PROC: if BENCHMARKING_G generate

 benchmarkStimulus: process begin

   wait for CLK_PERIOD_SPARSE_C;
      rst <= RST_POLARITY_G;
   wait for CLK_PERIOD_SPARSE_C*100;
      rst  <= not(RST_POLARITY_G);

   -- Wait for the rst to be released before doing anything else
   wait until (rst = not(RST_POLARITY_G));

   wait for CLK_PERIOD_SPARSE_C*2100; -- extend wait to align pgp protocol

   for i in 0 to OCC_BENCHMARK_COUNT-1 loop

      wait for CLK_PERIOD_SPARSE_C*200;
         rstCnt <= '1';

      wait for CLK_PERIOD_SPARSE_C*1;
         rstCnt <= '0';

         for ser in 0 to NUM_OF_SERIALIZERS_C-1 loop
            for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
               hitLen(ser)(col) <= toSlv(colHitsArray(i), hitLen(ser)(col)'length);
            end loop;
         end loop;

         sro <= '1';

      wait for CLK_PERIOD_SPARSE_C*2;
         sro  <= '0';

      wait until (asicRxMaster.tLast = '1');
         report "[INFO]: Done with occ = " & real'image(occArray(i)) & "% !" severity note;


      wait for CLK_PERIOD_SPARSE_C*20;
         colBusyArray(i)      <= conv_integer(unsigned(colBusyCnt));
         superBusyArray(i)    <= conv_integer(unsigned(superBusyCnt));
         totalLatencyArray(i) <= conv_integer(unsigned(totalLatencyCnt));

      wait for CLK_PERIOD_SPARSE_C*20;
         report "[INFO]: occ = " & real'image(occArray(i)) & "% colBusyCnt = " & integer'image(colBusyArray(i)) severity note;
         report "[INFO]: occ = " & real'image(occArray(i)) & "% superBusyCnt = " & integer'image(superBusyArray(i)) severity note;
         report "[INFO]: occ = " & real'image(occArray(i)) & "% totalLatencyCnt = " & integer'image(totalLatencyArray(i)) severity note;

   end loop;

   wait for CLK_PERIOD_SPARSE_C*100;
      report "[INFO]: Done benchmarking! Final results below..." severity note;

      for i in 0 to OCC_BENCHMARK_COUNT-1 loop
         report "[INFO]: occ = " & real'image(occArray(i)) & "% colBusyCnt = " & integer'image(colBusyArray(i)) severity note;
         report "[INFO]: occ = " & real'image(occArray(i)) & "% superBusyCnt = " & integer'image(superBusyArray(i)) severity note;
         report "[INFO]: occ = " & real'image(occArray(i)) & "% totalLatencyCnt = " & integer'image(totalLatencyArray(i)) severity note;
      end loop;

   -- do not touch begin
   wait;
   -- do not touch end

 end process benchmarkStimulus;

end generate GEN_BENCHMARK_PROC;
 -------------------------------------------------------------
 -------------------------------------------------------------
 -------------------------------------------------------------

  -- Process to Monitor AXI Stream and Write to File
  FileWriteProcessAsic : process(sysClk)
    file myFile : text open write_mode is "pix2pgpAxiDataDump.dat";
    variable row : line;
    variable byte : std_logic_vector(7 downto 0);
  begin
    if rising_edge(sysClk) then
      if m_axis_tvalid = '1' then
        for i in 0 to AXIS_CONFIG_C.TDATA_BYTES_C - 1 loop
          if m_axis_tkeep(i) = '1' then
            byte := m_axis_tdata((i*8+7) downto (i*8));
            hwrite(row, byte, LEFT, 0);
            writeline(myFile, row);
            row.all := "";
          end if;
        end loop;
      end if;
    end if;
  end process;

  MeasureColBusyProc : process(pgpClk)
   variable cnt : slv(31 downto 0) := (others => '0');
  begin
    if rising_edge(pgpClk) then
      cfgColBusyDel <= cfgColBusy(0);

      if rstCnt = '1' then

         cnt        := (others => '0');
         colBusyCnt <= (others => '0');

      else

         if cfgColBusyDel = '1' then
            cnt := cnt + 1;
         end if;

         if (cfgColBusyDel = '1' and cfgColBusy(0) = '0') or
            (cfgSuperBusyDel = '1' and cfgSuperBusy(0) = '0') then
            colBusyCnt <= cnt;
         end if;

      end if;

    end if;
  end process;

  MeasureSuperBusyProc : process(pgpClk)
   variable cnt : slv(31 downto 0) := (others => '0');
  begin
    if rising_edge(pgpClk) then

      if rstCnt = '1' then

         cnt          := (others => '0');
         superBusyCnt <= (others => '0');

      else
         cfgSuperBusyDel <= cfgSuperBusy(0);

         if cfgSuperBusyDel = '1' then
            cnt := cnt + 1;
         end if;

         if (cfgColBusyDel = '1' and cfgColBusy(0) = '0') or
            (cfgSuperBusyDel = '1' and cfgSuperBusy(0) = '0') then
            superBusyCnt <= cnt;
         end if;
      end if;

    end if;
  end process;

  MeasureTotalLatencyProc : process(pgpClk)
   variable cnt : slv(31 downto 0) := (others => '0');
  begin
    if rising_edge(pgpClk) then

      if rstCnt = '1' then

         cnt             := (others => '0');
         totalLatencyCnt <= (others => '0');

      else

         if cnt > 0 then
            cnt := cnt + 1;
         elsif sro = '1' and sroFinal = '0' then
            cnt := cnt + 1;
         end if;

         if asicRxMaster.tLast = '1' then
            totalLatencyCnt <= cnt;
         end if;

      end if;

    end if;
  end process;

end architecture;
