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

entity Pix2PgpSparkPixTTopTb is
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

end entity Pix2PgpSparkPixTTopTb;

-- * about the AF_LVL_G flags:
-- the surf-based fifos issue their almost-full/prog-full when wr_index = AF_LVL_G;
-- the synopsys fifos raise their flag when wr_index = DEPTH_G-AF_LVL_G;
-- i.e. for the synopsys fifos, the AF_LVL_G denotes the amount of empty memory spaces before
-- the almost-full flag is asserted

architecture test of Pix2PgpSparkPixTTopTb is

   constant CLK_PERIOD_SPARSE_C : time := 10.768 ns;
   constant CLK_PERIOD_PGP_C    : time := 5.3846 ns;

   signal sparseClk : sl := '0';
   signal pgpClk    : sl := '0';
   signal rst       : sl := '0';
   signal sro       : sl := '0';
   signal sroFinal  : sl := '0';
   signal trg       : sl := '0';
   signal trgFinal  : sl := '0';

   signal tokFb     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '1');
   signal sof       : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '1');
   signal eof       : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal overOcc   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal busy      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal ackN      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '1');
   signal wrEn      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal pause     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal pauseAck  : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal sparseBusy: slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal din       : Pix2PgpSparseDinArray := (others => (others => '0'));

   type hitLenArray is array (0 to NUM_OF_COL_MANAGERS_C-1) of slv(15 downto 0);
   signal hitLen  : hitLenArray := (others => (others => '0'));

   signal pgpDataAsic      : slv(31 downto 0) := (others => '0');
   signal pgpDataAsicValid : sl;
   signal pgpDataAsicReady : sl;

   signal pgpValid  : sl := '0';
   signal pgpData   : slv(63 downto 0) := (others => '0');

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

    writeDataProcess: process(pgpClk)

    -- variables for file-writing
    file myFile  : text open write_mode is "pix2pgpRxDataDump.dat";
    variable row : line;

  begin
    if (rising_edge(pgpClk)) then
        -- check if the valid flag is high
        if pgpValid = '1' then
          -- syntax: write(row_variable,what_to_write,
          -- justification(right/left), trailing_whitespaces);
          -- writeline(file_variable, row_variable);
          hwrite(row, pgpData, right, 0);
          writeline(myFile,row);
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

  issueTrgProcess: process(sparseClk)
  begin
    if (rising_edge(sparseClk)) then
      if trg = '1' and trgFinal = '0' then
        trgFinal <= trg;
      else
        trgFinal <= '0';
      end if;
    end if;
  end process;

   --------
   -- Pixel
   --------
   GEN_DUMMY_PIXEL: for col in 0 to NUM_OF_COL_MANAGERS_C-1 generate
      U_DummyPixel : entity pix2pgp.DummySparkPixTPixel
         generic map(
           TPD_G           => TPD_G,
           RST_ASYNC_G     => RST_ASYNC_G,
           RST_POLARITY_G  => RST_POLARITY_G,
           WAIT_WREN_G     => 3,
           COL_ID_G        => col)
         port map(
           clk        => sparseClk,
           df_reset_n => rst,
           sro        => sroFinal,
           trigger    => trgFinal,
           hitLen     => hitLen(col),
           pause      => pause(col),
           pauseAck   => pauseAck(col),
           sof        => sof(col),
           eof        => eof(col),
           overOcc    => overOcc(col),
           wrEn       => wrEn(col),
           dout       => din(col));
   end generate GEN_DUMMY_PIXEL;

   ------
   -- UUT
   ------
   U_Uut : entity pix2pgp.Pix2PgpSparkPixTTop
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
         pause        => pause,
         sof          => sof,
         eof          => eof,
         busy         => busy,
         overOcc      => overOcc,
         pauseAck     => pauseAck,
         wrEn         => wrEn,
         din0         => din(0),
         din1         => din(1),
         din2         => din(2),
         din3         => din(3),
         din4         => din(4),
         din5         => din(5),
         din6         => din(6),
         din7         => din(7),
         din8         => din(8),
         din9         => din(9),
         din10        => din(10),
         din11        => din(11),
         din12        => din(12),
         din13        => din(13),
         din14        => din(14),
         din15        => din(15),
         din16        => din(16),
         din17        => din(17),
         din18        => din(18),
         din19        => din(19),
         din20        => din(20),
         din21        => din(21),
         din22        => din(22),
         din23        => din(23),
         pgpDout      => pgpDataAsic,
         pgpDoutValid => pgpDataAsicValid,
         pgpDoutReady => pgpDataAsicReady);

   -------
   -- FPGA
   -------
   U_FPGA : entity pix2pgp.Pix2PgpFpgaTb
    generic map(
       TPD_G          => TPD_G,
       RST_ASYNC_G    => RST_ASYNC_G,
       RST_POLARITY_G => RST_POLARITY_G,
       FPGA_SYNTH_G   => FPGA_SYNTH_G,
       NUM_VC_G       => NUM_VC_G)
    port map(
       -- General Interface
       clk         => pgpClk,
       rst         => rst,
       -- Pix2Pgp Interface
       pgpDin      => pgpDataAsic,
       pgpDinValid => pgpDataAsicValid, -- has to be connected; otherwise pgp does not align
       pgpDinReady => pgpDataAsicReady, -- does not have to be connected
       -- FPGA RX Interface
       pgpValid    => pgpValid,
       pgpData     => pgpData);

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
         hitLen(col) <= toSlv(4, hitLen(col)'length);
       end loop;
         trg <= '1';
         sro <= '1';
     wait for CLK_PERIOD_SPARSE_C*2;
         trg  <= '0';
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
    --  trg <= '1';
    --  sro  <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  trg <= '0';
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
    --  trg <= '1';
    --  sro  <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  trg <= '0';
    --  sro  <= '0';

    -- wait for CLK_PERIOD_SPARSE_C*93;
    --   for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
    --     hitLen(col) <= toSlv(3, hitLen(col)'length);
    --   end loop;
    --     trg <= '1';
    --     sro <= '1';
    -- wait for CLK_PERIOD_SPARSE_C*2;
    --     trg <= '0';
    --     sro  <= '0';

    -- wait for CLK_PERIOD_SPARSE_C*93;
    --   for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
    --     hitLen(col) <= toSlv(1, hitLen(col)'length);
    --   end loop;
    --     trg <= '1';
    --     sro <= '1';
    -- wait for CLK_PERIOD_SPARSE_C*2;
    --     trg <= '0';
    --     sro  <= '0';

    -- wait for CLK_PERIOD_SPARSE_C*93;
    --   for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
    --   hitLen(col) <= toSlv(2, hitLen(col)'length);
    -- end loop;
    --   trg <= '1';
    --   sro <= '1';
    -- wait for CLK_PERIOD_SPARSE_C*2;
    --   trg <= '0';
    --   sro  <= '0';

    -- wait for CLK_PERIOD_SPARSE_C*93;
    --   for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
    --   hitLen(col) <= toSlv(0, hitLen(col)'length);
    -- end loop;
    --   trg <= '1';
    --   sro <= '1';
    -- wait for CLK_PERIOD_SPARSE_C*2;
    --   trg <= '0';
    --   sro  <= '0';
    ----------------------------------------------
    ----------------------------------------------
    -- regular stimuli end

    -- do not touch begin
     wait for CLK_PERIOD_SPARSE_C*93;
         trg <= '1';
     wait for CLK_PERIOD_SPARSE_C*2;
         trg  <= '0';
    wait;
    -- do not touch end

  end process stimulus;

end architecture;
