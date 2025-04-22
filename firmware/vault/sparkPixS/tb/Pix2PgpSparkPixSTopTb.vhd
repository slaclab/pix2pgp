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

   signal sparseClk : sl := '0';
   signal pgpClk    : sl := '0';
   signal sysClk    : sl := '0';
   signal rst       : sl := '0';
   signal sro       : sl := '0';
   signal sroFinal  : sl := '0';

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
   signal hitLen  : hitLenArray := (others => (others => '0'));

   type pgpDataAsicType is array (0 to NUM_OF_SERIALIZERS_C-1) of slv(31 downto 0);

   signal pgpDataAsic      : pgpDataAsicType := (others => (others => '0'));
   signal pgpDataAsicValid : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal pgpDataAsicReady : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal pgpDataAsicValidVec : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal pgpValid  : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal pgpReady  : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal pgpData   : Pix2PgpFpgaRxDataArray := (others => DEFAULT_PIX2PGP_DATABUS_C);

   signal laneError      : sl := '0';
   signal laneErrorAck   : sl := '1';
   signal asicTxMaster   : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal asicTxSlave    : AxiStreamSlaveType  := AXI_STREAM_SLAVE_FORCE_C; -- force to ready

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

  writeDataProcess: process(pgpClk)

    -- variables for file-writing
    file myFile  : text open write_mode is "pix2pgpRxDataDump.dat";
    variable row : line;

  begin
    if (rising_edge(pgpClk)) then
        -- check if the valid flag is high
        if pgpValid(0) = '1' then
          -- syntax: write(row_variable,what_to_write,
          -- justification(right/left), trailing_whitespaces);
          -- writeline(file_variable, row_variable);
          hwrite(row, pgpData(0).data, right, 0);
          writeline(myFile,row);
        end if;
      end if;
  end process;

  -- Process to Monitor AXI Stream and Write to File
  FileWriteProcess : process(sysClk)
    file myFile        : text open write_mode is "pix2pgpAxiDataDump.dat";
    variable tmp       : std_logic_vector(39 downto 0);
    variable row       : line;
    variable keep_mask : slv(7 downto 0);
  begin
    if rising_edge(sysClk) then
      if asicTxMaster.tValid = '1' then
         tmp := (others => '0');
        -- Write only valid data bytes according to tKeep using 40-bit words
        for i in 0 to 127 loop
          if asicTxMaster.tKeep(i) = '1' then
            keep_mask := asicTxMaster.tData((i*8+7) downto (i*8));
            tmp       := keep_mask & tmp(39 downto 8);

            if (i + 1) mod 5 = 0 then
              -- Write every 5 bytes as one 40-bit word
              hwrite(row, tmp, right, 0);
              writeline(myFile, row);
            end if;
          end if;
        end loop;
      end if;
    end if;
  end process;

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
               COL_ID_G       => col)
            port map(
               clk      => sparseClk,
               rst      => rst,
               sro      => sroFinal,
               pause    => pause(ser)(col),
               hitLen   => hitLen(col),
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

   -- same stream on all lanes
   GEN_LANE: for lane in 0 to NUM_OF_SERIALIZERS_C-1 generate

      -- pgp4 wrapper
      U_FPGA : entity pix2pgp.Pix2PgpFpgaTb
       generic map(
          TPD_G          => TPD_G,
          RST_ASYNC_G    => false,
          RST_POLARITY_G => RST_POLARITY_G,
          FPGA_SYNTH_G   => FPGA_SYNTH_G,
          NUM_VC_G       => NUM_VC_G)
       port map(
          -- General Interface
          clk         => pgpClk,
          rst         => rst,
          -- Pix2Pgp Interface
          pgpDin      => pgpDataAsic(lane),
          pgpDinValid => pgpDataAsicValid(lane),
          pgpDinReady => pgpDataAsicReady(lane),
          -- FPGA RX Interface
          pgpValid    => pgpValid(lane),
          pgpData     => pgpData(lane).data,
          pgpReady    => pgpReady(lane));

   end generate GEN_LANE;

   -- asic stream receiver and merger
   U_ASIC_STREAM_RX : entity pix2pgp.Pix2PgpAsicStreamRx
      generic map(
         TPD_G          => TPD_G,
         RST_ASYNC_G    => false,
         RST_POLARITY_G => RST_POLARITY_G)
      port map(
         -- General Interface
         asicClk          => sparseClk,
         asicRst          => rst,
         asicSro          => sroFinal,
         asicSroEna       => '1',
         pgpClk           => pgpClk,
         pgpRst           => rst,
         sysClk           => sysClk,
         sysRst           => rst,
         -- PGP4Rx Interface
         pgpValid         => pgpValid,
         pgpData          => pgpData,
         pgpReady         => pgpReady,
         -- AXI-Stream Rx Interface
         asicTxMaster     => asicTxMaster,
         asicTxSlave      => asicTxSlave,
         -- AXI-Lite Interface
         axilClk          => sysClk,
         axilRst          => rst,
         axilReadMaster   => AXI_LITE_READ_MASTER_INIT_C,
         axilReadSlave    => open,
         axilWriteMaster  => AXI_LITE_WRITE_MASTER_INIT_C,
         axilWriteSlave   => open);

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
    for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
      hitLen(col) <= toSlv(0, hitLen(col)'length);
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
       for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
         hitLen(col) <= toSlv(2, hitLen(col)'length);
       end loop;
         sro  <= '1';
     wait for CLK_PERIOD_SPARSE_C*2;
         sro  <= '0';

    -- wait for CLK_PERIOD_SPARSE_C*93;
    --  hitLen(0)  <= toSlv(0,  hitLen(5)'length);
    --  hitLen(1)  <= toSlv(3,  hitLen(5)'length);
    --  hitLen(2)  <= toSlv(0,  hitLen(5)'length);
    --  hitLen(3)  <= toSlv(0,  hitLen(5)'length);
    --  hitLen(4)  <= toSlv(1,  hitLen(5)'length);
    --  hitLen(5)  <= toSlv(2,  hitLen(5)'length);
    --  hitLen(6)  <= toSlv(0,  hitLen(6)'length);
    --  hitLen(7)  <= toSlv(2,  hitLen(7)'length);
    --  hitLen(8)  <= toSlv(0,  hitLen(8)'length);
    --  hitLen(9)  <= toSlv(0,  hitLen(9)'length);
    --  hitLen(10) <= toSlv(4,  hitLen(5)'length);
    --  hitLen(11) <= toSlv(3,  hitLen(5)'length);
    --  hitLen(12) <= toSlv(0,  hitLen(5)'length);
    --  hitLen(13) <= toSlv(3,  hitLen(5)'length);
    --  hitLen(14) <= toSlv(0,  hitLen(5)'length);
    --  hitLen(15) <= toSlv(2,  hitLen(5)'length);
    --  hitLen(16) <= toSlv(0,  hitLen(6)'length);
    --  hitLen(17) <= toSlv(1,  hitLen(7)'length);
    --  hitLen(18) <= toSlv(1,  hitLen(8)'length);
    --  hitLen(19) <= toSlv(0,  hitLen(9)'length);
    --  hitLen(20) <= toSlv(3,  hitLen(5)'length);
    --  hitLen(21) <= toSlv(0,  hitLen(5)'length);
    --  hitLen(22) <= toSlv(4,  hitLen(5)'length);
    --  hitLen(23) <= toSlv(0,  hitLen(5)'length);
    --  sro  <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  hitLen(0)  <= toSlv(2,  hitLen(5)'length);
    --  hitLen(1)  <= toSlv(3,  hitLen(5)'length);
    --  hitLen(2)  <= toSlv(1,  hitLen(5)'length);
    --  hitLen(3)  <= toSlv(3,  hitLen(5)'length);
    --  hitLen(4)  <= toSlv(1,  hitLen(5)'length);
    --  hitLen(5)  <= toSlv(2,  hitLen(5)'length);
    --  hitLen(6)  <= toSlv(3,  hitLen(6)'length);
    --  hitLen(7)  <= toSlv(2,  hitLen(7)'length);
    --  hitLen(8)  <= toSlv(0,  hitLen(8)'length);
    --  hitLen(9)  <= toSlv(0,  hitLen(9)'length);
    --  hitLen(10) <= toSlv(4,  hitLen(5)'length);
    --  hitLen(11) <= toSlv(3,  hitLen(5)'length);
    --  hitLen(12) <= toSlv(5,  hitLen(5)'length);
    --  hitLen(13) <= toSlv(3,  hitLen(5)'length);
    --  hitLen(14) <= toSlv(1,  hitLen(5)'length);
    --  hitLen(15) <= toSlv(2,  hitLen(5)'length);
    --  hitLen(16) <= toSlv(3,  hitLen(6)'length);
    --  hitLen(17) <= toSlv(3,  hitLen(7)'length);
    --  hitLen(18) <= toSlv(1,  hitLen(8)'length);
    --  hitLen(19) <= toSlv(4,  hitLen(9)'length);
    --  hitLen(20) <= toSlv(2,  hitLen(5)'length);
    --  hitLen(21) <= toSlv(2,  hitLen(5)'length);
    --  hitLen(22) <= toSlv(6,  hitLen(5)'length);
    --  hitLen(23) <= toSlv(0,  hitLen(5)'length);
    --  sro  <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

    -----------------------------------------------------------------------------
    -- reset test begin
    -----------------------------------------------------------------------------
    -- wait for CLK_PERIOD_SPARSE_C*2100; -- extend wait to make sure data are tx'd
    --  rst <= RST_POLARITY_G;
    -- wait for CLK_PERIOD_SPARSE_C*100;
    --  rst  <= not(RST_POLARITY_G);

    -- wait for CLK_PERIOD_SPARSE_C*2100; -- extend wait to align pgp protocol
    --  sro <= '1';
    -- wait for CLK_PERIOD_SPARSE_C*2;
    --  sro <= '0';
    -----------------------------------------------------------------------------
    -- reset test end
    -----------------------------------------------------------------------------
    ----------------------------------------------
    ----------------------------------------------
    -- regular stimuli end

    -- will force pause
    --wait for CLK_PERIOD_SPARSE_C*93;
    -- hitLen(0)  <= toSlv(0,  hitLen(5)'length);
    -- hitLen(1)  <= toSlv(31,  hitLen(5)'length);
    -- hitLen(2)  <= toSlv(0,  hitLen(5)'length);
    -- hitLen(3)  <= toSlv(0,  hitLen(5)'length);
    -- hitLen(4)  <= toSlv(4,  hitLen(5)'length);
    -- hitLen(5)  <= toSlv(24,  hitLen(5)'length);
    -- hitLen(6)  <= toSlv(0,  hitLen(6)'length);
    -- hitLen(7)  <= toSlv(1,  hitLen(7)'length);
    -- hitLen(8)  <= toSlv(5,  hitLen(8)'length);
    -- hitLen(9)  <= toSlv(0,  hitLen(9)'length);
    -- hitLen(10) <= toSlv(4,  hitLen(5)'length);
    -- hitLen(11) <= toSlv(20,  hitLen(5)'length);
    -- hitLen(12) <= toSlv(0,  hitLen(5)'length);
    -- hitLen(13) <= toSlv(3,  hitLen(5)'length);
    -- hitLen(14) <= toSlv(4,  hitLen(5)'length);
    -- hitLen(15) <= toSlv(2,  hitLen(5)'length);
    -- hitLen(16) <= toSlv(0,  hitLen(6)'length);
    -- hitLen(17) <= toSlv(2,  hitLen(7)'length);
    -- hitLen(18) <= toSlv(18,  hitLen(8)'length);
    -- hitLen(19) <= toSlv(0,  hitLen(9)'length);
    -- hitLen(20) <= toSlv(3,  hitLen(5)'length);
    -- hitLen(21) <= toSlv(0,  hitLen(5)'length);
    -- hitLen(22) <= toSlv(4,  hitLen(5)'length);
    -- hitLen(23) <= toSlv(0,  hitLen(5)'length);
    -- sro  <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    -- sro  <= '0';

     -- blast it; use with VCS (ghdl is not fast enough)
     --for trg in 0 to 1023 loop
     --  wait for CLK_PERIOD_SPARSE_C*93;
     -- hitLen(col) <= toSlv(4, hitLen(col)'length);
     --   sro <= '1';
     --  wait for CLK_PERIOD_SPARSE_C*2;
     --   sro <= '0';
     --end loop;
  ----------------------------------------
  ----------------------------------------

    -- do not touch begin
    wait;
    -- do not touch end

  end process stimulus;

end architecture;
