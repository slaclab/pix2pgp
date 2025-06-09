-- SparkPix-T Wrapper

-- keeping it simple
-- maybe can create a dinArray equivalent in systemVerilog?
-- breaking down the din into individual std_logic_vectors works too though...

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

library surf;
use surf.AxiStreamPkg.all;
use surf.StdRtlPkg.all;

entity Pix2PgpSparkPixTTop is
   generic(
      TPD_G                     : time      := 1 ns;
      RST_ASYNC_G               : boolean   := true;
      RST_POLARITY_G            : std_logic := '0';
      PIPELINE_DATA_G           : boolean   := false; -- pipeline data FIFO output downstream
      PIPELINE_STATUS_G         : boolean   := true;  -- pipeline status FIFO output downstream
      COLMANAGER_DATA_DEPTH_G   : integer   := 8;     -- colManager data FIFO depth (holds *2 hits)
      COLMANAGER_STATUS_DEPTH_G : integer   := 8;     -- colManager status FIFO depth (1 per event)
      DATAFIFO_PIPE_G           : natural   := 1;     -- colManager data FIFO I/O pipeline stages
      STATUSFIFO_PIPE_G         : natural   := 1;     -- colManager status FIFO I/O pipeline stages
      SER_GBOX_PIPE_G           : natural   := 0);    -- *only* set when synthesizing (*not* in sim)
   port(
      -- General Interface
      sparseClk         : in  std_logic;
      pgpClk            : in  std_logic;
      sparseRst         : in  std_logic;
      pgpRst            : in  std_logic;
      -- Configuration Registers
      cfgSel            : in  std_logic;
      cfgTimeoutLimit   : in  std_logic_vector(11 downto 0);
      cfgPauseLimit     : in  std_logic_vector(11 downto 0);
      cfgColumnEnable   : in  std_logic_vector(23 downto 0);
      cfgColBusy        : out std_logic;
      cfgColDataEmpty   : out std_logic;
      cfgColStatusEmpty : out std_logic;
      cfgSuperBusy      : out std_logic;
      cfgArbBusy        : out std_logic;
      -- Column Manager Interface
      -- dataIn
      din0              : in  std_logic_vector(31 downto 0);
      din1              : in  std_logic_vector(31 downto 0);
      din2              : in  std_logic_vector(31 downto 0);
      din3              : in  std_logic_vector(31 downto 0);
      din4              : in  std_logic_vector(31 downto 0);
      din5              : in  std_logic_vector(31 downto 0);
      din6              : in  std_logic_vector(31 downto 0);
      din7              : in  std_logic_vector(31 downto 0);
      din8              : in  std_logic_vector(31 downto 0);
      din9              : in  std_logic_vector(31 downto 0);
      din10             : in  std_logic_vector(31 downto 0);
      din11             : in  std_logic_vector(31 downto 0);
      din12             : in  std_logic_vector(31 downto 0);
      din13             : in  std_logic_vector(31 downto 0);
      din14             : in  std_logic_vector(31 downto 0);
      din15             : in  std_logic_vector(31 downto 0);
      din16             : in  std_logic_vector(31 downto 0);
      din17             : in  std_logic_vector(31 downto 0);
      din18             : in  std_logic_vector(31 downto 0);
      din19             : in  std_logic_vector(31 downto 0);
      din20             : in  std_logic_vector(31 downto 0);
      din21             : in  std_logic_vector(31 downto 0);
      din22             : in  std_logic_vector(31 downto 0);
      din23             : in  std_logic_vector(31 downto 0);
      -- flags
      sof               : in  std_logic_vector(23 downto 0);
      eof               : in  std_logic_vector(23 downto 0);
      overOcc           : in  std_logic_vector(23 downto 0);
      pauseAck          : in  std_logic_vector(23 downto 0);
      wrEn              : in  std_logic_vector(23 downto 0);
      busy              : out std_logic_vector(23 downto 0);
      pause             : out std_logic_vector(23 downto 0);
      -- Serializer Interface
      pgpDout           : out std_logic_vector(31 downto 0);
      pgpDoutValid      : out std_logic;
      pgpDoutReady      : in  std_logic);
end entity Pix2PgpSparkPixTTop;

architecture rtl of Pix2PgpSparkPixTTop is

   signal din                : Pix2PgpSparseDinArray;
   signal readback           : Pix2PgpCfgReadbackType;
   signal config             : Pix2PgpCfgConfigType;
   signal sparseColumnEnable : std_logic_vector(23 downto 0);

   signal pgpTxMaster        : AxiStreamMasterType;
   signal pgpTxSlave         : AxiStreamSlaveType;

   signal phyTxValid         : std_logic;
   signal phyTxReady         : std_logic;
   signal phyTxData          : std_logic_vector(65 downto 0);

   signal serGboxReady       : std_logic;
   signal serGboxValid       : std_logic;
   signal serGboxData        : std_logic_vector(31 downto 0);

   signal glblSparseRst      : std_logic;
   signal glblPgpRst         : std_logic;

begin

   -- check that we have sourced the correct Pkg file
   assert (NUM_OF_COL_MANAGERS_C = 24)
      report "[ERROR]: Pix2PgpSparkPixTTop; NUM_OF_COL_MANAGERS_C is *NOT* equal to 24! Please check that Pix2PgpPkg.vhd matches Pix2PgpSparkPixSPkg.vhd" severity failure;

   assert (SPARSE_DWIDTH_C = 32)
      report "[ERROR]: Pix2PgpSparkPixTTop; SPARSE_DWIDTH_C is *NOT* equal to 32! Please check that Pix2PgpPkg.vhd matches Pix2PgpSparkPixSPkg.vhd" severity failure;

   -- check the length equivalence with asserts
   -- avoid tying input port widths to generics; hardcode them instead
   -- ...ASIC flow tools can be annoying...
   assert (cfgTimeoutLimit'length = TIMEOUT_LIMIT_WIDTH_C)
      report "[ERROR]: Pix2PgpSparkPixTTop; Please match cfgTimeoutLimit port width with TIMEOUT_LIMIT_WIDTH_C generic" severity failure;

   assert (cfgColumnEnable'length = NUM_OF_COL_MANAGERS_C)
      report "[ERROR]: Pix2PgpSparkPixTTop; Please match cfgColumnEnable port width with NUM_OF_COL_MANAGERS_C generic" severity failure;

   assert (sof'length = NUM_OF_COL_MANAGERS_C)
      report "[ERROR]: Pix2PgpSparkPixTTop; Please match sof port width with NUM_OF_COL_MANAGERS_C generic" severity failure;

   assert (eof'length = NUM_OF_COL_MANAGERS_C)
      report "[ERROR]: Pix2PgpSparkPixTTop; Please match eof port width with NUM_OF_COL_MANAGERS_C generic" severity failure;

   assert (overOcc'length = NUM_OF_COL_MANAGERS_C)
      report "[ERROR]: Pix2PgpSparkPixTTop; Please match overOcc port width with NUM_OF_COL_MANAGERS_C generic" severity failure;

   assert (pauseAck'length = NUM_OF_COL_MANAGERS_C)
      report "[ERROR]: Pix2PgpSparkPixTTop; Please match pauseAck port width with NUM_OF_COL_MANAGERS_C generic" severity failure;

   assert (wrEn'length = NUM_OF_COL_MANAGERS_C)
      report "[ERROR]: Pix2PgpSparkPixTTop; Please match wrEn port width with NUM_OF_COL_MANAGERS_C generic" severity failure;

   assert (busy'length = NUM_OF_COL_MANAGERS_C)
      report "[ERROR]: Pix2PgpSparkPixTTop; Please match busy port width with NUM_OF_COL_MANAGERS_C generic" severity failure;

   assert (pause'length = NUM_OF_COL_MANAGERS_C)
      report "[ERROR]: Pix2PgpSparkPixTTop; Please match pause port width with NUM_OF_COL_MANAGERS_C generic" severity failure;

   --------------------------------------------------------------------------

   -- Top Level
   U_Pix2PgpTop : entity pix2pgp.Pix2PgpTop
      generic map (
         TPD_G                     => TPD_G,
         RST_ASYNC_G               => RST_ASYNC_G,
         RST_POLARITY_G            => RST_POLARITY_G,
         COLMANAGER_DATA_DEPTH_G   => COLMANAGER_DATA_DEPTH_G,
         COLMANAGER_STATUS_DEPTH_G => COLMANAGER_STATUS_DEPTH_G,
         PIPELINE_DATA_G           => PIPELINE_DATA_G,
         PIPELINE_STATUS_G         => PIPELINE_STATUS_G,
         DATAFIFO_PIPE_G           => DATAFIFO_PIPE_G,
         STATUSFIFO_PIPE_G         => STATUSFIFO_PIPE_G)
      port map (
         -- General Interface
         sparseClk    => sparseClk,
         pgpClk       => pgpClk,
         sparseRst    => glblSparseRst,
         pgpRst       => glblPgpRst,
         config       => config,
         readback     => readback,
         -- Column Manager Interface
         sof          => sof,
         eof          => eof,
         overOcc      => overOcc,
         pauseAck     => pauseAck,
         wrEn         => wrEn,
         din          => din,
         busy         => busy,
         pause        => pause,
         -- Pgp4TxLite Interface
         pgpTxMaster  => pgpTxMaster,
         pgpTxSlave   => pgpTxSlave);

   -- Instantiate the PGP4TxLiteWrapper
   U_Pgp4TxLiteWrapper : entity pix2pgp.Pix2Pgp4TxLiteWrapper
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G)
      port map(
        -- Clock and Reset
        clk         => pgpClk,
        rst         => pgpRst,
        -- 64-bit Input Framing Interface
        pgpTxMaster => pgpTxMaster,
        pgpTxSlave  => pgpTxSlave,
        -- 66-bit Output Interface
        phyTxValid  => phyTxValid,
        phyTxReady  => phyTxReady,
        phyTxData   => phyTxData);

   U_SerializerGearbox : entity surf.Gearbox
      generic map (
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         RST_POLARITY_G => RST_POLARITY_G,
         SLAVE_WIDTH_G  => 66,
         MASTER_WIDTH_G => SER_DWIDTH_C)
      port map (
         -- Clock and Reset
         clk            => pgpClk,
         rst            => pgpRst,
         -- Slave Interface
         slaveValid     => phyTxValid,
         slaveReady     => phyTxReady,
         slaveData      => phyTxData,
         slaveBitOrder  => '0',
         -- Master Interface
         masterBitOrder => '0',
         masterReady    => serGboxReady,
         masterValid    => serGboxValid,
         masterData     => serGboxData);

   -- pipeline the gearbox interface with the serializer
   U_PipelineGboxValid : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => SER_GBOX_PIPE_G)
      port map (
         clk     => pgpClk,
         din(0)  => serGboxValid,
         dout(0) => pgpDoutValid);

   U_PipelineGboxReady : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => SER_GBOX_PIPE_G)
      port map (
         clk     => pgpClk,
         din(0)  => pgpDoutReady,
         dout(0) => serGboxReady);

   U_PipelineGboxDout : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => SER_DWIDTH_C,
         DELAY_G        => SER_GBOX_PIPE_G)
      port map (
         clk  => pgpClk,
         din  => serGboxData,
         dout => pgpDout);

      -- dumb; but should always work with a .v/.sv wrapper above this level
      din(0)  <= din0;
      din(1)  <= din1;
      din(2)  <= din2;
      din(3)  <= din3;
      din(4)  <= din4;
      din(5)  <= din5;
      din(6)  <= din6;
      din(7)  <= din7;
      din(8)  <= din8;
      din(9)  <= din9;
      din(10) <= din10;
      din(11) <= din11;
      din(12) <= din12;
      din(13) <= din13;
      din(14) <= din14;
      din(15) <= din15;
      din(16) <= din16;
      din(17) <= din17;
      din(18) <= din18;
      din(19) <= din19;
      din(20) <= din20;
      din(21) <= din21;
      din(22) <= din22;
      din(23) <= din23;

   -- Configurable Registers Management
   process(pgpRst, pgpClk)
   begin
      if (RST_ASYNC_G and pgpRst = RST_POLARITY_G) then
         config.columnEnable <= (others => '0');
      elsif (rising_edge(pgpClk)) then
         if pgpRst = RST_POLARITY_G then
            config.columnEnable <= (others => '0');
         elsif cfgSel = '1' then
            config.columnEnable <= cfgColumnEnable;
         end if;
      end if;
   end process;

   process(sparseRst, sparseClk)
   begin
      if (RST_ASYNC_G and sparseRst = RST_POLARITY_G) then
         config.timeoutLimit <= (others => '0');
         sparseColumnEnable  <= (others => '0');
         config.pauseLimit   <= (others => '0');
      elsif (rising_edge(sparseClk)) then
         if sparseRst = RST_POLARITY_G then
            config.timeoutLimit <= (others => '0');
            sparseColumnEnable  <= (others => '0');
            config.pauseLimit   <= (others => '0');
         elsif cfgSel = '1' then
            config.timeoutLimit <= cfgTimeoutLimit;
            sparseColumnEnable  <= cfgColumnEnable;
            config.pauseLimit   <= cfgPauseLimit;
         end if;
      end if;
   end process;

   -- Reset Management
   process(sparseRst, sparseClk)
   begin
      if (RST_ASYNC_G and sparseRst = RST_POLARITY_G) then
         glblSparseRst <= sparseRst;
      elsif (rising_edge(sparseClk)) then

         if RST_POLARITY_G = '1' then
            glblSparseRst <= sparseRst or uAnd(not(sparseColumnEnable));
         else
            glblSparseRst <= sparseRst and uOr(sparseColumnEnable);
         end if;

      end if;
   end process;

   process(pgpRst, pgpClk, config)

      variable columnEnable : std_logic_vector(23 downto 0);
   begin
      columnEnable := config.columnEnable;

      if (RST_ASYNC_G and pgpRst = RST_POLARITY_G) then
         glblPgpRst <= pgpRst;
      elsif (rising_edge(pgpClk)) then

         if RST_POLARITY_G = '1' then
            glblPgpRst <= pgpRst or uAnd(not(columnEnable));
         else
            glblPgpRst <= pgpRst and uOr(columnEnable);
         end if;

      end if;
   end process;

   -- feedback signals
   U_SyncColBusy : entity surf.Synchronizer
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G)
      port map (
         clk     => pgpClk,
         dataIn  => readback.cfgColBusy,
         dataOut => cfgColBusy);

   U_SyncColDataEmpty : entity surf.Synchronizer
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G)
      port map (
         clk     => pgpClk,
         dataIn  => readback.cfgColDataEmpty,
         dataOut => cfgColDataEmpty);

   U_SyncColStatusEmpty : entity surf.Synchronizer
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G)
      port map (
         clk     => pgpClk,
         dataIn  => readback.cfgColStatusEmpty,
         dataOut => cfgColStatusEmpty);

      cfgSuperBusy <= readback.cfgSuperBusy;
      cfgArbBusy   <= readback.cfgArbBusy;

end architecture;
