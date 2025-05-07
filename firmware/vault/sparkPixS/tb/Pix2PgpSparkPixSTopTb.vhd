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
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpSparkPixSTopTb is
   generic(
      TPD_G                     : time     := 1 ns;
      RST_ASYNC_G               : boolean  := true;
      RST_POLARITY_G            : sl       := '0';
      FPGA_SYNTH_G              : boolean  := false;
      PIPELINE_DATA_G           : boolean  := false;
      PIPELINE_STATUS_G         : boolean  := true;
      TIMEOUT_LIMIT_WIDTH_G     : positive := 12;
      COLMANAGER_DATA_DEPTH_G   : integer  := 8;
      COLMANAGER_STATUS_DEPTH_G : integer  := 8;
      DATAFIFO_PIPE_G           : natural  := 1;
      STATUSFIFO_PIPE_G         : natural  := 1;
      NUM_VC_G                  : natural  := 1
   );
   port (
    dummyIn : in sl
  );

end entity Pix2PgpSparkPixSTopTb;

-- * about the AF_LVL_G flags:
-- the surf-based fifos issue their almost-full/prog-full when wr_index = AF_LVL_G;
-- the synopsys fifos raise their flag when wr_index = DEPTH_G-AF_LVL_G;
-- i.e. for the synopsys fifos, the AF_LVL_G denotes the amount of empty memory spaces before
-- the almost-full flag is asserted

architecture test of Pix2PgpSparkPixSTopTb is

   constant CLK_PERIOD_SPARSE_C : time := 10.768 ns;
   constant CLK_PERIOD_PGP_C    : time := 5.3846 ns;
   constant CLK_PERIOD_SYS_C    : time := 6.25   ns;
   constant REV_RST_POLARITY_C  : sl   := not(RST_POLARITY_G);

   signal sparseClk : sl := '0';
   signal pgpClk    : sl := '0';
   signal sysClk    : sl := '0';
   signal rst       : sl := '0';
   signal sro       : sl := '0';
   signal sroFinal  : sl := '0';
   signal revRst    : sl := '0';

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

   type hitLenArray is array (0 to NUM_OF_COL_MANAGERS_C-1) of slv(9 downto 0);

   type metaHitLenArray is array (0 to NUM_OF_SERIALIZERS_C-1) of hitLenArray;

   signal hitLen  : metaHitLenArray := (others => (others => (others => '0')));

   type pgpDataAsicType is array (0 to NUM_OF_SERIALIZERS_C-1) of slv(31 downto 0);

   signal pgpDataAsic      : pgpDataAsicType := (others => (others => '0'));
   signal pgpDataAsicValid : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal pgpDataAsicReady : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal pgpDataAsicValidVec : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal pgp4RxMaster : AxiStreamMasterArray(0 to NUM_OF_SERIALIZERS_C-1) := (others => AXI_STREAM_MASTER_INIT_C);
   signal pgp4RxSlave : AxiStreamSlaveArray(0 to NUM_OF_SERIALIZERS_C-1) := (others => AXI_STREAM_SLAVE_INIT_C);

   signal asicRxMaster   : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal asicRxSlave    : AxiStreamSlaveType  := AXI_STREAM_SLAVE_FORCE_C; -- force to ready

   signal m_axis_tvalid  : sl := '0';
   signal m_axis_tdata   : slv(FPGA_RX_AXI_CONFIG_C.TDATA_BYTES_C*8-1 downto 0) := (others => '0');
   signal m_axis_tstrb   : slv(FPGA_RX_AXI_CONFIG_C.TDATA_BYTES_C-1 downto 0)   := (others => '0');
   signal m_axis_tkeep   : slv(FPGA_RX_AXI_CONFIG_C.TDATA_BYTES_C-1 downto 0)   := (others => '0');
   signal m_axis_tlast   : sl := '0';
   signal m_axis_tdest   : slv(7 downto 0) := (others => '0');
   signal m_axis_tid     : slv(7 downto 0) := (others => '0');
   signal m_axis_tuser   : slv(7 downto 0) := (others => '0');

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

   --------
   -- Pixel
   --------
   GEN_SERIALIZER: for ser in 0 to NUM_OF_SERIALIZERS_C-1 generate

      GEN_DUMMY_PIXEL: for col in 0 to NUM_OF_COL_MANAGERS_C-1 generate
         U_DummyPixel : entity pix2pgp.DummySparkPixSPixel
            generic map(
               TPD_G          => TPD_G,
               RST_ASYNC_G    => RST_ASYNC_G,
               RST_POLARITY_G => RST_POLARITY_G,
               WAIT_FB_G      => 4,
               WAIT_ACKN_G    => 3, -- 14 as per Hyunjoon (so 7+7=14)
               WAIT_WREN_G    => 3, -- 14 as per Hyunjoon
               SER_ID_G       => ser,
               COL_ID_G       => col)
            port map(
               clk      => sparseClk,
               rst      => rst,
               sro      => sroFinal,
               pause    => pause(ser)(col),
               hitLen   => hitLen(ser)(col),
               pauseAck => pauseAck(ser)(col),
               tok      => open,
               tokFb    => tokFb(ser)(col),
               ackN     => ackN(ser)(col),
               wrEn     => wrEn(ser)(col),
               dout     => din(ser)(col));

         U_DummyFlowCtrl: entity pix2pgp.SparkPixSFlowCtrl
           generic map(
             RST_POLARITY_G => RST_POLARITY_G,
             COL_ID_G       => col)
           port map(
               clk             => sparseClk,
               df_reset_n      => rst,
               sro             => sroFinal,
               tok_fb          => tokFb(ser)(col),
               sparse_itf_busy => sparseBusy(ser)(col),
               pix2pgp_busy    => busy(ser)(col),
               sof             => sof(ser)(col),
               eof             => eof(ser)(col),
               over_occ        => overOcc(ser)(col));
      end generate GEN_DUMMY_PIXEL;

      ------
      -- UUT
      ------
      U_Uut : entity pix2pgp.Pix2PgpSparkPixSTop
         generic map(
            TPD_G                      => TPD_G,
            RST_ASYNC_G                => RST_ASYNC_G,
            RST_POLARITY_G             => RST_POLARITY_G,
            DATAFIFO_PIPE_G            => DATAFIFO_PIPE_G,
            STATUSFIFO_PIPE_G          => STATUSFIFO_PIPE_G,
            TIMEOUT_LIMIT_WIDTH_G      => TIMEOUT_LIMIT_WIDTH_G,
            PIPELINE_DATA_G            => PIPELINE_DATA_G,
            PIPELINE_STATUS_G          => PIPELINE_STATUS_G,
            COLMANAGER_DATA_DEPTH_G    => COLMANAGER_DATA_DEPTH_G,
            COLMANAGER_STATUS_DEPTH_G  => COLMANAGER_STATUS_DEPTH_G)
         port map(
            sparseClk    => sparseClk,
            sparseRst    => rst,
            pgpClk       => pgpClk,
            pgpRst       => rst,
            sel          => '1',
            timeoutLimit => x"0FF",
            pauseLimit   => x"00C",
            columnEnable => x"FFFFFF",
            pause        => pause(ser),
            sof          => sof(ser),
            eof          => eof(ser),
            busy         => busy(ser),
            overOcc      => overOcc(ser),
            pauseAck     => pauseAck(ser),
            wrEn         => wrEn(ser),
            din0         => din(ser)(0),
            din1         => din(ser)(1),
            din2         => din(ser)(2),
            din3         => din(ser)(3),
            din4         => din(ser)(4),
            din5         => din(ser)(5),
            din6         => din(ser)(6),
            din7         => din(ser)(7),
            din8         => din(ser)(8),
            din9         => din(ser)(9),
            din10        => din(ser)(10),
            din11        => din(ser)(11),
            din12        => din(ser)(12),
            din13        => din(ser)(13),
            din14        => din(ser)(14),
            din15        => din(ser)(15),
            din16        => din(ser)(16),
            din17        => din(ser)(17),
            din18        => din(ser)(18),
            din19        => din(ser)(19),
            din20        => din(ser)(20),
            din21        => din(ser)(21),
            din22        => din(ser)(22),
            din23        => din(ser)(23),
            pgpDout      => pgpDataAsic(ser),
            pgpDoutValid => pgpDataAsicValid(ser),
            pgpDoutReady => pgpDataAsicReady(ser));

   end generate GEN_SERIALIZER;

   -------
   -- FPGA
   -------

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
          clk          => pgpClk,
          rst          => revRst,
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
         TPD_G                 => TPD_G,
         RST_ASYNC_G           => false,
         RST_POLARITY_G        => REV_RST_POLARITY_C,
         ASIC_ID_G             => 0,
         TIMEOUT_LIMIT_WIDTH_G => 16)
      port map(
         -- General Interface
         pgpClk          => pgpClk,
         pgpRst          => revRst,
         sysClk          => sysClk,
         sysRst          => revRst,
         -- ASIC Domain Interface
         asicClk         => sparseClk,
         asicRst         => rst,
         asicSro         => sroFinal,
         asicSroEna      => '1',
         -- PGP4Rx Interface
         pgp4RxMaster    => pgp4RxMaster,
         pgp4RxSlave     => pgp4RxSlave,
         -- AXI-Stream Rx Interface
         asicRxMaster    => asicRxMaster,
         asicRxSlave     => asicRxSlave,
         -- AXI-Lite Interface
         axilClk         => sysClk,
         axilRst         => revRst,
         axilReadMaster  => AXI_LITE_READ_MASTER_INIT_C,
         axilReadSlave   => open,
         axilWriteMaster => AXI_LITE_WRITE_MASTER_INIT_C,
         axilWriteSlave  => open);

   -- Map PgpRxMasters to AXI
   axiMaster : entity surf.MasterAxiStreamIpIntegrator
      generic map (
         INTERFACENAME   => "M_AXIS",
         TUSER_WIDTH     => 8,
         TID_WIDTH       => 8,
         TDEST_WIDTH     => 8,
         TDATA_NUM_BYTES => FPGA_RX_AXI_CONFIG_C.TDATA_BYTES_C)
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
         axisMaster     => asicRxMaster,
         axisSlave      => asicRxSlave);

  -- Generate the test stimulus
  stimulus: process begin

    -- do not touch begin
    ----------------------------------------------
    ----------------------------------------------
    -- issue reset here
    wait for CLK_PERIOD_SPARSE_C;
      rst <= RST_POLARITY_G;
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
      sro  <= '0';
    ----------------------------------------------
    ----------------------------------------------
    -- do not touch end

    -- regular stimuli begin
    ----------------------------------------------
    ----------------------------------------------

    wait for CLK_PERIOD_SPARSE_C*93;
      sro <= '1';
    wait for CLK_PERIOD_SPARSE_C*2;
      sro  <= '0';

   wait for CLK_PERIOD_SPARSE_C*93;
      sro <= '1';
    wait for CLK_PERIOD_SPARSE_C*2;
      sro  <= '0';



-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wait for CLK_PERIOD_SPARSE_C*93;
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
---------------------------------------
for i in 0 to 10 loop
   hitLen(0)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(1) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(2) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(3) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(4) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(5) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(6) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(7) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(9) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(10) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(12) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(13) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(15) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(16) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(17) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(18) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(19) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(20) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(21) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(22) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(23) <= toSlv(1, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(1)(0) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(1) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(2) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(3) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(4) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(5) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(7) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(8) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(9) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(11) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(12) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(13) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(15) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(16) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(17) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(18) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(19) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(20) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(21) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(23) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(2)(0) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(2) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(3) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(5) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(6) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(7) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(9) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(10) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(11) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(12) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(13) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(14) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(16) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(18) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(19) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(21) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(22) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(23) <= toSlv(1, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(3)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(3) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(7) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(12) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(13) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(15) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(16) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(17) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(18) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(23) <= toSlv(4, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(4)(0) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(2) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(3) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(4) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(5) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(7) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(8) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(9) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(10) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(11) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(12) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(13) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(14) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(15) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(16) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(17) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(21) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(22) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(23) <= toSlv(4, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(5)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(2) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(3) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(4) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(6) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(7) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(8) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(9) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(10) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(11) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(12) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(13) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(14) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(15) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(16) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(17) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(18) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(19) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(21) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(22) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(23) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(6)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(1) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(2) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(3) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(4) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(5) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(6) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(7) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(8) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(9) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(10) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(11) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(12) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(13) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(14) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(15) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(17) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(18) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(21) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(22) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(23) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(7)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(2) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(3) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(4) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(5) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(6) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(7) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(9) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(10) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(12) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(13) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(14) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(15) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(18) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(19) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(20) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(21) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(22) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(23) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
sro  <= '1';
wait for CLK_PERIOD_SPARSE_C*2;
sro  <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wait for CLK_PERIOD_SPARSE_C*93;
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
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
   hitLen(0)(15) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(16) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(21) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(22) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(23) <= toSlv(0, hitLen(0)(0)'length);
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
---------------------------------------
---------------------------------------
   hitLen(2)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(1) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(3) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(6) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(7) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(9) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(10) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(11) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(12) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(13) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(14) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(15) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(16) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(17) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(19) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(22) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(23) <= toSlv(4, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(3)(0) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(1) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(2) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(3) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(4) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(5) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(6) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(7) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(9) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(12) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(13) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(16) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(17) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(18) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(21) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(22) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(23) <= toSlv(1, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(4)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(2) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(3) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(4) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(5) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(6) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(7) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(9) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(10) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(12) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(13) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(14) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(16) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(17) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(19) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(20) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(21) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(23) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(5)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(2) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(3) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(4) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(5) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(6) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(7) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(9) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(10) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(11) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(12) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(13) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(14) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(15) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(16) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(17) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(18) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(19) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(21) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(22) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(23) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(6)(0) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(3) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(4) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(5) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(6) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(7) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(11) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(12) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(13) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(15) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(16) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(18) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(19) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(20) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(22) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(23) <= toSlv(1, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(7)(0) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(1) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(3) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(5) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(7) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(9) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(10) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(12) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(13) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(14) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(15) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(17) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(19) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(21) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(22) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(23) <= toSlv(1, hitLen(0)(0)'length);
---------------------------------------
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
sro  <= '1';
wait for CLK_PERIOD_SPARSE_C*2;
sro  <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wait for CLK_PERIOD_SPARSE_C*93;
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
---------------------------------------
   hitLen(0)(0) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(1) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(2) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(3) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(5) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(6) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(7) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(8) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(11) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(12) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(13) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(15) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(16) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(18) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(19) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(20) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(21) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(22) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(23) <= toSlv(3, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(1)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(1) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(3) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(4) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(5) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(6) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(7) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(8) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(9) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(10) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(11) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(12) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(13) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(15) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(16) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(18) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(19) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(20) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(21) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(22) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(23) <= toSlv(3, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(2)(0) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(2) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(3) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(4) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(5) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(7) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(8) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(9) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(10) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(11) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(12) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(13) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(15) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(17) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(19) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(22) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(23) <= toSlv(1, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(3)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(3) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(4) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(5) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(6) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(7) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(8) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(9) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(11) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(12) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(13) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(15) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(16) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(17) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(18) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(20) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(22) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(23) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(4)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(1) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(2) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(3) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(4) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(6) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(7) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(11) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(12) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(13) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(14) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(15) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(16) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(18) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(19) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(20) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(21) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(22) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(23) <= toSlv(3, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(5)(0) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(1) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(2) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(3) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(7) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(8) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(9) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(11) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(12) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(13) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(14) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(15) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(17) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(18) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(19) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(21) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(22) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(23) <= toSlv(1, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(6)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(1) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(3) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(4) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(5) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(6) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(7) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(9) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(10) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(11) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(12) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(13) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(14) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(16) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(18) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(19) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(23) <= toSlv(4, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(7)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(3) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(4) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(7) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(10) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(12) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(13) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(15) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(16) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(18) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(20) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(23) <= toSlv(4, hitLen(0)(0)'length);
---------------------------------------
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
sro  <= '1';
wait for CLK_PERIOD_SPARSE_C*2;
sro  <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wait for CLK_PERIOD_SPARSE_C*93;
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
---------------------------------------
   hitLen(0)(0) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(1) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(2) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(3) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(4) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(5) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(6) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(7) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(8) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(11) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(12) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(13) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(14) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(15) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(16) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(17) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(18) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(19) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(22) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(23) <= toSlv(4, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(1)(0) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(1) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(2) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(3) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(4) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(5) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(6) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(7) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(8) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(10) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(12) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(13) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(14) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(16) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(17) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(18) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(19) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(20) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(21) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(23) <= toSlv(3, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(2)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(2) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(3) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(4) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(6) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(7) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(8) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(10) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(11) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(12) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(13) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(15) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(16) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(17) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(18) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(19) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(20) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(22) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(23) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(3)(0) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(2) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(3) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(4) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(5) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(6) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(7) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(9) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(10) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(11) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(12) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(13) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(14) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(16) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(17) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(18) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(19) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(21) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(22) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(23) <= toSlv(4, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(4)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(1) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(3) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(4) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(6) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(7) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(8) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(10) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(12) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(13) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(14) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(16) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(18) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(19) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(20) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(21) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(22) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(23) <= toSlv(4, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(5)(0) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(2) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(3) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(4) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(5) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(6) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(7) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(9) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(10) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(11) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(12) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(13) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(14) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(15) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(16) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(18) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(19) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(21) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(22) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(23) <= toSlv(4, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(6)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(2) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(3) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(4) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(5) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(7) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(9) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(12) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(13) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(14) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(15) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(18) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(19) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(23) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(7)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(1) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(2) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(3) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(4) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(5) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(6) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(7) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(8) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(9) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(10) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(12) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(13) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(14) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(15) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(17) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(18) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(19) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(20) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(21) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(22) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(23) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
sro  <= '1';
wait for CLK_PERIOD_SPARSE_C*2;
sro  <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wait for CLK_PERIOD_SPARSE_C*93;
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
---------------------------------------
   hitLen(0)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(1) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(2) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(3) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(4) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(5) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(6) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(7) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(8) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(10) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(12) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(13) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(14) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(15) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(16) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(17) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(19) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(20) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(21) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(23) <= toSlv(3, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(1)(0) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(3) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(5) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(6) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(7) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(9) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(10) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(12) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(13) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(14) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(15) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(17) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(18) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(20) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(22) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(23) <= toSlv(4, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(2)(0) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(2) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(3) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(5) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(7) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(9) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(10) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(11) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(12) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(13) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(14) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(16) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(17) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(19) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(20) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(21) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(22) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(23) <= toSlv(0, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(3)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(1) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(2) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(3) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(4) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(5) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(6) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(7) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(10) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(11) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(12) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(13) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(14) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(16) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(17) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(18) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(19) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(20) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(21) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(22) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(23) <= toSlv(0, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(4)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(1) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(3) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(4) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(5) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(7) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(8) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(9) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(11) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(12) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(13) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(15) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(16) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(17) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(18) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(19) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(20) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(21) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(23) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(5)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(1) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(2) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(3) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(5) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(6) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(7) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(8) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(9) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(10) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(11) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(12) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(13) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(15) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(16) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(17) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(19) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(20) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(21) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(23) <= toSlv(4, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(6)(0) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(2) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(3) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(4) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(5) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(7) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(8) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(11) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(12) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(13) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(14) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(15) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(17) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(18) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(19) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(21) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(23) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(7)(0) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(2) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(3) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(4) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(6) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(7) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(8) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(9) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(10) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(11) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(12) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(13) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(15) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(16) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(17) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(18) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(20) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(22) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(23) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
sro  <= '1';
wait for CLK_PERIOD_SPARSE_C*2;
sro  <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wait for CLK_PERIOD_SPARSE_C*93;
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
---------------------------------------
   hitLen(0)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(1) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(2) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(3) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(4) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(5) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(6) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(7) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(8) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(9) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(10) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(12) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(13) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(14) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(15) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(16) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(18) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(19) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(21) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(22) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(23) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(1)(0) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(1) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(2) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(3) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(7) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(8) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(9) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(10) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(12) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(13) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(14) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(15) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(16) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(17) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(18) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(20) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(21) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(22) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(23) <= toSlv(0, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(2)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(1) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(2) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(3) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(4) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(5) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(7) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(8) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(9) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(10) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(11) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(2)(12) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(13) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(14) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(2)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(16) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(17) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(18) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(19) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(2)(20) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(2)(21) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(22) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(23) <= toSlv(0, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(3)(0) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(2) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(3) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(4) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(5) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(6) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(7) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(9) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(11) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(12) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(13) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(14) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(18) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(19) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(23) <= toSlv(4, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(4)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(1) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(3) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(5) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(7) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(9) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(10) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(11) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(12) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(13) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(14) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(16) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(17) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(18) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(19) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(22) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(23) <= toSlv(1, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(5)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(2) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(3) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(4) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(5) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(6) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(7) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(8) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(9) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(11) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(12) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(13) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(17) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(20) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(21) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(23) <= toSlv(0, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(6)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(1) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(3) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(4) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(6) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(7) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(9) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(10) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(12) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(13) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(14) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(15) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(16) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(17) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(18) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(19) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(20) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(21) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(22) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(23) <= toSlv(3, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(7)(0) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(3) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(4) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(5) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(7) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(8) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(10) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(11) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(12) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(13) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(15) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(16) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(17) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(18) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(19) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(21) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(22) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(23) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
sro  <= '1';
wait for CLK_PERIOD_SPARSE_C*2;
sro  <= '0';
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wait for CLK_PERIOD_SPARSE_C*93;
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
---------------------------------------
   hitLen(0)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(2) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(3) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(4) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(7) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(9) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(11) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(12) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(13) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(0)(14) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(15) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(16) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(17) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(0)(18) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(0)(20) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(21) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(0)(22) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(0)(23) <= toSlv(3, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(1)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(1) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(3) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(5) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(6) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(1)(7) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(8) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(9) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(10) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(12) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(13) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(14) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(15) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(16) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(1)(17) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(18) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(1)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(20) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(21) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(1)(22) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(1)(23) <= toSlv(1, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(2)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(2) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(3) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(4) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(5) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(7) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(8) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(9) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(10) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(11) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(12) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(13) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(14) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(15) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(16) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(17) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(20) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(21) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(22) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(2)(23) <= toSlv(0, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(3)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(2) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(3) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(4) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(5) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(6) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(7) <= toSlv(21, hitLen(0)(0)'length);
   hitLen(3)(8) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(9) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(10) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(11) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(3)(12) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(13) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(14) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(3)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(17) <= toSlv(15, hitLen(0)(0)'length);
   hitLen(3)(18) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(19) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(3)(21) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(3)(22) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(3)(23) <= toSlv(4, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(4)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(1) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(3) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(4) <= toSlv(40, hitLen(0)(0)'length);
   hitLen(4)(5) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(7) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(4)(9) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(10) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(11) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(12) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(13) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(14) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(16) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(17) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(4)(18) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(19) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(4)(21) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(4)(22) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(4)(23) <= toSlv(0, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(5)(0) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(1) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(2) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(3) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(4) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(5) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(6) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(7) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(8) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(9) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(10) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(11) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(12) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(13) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(5)(14) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(15) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(16) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(17) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(18) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(19) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(5)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(5)(21) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(5)(22) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(5)(23) <= toSlv(2, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(6)(0) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(1) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(3) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(4) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(6) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(7) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(8) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(9) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(10) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(11) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(12) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(13) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(14) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(6)(16) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(17) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(18) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(6)(19) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(6)(21) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(6)(22) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(6)(23) <= toSlv(1, hitLen(0)(0)'length);
---------------------------------------
---------------------------------------
   hitLen(7)(0) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(1) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(2) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(3) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(4) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(5) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(6) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(7) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(8) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(9) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(10) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(11) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(12) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(13) <= toSlv(3, hitLen(0)(0)'length);
   hitLen(7)(14) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(15) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(16) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(17) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(18) <= toSlv(2, hitLen(0)(0)'length);
   hitLen(7)(19) <= toSlv(0, hitLen(0)(0)'length);
   hitLen(7)(20) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(21) <= toSlv(4, hitLen(0)(0)'length);
   hitLen(7)(22) <= toSlv(1, hitLen(0)(0)'length);
   hitLen(7)(23) <= toSlv(0, hitLen(0)(0)'length);
   ---------------------------------------
   -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   sro  <= '1';
   wait for CLK_PERIOD_SPARSE_C*2;
   sro  <= '0';

   -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   wait for CLK_PERIOD_SPARSE_C*93;
end loop;


-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ----------------------------------------
  ----------------------------------------

    -- do not touch begin
    wait;
    -- do not touch end

  end process stimulus;

  revRst <= not(rst);

  -- Process to Monitor AXI Stream and Write to File
  FileWriteProcessAsic : process(sysClk)
    file myFile : text open write_mode is "pix2pgpAxiDataDump.dat";
    variable row : line;
    variable byte : std_logic_vector(7 downto 0);
  begin
    if rising_edge(sysClk) then
      if m_axis_tvalid = '1' then
        for i in 0 to FPGA_RX_AXI_CONFIG_C.TDATA_BYTES_C - 1 loop
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

end architecture;
