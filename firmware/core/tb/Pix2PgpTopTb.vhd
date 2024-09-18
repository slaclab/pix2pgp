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
      TPD_G                      : time     := 1 ns;
      RST_ASYNC_G                : boolean  := True;
      RST_POLARITY_G             : sl       := '1';
      FPGA_SYNTH_G               : boolean  := False;
      DATAFIFO_PIPE_G            : positive := 2;
      STATUSFIFO_PIPE_G          : positive := 2;
      PIPELINE_BRIDGE_DATA_G     : boolean  := False;
      PIPELINE_BRIDGE_STATUS_G   : boolean  := True;
      COLMANAGER_DATA_DEPTH_G    : integer  := 6;
      COLMANAGER_DATA_AF_LVL_G   : integer  := 5; -- *
      COLMANAGER_STATUS_DEPTH_G  : integer  := 4;
      COLMANAGER_STATUS_AF_LVL_G : integer  := 5; -- *
      ADAPTER_DEPTH_G            : integer  := 6;
      ADAPTER_AF_LVL_G           : integer  := 5; -- *
      SUPER_FIFO_RD_DELAY_G      : natural  := 3;
      ARB_DOUT_PIPE_G            : natural  := 2;
      NUM_VC_G                   : natural  := 1
   );
   port (
    dummyIn : in sl
  );

end entity Pix2PgpTopTb;

-- * about the AF_LVL_G flags:
-- the surf-based fifos issue their almost-full/prog-full when wr_index = AF_LVL_G;
-- the synopsys fifos raise their flag when wr_index = DEPTH_G-AF_LVL_G;
-- i.e. for the synopsys fifos, the AF_LVL_G denotes the amount of empty memory spaces before
-- the almost-full flag is asserted

architecture test of Pix2PgpTopTb is

   constant CLK_PERIOD_SPARSE_C : time := 10.768 ns;
   constant CLK_PERIOD_PGP_C    : time := 5.384  ns;

   signal sparseClk : sl := '0';
   signal pgpClk    : sl := '0';
   signal rst       : sl := '1';
   signal sro       : sl := '0';
   signal sroFinal  : sl := '0';

   signal sof       : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '1');
   signal eof       : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal overOcc   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal busy      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal ackN      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '1');
   signal wrEn      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal pause     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal din       : Pix2PgpSparseDinArray := (others => (others => '0'));

   type hitLenArray is array (0 to NUM_OF_COL_MANAGERS_C-1) of slv(9 downto 0);
   signal hitLen  : hitLenArray := (others => (others => '0'));

   signal pgpDout      : slv(31 downto 0) := (others => '0');
   signal pgpDoutValid : sl;
   signal pgpDoutReady : sl;

   signal pgpValid  : sl := '0';
   signal pgpData   : slv(39 downto 0) := (others => '0');

begin

  -- rst and clk
  sparseClk <= not sparseClk after CLK_PERIOD_SPARSE_C - TPD_G;
  pgpClk    <= not pgpClk    after CLK_PERIOD_PGP_C    - TPD_G;
  rst <= '1', '0' after CLK_PERIOD_SPARSE_C*100;

  -- Generate the test stimulus
  stimulus: process begin

    -- do not touch begin
    ----------------------------------------------
    ----------------------------------------------
    -- Wait for the rst to be released before
    wait until (rst = '0');
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

    -- regular stimuli
    ----------------------------------------------
    ----------------------------------------------
    wait for CLK_PERIOD_SPARSE_C*93;
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop

        hitLen(col) <= toSlv(4, hitLen(col)'length);
      end loop;
        sro <= '1';
    wait for CLK_PERIOD_SPARSE_C*2;
        sro  <= '0';

    wait for CLK_PERIOD_SPARSE_C*93;
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop

        hitLen(col) <= toSlv(3, hitLen(col)'length);
      end loop;
        sro <= '1';
    wait for CLK_PERIOD_SPARSE_C*2;
        sro  <= '0';

    wait for CLK_PERIOD_SPARSE_C*93;
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop

        hitLen(col) <= toSlv(1, hitLen(col)'length);
      end loop;
        sro <= '1';
    wait for CLK_PERIOD_SPARSE_C*2;
        sro  <= '0';

    wait for CLK_PERIOD_SPARSE_C*93;
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
      hitLen(col) <= toSlv(2, hitLen(col)'length);
    end loop;
      sro <= '1';
    wait for CLK_PERIOD_SPARSE_C*2;
      sro  <= '0';

    wait for CLK_PERIOD_SPARSE_C*93;
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
      hitLen(col) <= toSlv(0, hitLen(col)'length);
    end loop;
      sro <= '1';
    wait for CLK_PERIOD_SPARSE_C*2;
      sro  <= '0';
    ----------------------------------------------
    ----------------------------------------------

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  for col in 12 to NUM_OF_COL_MANAGERS_C-1 loop
    --
    --    hitLen(col) <= toSlv(3, hitLen(col)'length);
    --  end loop;
    --    sro <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --    sro  <= '0';

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  for col in 14 to NUM_OF_COL_MANAGERS_C-1 loop
    --
    --    hitLen(col) <= toSlv(4, hitLen(col)'length);
    --  end loop;
    --    sro <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --    sro  <= '0';

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  sro  <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  for col in 0 to 4 loop
    --
    --    hitLen(col) <= toSlv(0, hitLen(col)'length);
    --  end loop;
    --  hitLen(5) <= toSlv(3, hitLen(5)'length);
    --  hitLen(6) <= toSlv(1, hitLen(6)'length);
    --  hitLen(7) <= toSlv(2, hitLen(7)'length);
    --  hitLen(8) <= toSlv(3, hitLen(8)'length);
    --  hitLen(9) <= toSlv(4, hitLen(9)'length);
    --  sro  <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  hitLen(5) <= toSlv(8, hitLen(5)'length);
    --  hitLen(6) <= toSlv(6, hitLen(6)'length);
    --  hitLen(7) <= toSlv(3, hitLen(7)'length);
    --  hitLen(8) <= toSlv(5, hitLen(8)'length);
    --  hitLen(9) <= toSlv(1, hitLen(9)'length);
    --  sro  <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
    --     hitLen(col) <= toSlv(34, hitLen(col)'length);
    --  end loop;
    --  sro  <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  sro  <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  hitLen(0)  <= toSlv(0,  hitLen(5)'length);
    --  hitLen(1)  <= toSlv(2,  hitLen(5)'length);
    --  hitLen(2)  <= toSlv(0,  hitLen(5)'length);
    --  hitLen(3)  <= toSlv(0,  hitLen(5)'length);
    --  hitLen(4)  <= toSlv(4,  hitLen(5)'length);
    --  hitLen(5)  <= toSlv(0,  hitLen(5)'length);
    --  hitLen(6)  <= toSlv(0,  hitLen(6)'length);
    --  hitLen(7)  <= toSlv(1,  hitLen(7)'length);
    --  hitLen(8)  <= toSlv(0,  hitLen(8)'length);
    --  hitLen(9)  <= toSlv(0,  hitLen(9)'length);
    --  hitLen(10) <= toSlv(4,  hitLen(5)'length);
    --  hitLen(11) <= toSlv(2,  hitLen(5)'length);
    --  hitLen(12) <= toSlv(0,  hitLen(5)'length);
    --  hitLen(13) <= toSlv(3,  hitLen(5)'length);
    --  hitLen(14) <= toSlv(0,  hitLen(5)'length);
    --  hitLen(15) <= toSlv(2,  hitLen(5)'length);
    --  hitLen(16) <= toSlv(0,  hitLen(6)'length);
    --  hitLen(17) <= toSlv(0,  hitLen(7)'length);
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
    --  hitLen(0)  <= toSlv(0,  hitLen(5)'length);
    --  hitLen(1)  <= toSlv(4,  hitLen(5)'length);
    --  hitLen(2)  <= toSlv(3,  hitLen(5)'length);
    --  hitLen(3)  <= toSlv(0,  hitLen(5)'length);
    --  hitLen(4)  <= toSlv(1,  hitLen(5)'length);
    --  hitLen(5)  <= toSlv(2,  hitLen(5)'length);
    --  hitLen(6)  <= toSlv(0,  hitLen(6)'length);
    --  hitLen(7)  <= toSlv(1,  hitLen(7)'length);
    --  hitLen(8)  <= toSlv(0,  hitLen(8)'length);
    --  hitLen(9)  <= toSlv(0,  hitLen(9)'length);
    --  hitLen(10) <= toSlv(4,  hitLen(5)'length);
    --  hitLen(11) <= toSlv(2,  hitLen(5)'length);
    --  hitLen(12) <= toSlv(0,  hitLen(5)'length);
    --  hitLen(13) <= toSlv(2,  hitLen(5)'length);
    --  hitLen(14) <= toSlv(0,  hitLen(5)'length);
    --  hitLen(15) <= toSlv(3,  hitLen(5)'length);
    --  hitLen(16) <= toSlv(0,  hitLen(6)'length);
    --  hitLen(17) <= toSlv(2,  hitLen(7)'length);
    --  hitLen(18) <= toSlv(1,  hitLen(8)'length);
    --  hitLen(19) <= toSlv(2,  hitLen(9)'length);
    --  hitLen(20) <= toSlv(4,  hitLen(5)'length);
    --  hitLen(21) <= toSlv(2,  hitLen(5)'length);
    --  hitLen(22) <= toSlv(1,  hitLen(5)'length);
    --  hitLen(23) <= toSlv(2,  hitLen(5)'length);
    --  sro  <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_SPARSE_C*93*4; -- x4 otherwise OverOcc
    --for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
    --
    --  hitLen(col) <= toSlv(0, hitLen(col)'length);
    --end loop;

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  hitLen(0)  <= toSlv(3, hitLen(5)'length);
    --  hitLen(2)  <= toSlv(1, hitLen(6)'length);
    --  hitLen(7)  <= toSlv(2, hitLen(7)'length);
    --  hitLen(12) <= toSlv(3, hitLen(8)'length);
    --  hitLen(20) <= toSlv(4, hitLen(9)'length);
    --  sro <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
    --    hitLen(col) <= toSlv(0, hitLen(col)'length);
    --  end loop;
    --  sro  <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

    -- overocc test
    --wait for CLK_PERIOD_SPARSE_C*93;
    --  hitLen(0)  <= toSlv(3, hitLen(5)'length);
    --  hitLen(2)  <= toSlv(1, hitLen(6)'length);
    --  hitLen(4)  <= toSlv(2, hitLen(7)'length);
    --  hitLen(7)  <= toSlv(25, hitLen(8)'length);
    --  hitLen(20) <= toSlv(3, hitLen(9)'length);
    --  sro <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  hitLen(0)  <= toSlv(2, hitLen(5)'length);
    --  hitLen(2)  <= toSlv(4, hitLen(6)'length);
    --  hitLen(7)  <= toSlv(2, hitLen(7)'length);
    --  hitLen(12) <= toSlv(2, hitLen(8)'length);
    --  hitLen(20) <= toSlv(3, hitLen(9)'length);
    --  sro <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  hitLen(0)  <= toSlv(3, hitLen(5)'length);
    --  hitLen(2)  <= toSlv(1, hitLen(6)'length);
    --  hitLen(7)  <= toSlv(2, hitLen(7)'length);
    --  hitLen(12) <= toSlv(2, hitLen(8)'length);
    --  hitLen(20) <= toSlv(4, hitLen(9)'length);
    --  sro <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
    --     hitLen(col) <= toSlv(0, hitLen(col)'length);
    --  end loop;
    --  sro  <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
    --  hitLen(col) <= toSlv(0, hitLen(col)'length);
    --end loop;
    --  sro <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
    --  hitLen(col) <= toSlv(1, hitLen(col)'length);
    --end loop;
    --  sro <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_SPARSE_C*93;
    --  for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
    --  hitLen(col) <= toSlv(1, hitLen(col)'length);
    --end loop;
    --  sro <= '1';
    --wait for CLK_PERIOD_SPARSE_C*2;
    --  sro  <= '0';

  -- verification-generated
  ----------------------------------------
  --------------- hit = 0 ---------------
  ----------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(5, hitLen(0)'length);
  --  hitLen(4) <= toSlv(7, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(5, hitLen(0)'length);
  --  hitLen(8) <= toSlv(6, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(6, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(0, hitLen(0)'length);
  --  hitLen(17) <= toSlv(7, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(5, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(5, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 1 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(2, hitLen(0)'length);
  --  hitLen(3) <= toSlv(5, hitLen(0)'length);
  --  hitLen(4) <= toSlv(7, hitLen(0)'length);
  --  hitLen(5) <= toSlv(5, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(6, hitLen(0)'length);
  --  hitLen(8) <= toSlv(5, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(6, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(0, hitLen(0)'length);
  --  hitLen(15) <= toSlv(0, hitLen(0)'length);
  --  hitLen(16) <= toSlv(0, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(4, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(2, hitLen(0)'length);
  --  hitLen(23) <= toSlv(2, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 2 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(5, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(5, hitLen(0)'length);
  --  hitLen(7) <= toSlv(7, hitLen(0)'length);
  --  hitLen(8) <= toSlv(1, hitLen(0)'length);
  --  hitLen(9) <= toSlv(0, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(6, hitLen(0)'length);
  --  hitLen(12) <= toSlv(5, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(5, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(5, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(4, hitLen(0)'length);
  --  hitLen(21) <= toSlv(1, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(6, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 3 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(7, hitLen(0)'length);
  --  hitLen(1) <= toSlv(6, hitLen(0)'length);
  --  hitLen(2) <= toSlv(2, hitLen(0)'length);
  --  hitLen(3) <= toSlv(1, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(5, hitLen(0)'length);
  --  hitLen(6) <= toSlv(6, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(1, hitLen(0)'length);
  --  hitLen(9) <= toSlv(6, hitLen(0)'length);
  --  hitLen(10) <= toSlv(1, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(6, hitLen(0)'length);
  --  hitLen(17) <= toSlv(1, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(4, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(5, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 4 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(5, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(1, hitLen(0)'length);
  --  hitLen(3) <= toSlv(1, hitLen(0)'length);
  --  hitLen(4) <= toSlv(7, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(1, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(6, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(5, hitLen(0)'length);
  --  hitLen(18) <= toSlv(5, hitLen(0)'length);
  --  hitLen(19) <= toSlv(4, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(7, hitLen(0)'length);
  --  hitLen(22) <= toSlv(2, hitLen(0)'length);
  --  hitLen(23) <= toSlv(6, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 5 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(5, hitLen(0)'length);
  --  hitLen(4) <= toSlv(1, hitLen(0)'length);
  --  hitLen(5) <= toSlv(6, hitLen(0)'length);
  --  hitLen(6) <= toSlv(1, hitLen(0)'length);
  --  hitLen(7) <= toSlv(9, hitLen(0)'length);
  --  hitLen(8) <= toSlv(6, hitLen(0)'length);
  --  hitLen(9) <= toSlv(5, hitLen(0)'length);
  --  hitLen(10) <= toSlv(1, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(0, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(0, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(2, hitLen(0)'length);
  --  hitLen(18) <= toSlv(4, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(7, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 6 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(7, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(5, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(5, hitLen(0)'length);
  --  hitLen(9) <= toSlv(1, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(1, hitLen(0)'length);
  --  hitLen(12) <= toSlv(1, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(1, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(6, hitLen(0)'length);
  --  hitLen(23) <= toSlv(5, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 7 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(6, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(5, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(6, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(0, hitLen(0)'length);
  --  hitLen(8) <= toSlv(1, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(6, hitLen(0)'length);
  --  hitLen(11) <= toSlv(4, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(1, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 8 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(6, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(5, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(1, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(7, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(1, hitLen(0)'length);
  --  hitLen(17) <= toSlv(6, hitLen(0)'length);
  --  hitLen(18) <= toSlv(4, hitLen(0)'length);
  --  hitLen(19) <= toSlv(9, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(6, hitLen(0)'length);
  --  hitLen(22) <= toSlv(2, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 9 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(2, hitLen(0)'length);
  --  hitLen(3) <= toSlv(4, hitLen(0)'length);
  --  hitLen(4) <= toSlv(0, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(4, hitLen(0)'length);
  --  hitLen(19) <= toSlv(5, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(7, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 10 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(7, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(2, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(7, hitLen(0)'length);
  --  hitLen(6) <= toSlv(6, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(3, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(4, hitLen(0)'length);
  --  hitLen(12) <= toSlv(3, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(1, hitLen(0)'length);
  --  hitLen(15) <= toSlv(0, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(5, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(4, hitLen(0)'length);
  --  hitLen(20) <= toSlv(5, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(5, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 11 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(1, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(1, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(1, hitLen(0)'length);
  --  hitLen(12) <= toSlv(6, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(5, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(4, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(1, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(4, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 12 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(5, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(1, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(5, hitLen(0)'length);
  --  hitLen(6) <= toSlv(0, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(5, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(1, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(6, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(6, hitLen(0)'length);
  --  hitLen(21) <= toSlv(1, hitLen(0)'length);
  --  hitLen(22) <= toSlv(0, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 13 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(0, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(6, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(7, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(4, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(4, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(7, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 14 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(2, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(1, hitLen(0)'length);
  --  hitLen(6) <= toSlv(4, hitLen(0)'length);
  --  hitLen(7) <= toSlv(1, hitLen(0)'length);
  --  hitLen(8) <= toSlv(1, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(7, hitLen(0)'length);
  --  hitLen(12) <= toSlv(3, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(1, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(6, hitLen(0)'length);
  --  hitLen(17) <= toSlv(8, hitLen(0)'length);
  --  hitLen(18) <= toSlv(1, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(2, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 15 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(8, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(0, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(5, hitLen(0)'length);
  --  hitLen(7) <= toSlv(7, hitLen(0)'length);
  --  hitLen(8) <= toSlv(0, hitLen(0)'length);
  --  hitLen(9) <= toSlv(1, hitLen(0)'length);
  --  hitLen(10) <= toSlv(1, hitLen(0)'length);
  --  hitLen(11) <= toSlv(4, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(5, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(5, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 16 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(6, hitLen(0)'length);
  --  hitLen(3) <= toSlv(5, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(5, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(6, hitLen(0)'length);
  --  hitLen(9) <= toSlv(4, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(0, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(0, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(6, hitLen(0)'length);
  --  hitLen(19) <= toSlv(1, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(6, hitLen(0)'length);
  --  hitLen(22) <= toSlv(5, hitLen(0)'length);
  --  hitLen(23) <= toSlv(0, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 17 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(4, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(5, hitLen(0)'length);
  --  hitLen(7) <= toSlv(6, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(1, hitLen(0)'length);
  --  hitLen(10) <= toSlv(1, hitLen(0)'length);
  --  hitLen(11) <= toSlv(5, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(1, hitLen(0)'length);
  --  hitLen(15) <= toSlv(5, hitLen(0)'length);
  --  hitLen(16) <= toSlv(6, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(4, hitLen(0)'length);
  --  hitLen(19) <= toSlv(5, hitLen(0)'length);
  --  hitLen(20) <= toSlv(5, hitLen(0)'length);
  --  hitLen(21) <= toSlv(4, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(4, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 18 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(5, hitLen(0)'length);
  --  hitLen(1) <= toSlv(5, hitLen(0)'length);
  --  hitLen(2) <= toSlv(1, hitLen(0)'length);
  --  hitLen(3) <= toSlv(6, hitLen(0)'length);
  --  hitLen(4) <= toSlv(6, hitLen(0)'length);
  --  hitLen(5) <= toSlv(1, hitLen(0)'length);
  --  hitLen(6) <= toSlv(7, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(3, hitLen(0)'length);
  --  hitLen(9) <= toSlv(4, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(6, hitLen(0)'length);
  --  hitLen(12) <= toSlv(5, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(1, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(6, hitLen(0)'length);
  --  hitLen(21) <= toSlv(7, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(2, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 19 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(9, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(4, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(9, hitLen(0)'length);
  --  hitLen(6) <= toSlv(1, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(5, hitLen(0)'length);
  --  hitLen(12) <= toSlv(3, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(5, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(0, hitLen(0)'length);
  --  hitLen(17) <= toSlv(1, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(8, hitLen(0)'length);
  --  hitLen(20) <= toSlv(7, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(2, hitLen(0)'length);
  --  hitLen(23) <= toSlv(1, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 20 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(1, hitLen(0)'length);
  --  hitLen(3) <= toSlv(5, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(5, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(4, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(4, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(2, hitLen(0)'length);
  --  hitLen(18) <= toSlv(5, hitLen(0)'length);
  --  hitLen(19) <= toSlv(7, hitLen(0)'length);
  --  hitLen(20) <= toSlv(7, hitLen(0)'length);
  --  hitLen(21) <= toSlv(4, hitLen(0)'length);
  --  hitLen(22) <= toSlv(5, hitLen(0)'length);
  --  hitLen(23) <= toSlv(4, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 21 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(1, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(4, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(7, hitLen(0)'length);
  --  hitLen(6) <= toSlv(6, hitLen(0)'length);
  --  hitLen(7) <= toSlv(8, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(0, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(6, hitLen(0)'length);
  --  hitLen(12) <= toSlv(5, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(4, hitLen(0)'length);
  --  hitLen(17) <= toSlv(1, hitLen(0)'length);
  --  hitLen(18) <= toSlv(1, hitLen(0)'length);
  --  hitLen(19) <= toSlv(7, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(6, hitLen(0)'length);
  --  hitLen(23) <= toSlv(1, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 22 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(5, hitLen(0)'length);
  --  hitLen(2) <= toSlv(6, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(7, hitLen(0)'length);
  --  hitLen(6) <= toSlv(4, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(6, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(7, hitLen(0)'length);
  --  hitLen(18) <= toSlv(6, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(1, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 23 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(5, hitLen(0)'length);
  --  hitLen(2) <= toSlv(1, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(5, hitLen(0)'length);
  --  hitLen(7) <= toSlv(8, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(1, hitLen(0)'length);
  --  hitLen(11) <= toSlv(6, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(6, hitLen(0)'length);
  --  hitLen(15) <= toSlv(5, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(5, hitLen(0)'length);
  --  hitLen(19) <= toSlv(4, hitLen(0)'length);
  --  hitLen(20) <= toSlv(4, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(2, hitLen(0)'length);
  --  hitLen(23) <= toSlv(0, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 24 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(0, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(1, hitLen(0)'length);
  --  hitLen(3) <= toSlv(6, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(8, hitLen(0)'length);
  --  hitLen(6) <= toSlv(5, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(3, hitLen(0)'length);
  --  hitLen(9) <= toSlv(5, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(7, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(1, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(0, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(1, hitLen(0)'length);
  --  hitLen(22) <= toSlv(5, hitLen(0)'length);
  --  hitLen(23) <= toSlv(5, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 25 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(6, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(1, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(4, hitLen(0)'length);
  --  hitLen(7) <= toSlv(0, hitLen(0)'length);
  --  hitLen(8) <= toSlv(7, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(1, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(5, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(1, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(2, hitLen(0)'length);
  --  hitLen(23) <= toSlv(2, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 26 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(6, hitLen(0)'length);
  --  hitLen(4) <= toSlv(1, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(1, hitLen(0)'length);
  --  hitLen(8) <= toSlv(1, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(10, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(5, hitLen(0)'length);
  --  hitLen(20) <= toSlv(5, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(4, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 27 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(5, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(0, hitLen(0)'length);
  --  hitLen(6) <= toSlv(4, hitLen(0)'length);
  --  hitLen(7) <= toSlv(1, hitLen(0)'length);
  --  hitLen(8) <= toSlv(6, hitLen(0)'length);
  --  hitLen(9) <= toSlv(4, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(3, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(5, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 28 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(2, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(5, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(5, hitLen(0)'length);
  --  hitLen(10) <= toSlv(7, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(1, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(5, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(1, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(5, hitLen(0)'length);
  --  hitLen(23) <= toSlv(2, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 29 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(0, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(2, hitLen(0)'length);
  --  hitLen(3) <= toSlv(1, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(5, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(1, hitLen(0)'length);
  --  hitLen(13) <= toSlv(6, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(5, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(4, hitLen(0)'length);
  --  hitLen(19) <= toSlv(0, hitLen(0)'length);
  --  hitLen(20) <= toSlv(5, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(4, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 30 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(5, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(1, hitLen(0)'length);
  --  hitLen(8) <= toSlv(1, hitLen(0)'length);
  --  hitLen(9) <= toSlv(5, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(4, hitLen(0)'length);
  --  hitLen(12) <= toSlv(3, hitLen(0)'length);
  --  hitLen(13) <= toSlv(6, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(1, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(2, hitLen(0)'length);
  --  hitLen(23) <= toSlv(5, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 31 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(6, hitLen(0)'length);
  --  hitLen(1) <= toSlv(5, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(4, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(4, hitLen(0)'length);
  --  hitLen(17) <= toSlv(5, hitLen(0)'length);
  --  hitLen(18) <= toSlv(4, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(1, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(2, hitLen(0)'length);
  --  hitLen(23) <= toSlv(1, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 32 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(1, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(4, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(5, hitLen(0)'length);
  --  hitLen(9) <= toSlv(4, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(5, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(7, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(1, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(7, hitLen(0)'length);
  --  hitLen(22) <= toSlv(5, hitLen(0)'length);
  --  hitLen(23) <= toSlv(1, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 33 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(1, hitLen(0)'length);
  --  hitLen(1) <= toSlv(5, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(3, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(5, hitLen(0)'length);
  --  hitLen(15) <= toSlv(0, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(6, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(4, hitLen(0)'length);
  --  hitLen(22) <= toSlv(5, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 34 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(5, hitLen(0)'length);
  --  hitLen(2) <= toSlv(8, hitLen(0)'length);
  --  hitLen(3) <= toSlv(1, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(7, hitLen(0)'length);
  --  hitLen(9) <= toSlv(5, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(1, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(5, hitLen(0)'length);
  --  hitLen(19) <= toSlv(1, hitLen(0)'length);
  --  hitLen(20) <= toSlv(7, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 35 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(6, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(1, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(6, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(3, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(1, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(3, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(5, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(6, hitLen(0)'length);
  --  hitLen(22) <= toSlv(6, hitLen(0)'length);
  --  hitLen(23) <= toSlv(4, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 36 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(5, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(6, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(6, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(3, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(6, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(0, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(1, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(5, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 37 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(6, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(1, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(1, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(5, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(4, hitLen(0)'length);
  --  hitLen(12) <= toSlv(3, hitLen(0)'length);
  --  hitLen(13) <= toSlv(1, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(5, hitLen(0)'length);
  --  hitLen(18) <= toSlv(6, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(1, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(6, hitLen(0)'length);
  --  hitLen(23) <= toSlv(4, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 38 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(7, hitLen(0)'length);
  --  hitLen(2) <= toSlv(1, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(0, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(5, hitLen(0)'length);
  --  hitLen(8) <= toSlv(8, hitLen(0)'length);
  --  hitLen(9) <= toSlv(1, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(6, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(1, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(2, hitLen(0)'length);
  --  hitLen(23) <= toSlv(4, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 39 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(5, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(1, hitLen(0)'length);
  --  hitLen(9) <= toSlv(4, hitLen(0)'length);
  --  hitLen(10) <= toSlv(11, hitLen(0)'length);
  --  hitLen(11) <= toSlv(4, hitLen(0)'length);
  --  hitLen(12) <= toSlv(0, hitLen(0)'length);
  --  hitLen(13) <= toSlv(1, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(4, hitLen(0)'length);
  --  hitLen(17) <= toSlv(2, hitLen(0)'length);
  --  hitLen(18) <= toSlv(4, hitLen(0)'length);
  --  hitLen(19) <= toSlv(5, hitLen(0)'length);
  --  hitLen(20) <= toSlv(4, hitLen(0)'length);
  --  hitLen(21) <= toSlv(1, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(2, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 40 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(6, hitLen(0)'length);
  --  hitLen(1) <= toSlv(5, hitLen(0)'length);
  --  hitLen(2) <= toSlv(1, hitLen(0)'length);
  --  hitLen(3) <= toSlv(0, hitLen(0)'length);
  --  hitLen(4) <= toSlv(6, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(4, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(4, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(3, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(1, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(5, hitLen(0)'length);
  --  hitLen(19) <= toSlv(1, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 41 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(2, hitLen(0)'length);
  --  hitLen(3) <= toSlv(4, hitLen(0)'length);
  --  hitLen(4) <= toSlv(0, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(0, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(1, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(0, hitLen(0)'length);
  --  hitLen(12) <= toSlv(7, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(1, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(5, hitLen(0)'length);
  --  hitLen(18) <= toSlv(6, hitLen(0)'length);
  --  hitLen(19) <= toSlv(4, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(6, hitLen(0)'length);
  --  hitLen(22) <= toSlv(5, hitLen(0)'length);
  --  hitLen(23) <= toSlv(5, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 42 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(1, hitLen(0)'length);
  --  hitLen(1) <= toSlv(0, hitLen(0)'length);
  --  hitLen(2) <= toSlv(7, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(1, hitLen(0)'length);
  --  hitLen(7) <= toSlv(7, hitLen(0)'length);
  --  hitLen(8) <= toSlv(1, hitLen(0)'length);
  --  hitLen(9) <= toSlv(1, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(1, hitLen(0)'length);
  --  hitLen(12) <= toSlv(6, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(1, hitLen(0)'length);
  --  hitLen(19) <= toSlv(4, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(0, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 43 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(1, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(0, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(4, hitLen(0)'length);
  --  hitLen(7) <= toSlv(0, hitLen(0)'length);
  --  hitLen(8) <= toSlv(3, hitLen(0)'length);
  --  hitLen(9) <= toSlv(5, hitLen(0)'length);
  --  hitLen(10) <= toSlv(1, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(4, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(6, hitLen(0)'length);
  --  hitLen(22) <= toSlv(6, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 44 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(6, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(5, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(1, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(5, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(1, hitLen(0)'length);
  --  hitLen(12) <= toSlv(0, hitLen(0)'length);
  --  hitLen(13) <= toSlv(8, hitLen(0)'length);
  --  hitLen(14) <= toSlv(6, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(0, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(5, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(5, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 45 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(6, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(1, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(5, hitLen(0)'length);
  --  hitLen(6) <= toSlv(1, hitLen(0)'length);
  --  hitLen(7) <= toSlv(5, hitLen(0)'length);
  --  hitLen(8) <= toSlv(3, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(1, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(3, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(1, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(6, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(7, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(4, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(8, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 46 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(5, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(0, hitLen(0)'length);
  --  hitLen(5) <= toSlv(1, hitLen(0)'length);
  --  hitLen(6) <= toSlv(4, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(6, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(3, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(5, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(6, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(6, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(6, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 47 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(5, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(2, hitLen(0)'length);
  --  hitLen(3) <= toSlv(6, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(6, hitLen(0)'length);
  --  hitLen(6) <= toSlv(1, hitLen(0)'length);
  --  hitLen(7) <= toSlv(6, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(1, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(1, hitLen(0)'length);
  --  hitLen(12) <= toSlv(1, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(1, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(2, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 48 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(5, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(4, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(7, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(1, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(4, hitLen(0)'length);
  --  hitLen(17) <= toSlv(6, hitLen(0)'length);
  --  hitLen(18) <= toSlv(4, hitLen(0)'length);
  --  hitLen(19) <= toSlv(6, hitLen(0)'length);
  --  hitLen(20) <= toSlv(4, hitLen(0)'length);
  --  hitLen(21) <= toSlv(6, hitLen(0)'length);
  --  hitLen(22) <= toSlv(2, hitLen(0)'length);
  --  hitLen(23) <= toSlv(2, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 49 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(5, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(4, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(7, hitLen(0)'length);
  --  hitLen(9) <= toSlv(1, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(5, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(4, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(2, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 50 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(9, hitLen(0)'length);
  --  hitLen(3) <= toSlv(0, hitLen(0)'length);
  --  hitLen(4) <= toSlv(6, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(5, hitLen(0)'length);
  --  hitLen(7) <= toSlv(5, hitLen(0)'length);
  --  hitLen(8) <= toSlv(1, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(4, hitLen(0)'length);
  --  hitLen(12) <= toSlv(1, hitLen(0)'length);
  --  hitLen(13) <= toSlv(0, hitLen(0)'length);
  --  hitLen(14) <= toSlv(5, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(4, hitLen(0)'length);
  --  hitLen(17) <= toSlv(2, hitLen(0)'length);
  --  hitLen(18) <= toSlv(5, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(4, hitLen(0)'length);
  --  hitLen(21) <= toSlv(6, hitLen(0)'length);
  --  hitLen(22) <= toSlv(5, hitLen(0)'length);
  --  hitLen(23) <= toSlv(6, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 51 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(4, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(0, hitLen(0)'length);
  --  hitLen(7) <= toSlv(13, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(1, hitLen(0)'length);
  --  hitLen(11) <= toSlv(4, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(7, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(5, hitLen(0)'length);
  --  hitLen(19) <= toSlv(6, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(2, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 52 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(7, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(4, hitLen(0)'length);
  --  hitLen(12) <= toSlv(5, hitLen(0)'length);
  --  hitLen(13) <= toSlv(6, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(2, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(5, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(4, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 53 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(4, hitLen(0)'length);
  --  hitLen(7) <= toSlv(7, hitLen(0)'length);
  --  hitLen(8) <= toSlv(6, hitLen(0)'length);
  --  hitLen(9) <= toSlv(0, hitLen(0)'length);
  --  hitLen(10) <= toSlv(5, hitLen(0)'length);
  --  hitLen(11) <= toSlv(1, hitLen(0)'length);
  --  hitLen(12) <= toSlv(0, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(1, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(5, hitLen(0)'length);
  --  hitLen(19) <= toSlv(5, hitLen(0)'length);
  --  hitLen(20) <= toSlv(1, hitLen(0)'length);
  --  hitLen(21) <= toSlv(4, hitLen(0)'length);
  --  hitLen(22) <= toSlv(6, hitLen(0)'length);
  --  hitLen(23) <= toSlv(6, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 54 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(5, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(6, hitLen(0)'length);
  --  hitLen(10) <= toSlv(7, hitLen(0)'length);
  --  hitLen(11) <= toSlv(5, hitLen(0)'length);
  --  hitLen(12) <= toSlv(6, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(6, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(7, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(0, hitLen(0)'length);
  --  hitLen(23) <= toSlv(5, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 55 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(1, hitLen(0)'length);
  --  hitLen(1) <= toSlv(5, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(5, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(1, hitLen(0)'length);
  --  hitLen(6) <= toSlv(5, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(4, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(3, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(7, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(6, hitLen(0)'length);
  --  hitLen(19) <= toSlv(4, hitLen(0)'length);
  --  hitLen(20) <= toSlv(6, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(6, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 56 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(1, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(6, hitLen(0)'length);
  --  hitLen(3) <= toSlv(4, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(1, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(4, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(8, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(0, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(8, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(4, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 57 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(6, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(5, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(3, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(1, hitLen(0)'length);
  --  hitLen(17) <= toSlv(5, hitLen(0)'length);
  --  hitLen(18) <= toSlv(1, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(4, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(7, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 58 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(1, hitLen(0)'length);
  --  hitLen(3) <= toSlv(1, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(8, hitLen(0)'length);
  --  hitLen(6) <= toSlv(1, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(0, hitLen(0)'length);
  --  hitLen(12) <= toSlv(8, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(5, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(2, hitLen(0)'length);
  --  hitLen(18) <= toSlv(4, hitLen(0)'length);
  --  hitLen(19) <= toSlv(1, hitLen(0)'length);
  --  hitLen(20) <= toSlv(8, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 59 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(6, hitLen(0)'length);
  --  hitLen(2) <= toSlv(6, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(5, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(0, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(6, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(5, hitLen(0)'length);
  --  hitLen(18) <= toSlv(4, hitLen(0)'length);
  --  hitLen(19) <= toSlv(0, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(4, hitLen(0)'length);
  --  hitLen(22) <= toSlv(6, hitLen(0)'length);
  --  hitLen(23) <= toSlv(2, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 60 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(7, hitLen(0)'length);
  --  hitLen(3) <= toSlv(1, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(1, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(1, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(4, hitLen(0)'length);
  --  hitLen(10) <= toSlv(1, hitLen(0)'length);
  --  hitLen(11) <= toSlv(0, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(6, hitLen(0)'length);
  --  hitLen(14) <= toSlv(6, hitLen(0)'length);
  --  hitLen(15) <= toSlv(1, hitLen(0)'length);
  --  hitLen(16) <= toSlv(1, hitLen(0)'length);
  --  hitLen(17) <= toSlv(1, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(7, hitLen(0)'length);
  --  hitLen(20) <= toSlv(5, hitLen(0)'length);
  --  hitLen(21) <= toSlv(6, hitLen(0)'length);
  --  hitLen(22) <= toSlv(5, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 61 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(9, hitLen(0)'length);
  --  hitLen(8) <= toSlv(5, hitLen(0)'length);
  --  hitLen(9) <= toSlv(1, hitLen(0)'length);
  --  hitLen(10) <= toSlv(6, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(0, hitLen(0)'length);
  --  hitLen(16) <= toSlv(7, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(1, hitLen(0)'length);
  --  hitLen(19) <= toSlv(1, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(5, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 62 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(2, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(0, hitLen(0)'length);
  --  hitLen(6) <= toSlv(5, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(1, hitLen(0)'length);
  --  hitLen(9) <= toSlv(5, hitLen(0)'length);
  --  hitLen(10) <= toSlv(5, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(5, hitLen(0)'length);
  --  hitLen(16) <= toSlv(7, hitLen(0)'length);
  --  hitLen(17) <= toSlv(1, hitLen(0)'length);
  --  hitLen(18) <= toSlv(6, hitLen(0)'length);
  --  hitLen(19) <= toSlv(6, hitLen(0)'length);
  --  hitLen(20) <= toSlv(4, hitLen(0)'length);
  --  hitLen(21) <= toSlv(4, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(6, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 63 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(0, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(4, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(8, hitLen(0)'length);
  --  hitLen(10) <= toSlv(5, hitLen(0)'length);
  --  hitLen(11) <= toSlv(4, hitLen(0)'length);
  --  hitLen(12) <= toSlv(6, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(1, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(9, hitLen(0)'length);
  --  hitLen(17) <= toSlv(2, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(6, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(2, hitLen(0)'length);
  --  hitLen(23) <= toSlv(0, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 64 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(1, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(7, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(5, hitLen(0)'length);
  --  hitLen(10) <= toSlv(5, hitLen(0)'length);
  --  hitLen(11) <= toSlv(1, hitLen(0)'length);
  --  hitLen(12) <= toSlv(3, hitLen(0)'length);
  --  hitLen(13) <= toSlv(0, hitLen(0)'length);
  --  hitLen(14) <= toSlv(1, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(5, hitLen(0)'length);
  --  hitLen(21) <= toSlv(1, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(4, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 65 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(6, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(1, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(6, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(6, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(6, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(7, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(8, hitLen(0)'length);
  --  hitLen(17) <= toSlv(5, hitLen(0)'length);
  --  hitLen(18) <= toSlv(9, hitLen(0)'length);
  --  hitLen(19) <= toSlv(4, hitLen(0)'length);
  --  hitLen(20) <= toSlv(4, hitLen(0)'length);
  --  hitLen(21) <= toSlv(1, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(2, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 66 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(1, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(1, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(6, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(1, hitLen(0)'length);
  --  hitLen(10) <= toSlv(1, hitLen(0)'length);
  --  hitLen(11) <= toSlv(1, hitLen(0)'length);
  --  hitLen(12) <= toSlv(3, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(8, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(1, hitLen(0)'length);
  --  hitLen(17) <= toSlv(1, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(4, hitLen(0)'length);
  --  hitLen(20) <= toSlv(1, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 67 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(5, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(1, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(1, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(7, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(6, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(1, hitLen(0)'length);
  --  hitLen(18) <= toSlv(4, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(4, hitLen(0)'length);
  --  hitLen(21) <= toSlv(4, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 68 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(1, hitLen(0)'length);
  --  hitLen(1) <= toSlv(0, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(0, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(1, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(5, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(1, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(2, hitLen(0)'length);
  --  hitLen(18) <= toSlv(5, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(8, hitLen(0)'length);
  --  hitLen(21) <= toSlv(1, hitLen(0)'length);
  --  hitLen(22) <= toSlv(7, hitLen(0)'length);
  --  hitLen(23) <= toSlv(10, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 69 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(5, hitLen(0)'length);
  --  hitLen(1) <= toSlv(7, hitLen(0)'length);
  --  hitLen(2) <= toSlv(6, hitLen(0)'length);
  --  hitLen(3) <= toSlv(4, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(3, hitLen(0)'length);
  --  hitLen(9) <= toSlv(1, hitLen(0)'length);
  --  hitLen(10) <= toSlv(1, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(0, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(6, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(6, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(4, hitLen(0)'length);
  --  hitLen(21) <= toSlv(6, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 70 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(3, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(1, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(6, hitLen(0)'length);
  --  hitLen(8) <= toSlv(6, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(7, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(7, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(5, hitLen(0)'length);
  --  hitLen(15) <= toSlv(8, hitLen(0)'length);
  --  hitLen(16) <= toSlv(4, hitLen(0)'length);
  --  hitLen(17) <= toSlv(5, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(1, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(0, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(0, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 71 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(2, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(6, hitLen(0)'length);
  --  hitLen(5) <= toSlv(5, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(5, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(5, hitLen(0)'length);
  --  hitLen(21) <= toSlv(4, hitLen(0)'length);
  --  hitLen(22) <= toSlv(0, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 72 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(5, hitLen(0)'length);
  --  hitLen(2) <= toSlv(2, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(1, hitLen(0)'length);
  --  hitLen(6) <= toSlv(6, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(0, hitLen(0)'length);
  --  hitLen(9) <= toSlv(5, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(1, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(6, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(2, hitLen(0)'length);
  --  hitLen(18) <= toSlv(8, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(4, hitLen(0)'length);
  --  hitLen(21) <= toSlv(6, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(4, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 73 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(0, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(8, hitLen(0)'length);
  --  hitLen(8) <= toSlv(3, hitLen(0)'length);
  --  hitLen(9) <= toSlv(5, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(5, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(0, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(6, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(4, hitLen(0)'length);
  --  hitLen(19) <= toSlv(6, hitLen(0)'length);
  --  hitLen(20) <= toSlv(6, hitLen(0)'length);
  --  hitLen(21) <= toSlv(6, hitLen(0)'length);
  --  hitLen(22) <= toSlv(5, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 74 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(1, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(2, hitLen(0)'length);
  --  hitLen(6) <= toSlv(5, hitLen(0)'length);
  --  hitLen(7) <= toSlv(5, hitLen(0)'length);
  --  hitLen(8) <= toSlv(3, hitLen(0)'length);
  --  hitLen(9) <= toSlv(0, hitLen(0)'length);
  --  hitLen(10) <= toSlv(0, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(5, hitLen(0)'length);
  --  hitLen(13) <= toSlv(0, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(4, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(5, hitLen(0)'length);
  --  hitLen(19) <= toSlv(4, hitLen(0)'length);
  --  hitLen(20) <= toSlv(0, hitLen(0)'length);
  --  hitLen(21) <= toSlv(4, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(2, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 75 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(6, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(5, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(7, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(7, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(1, hitLen(0)'length);
  --  hitLen(19) <= toSlv(4, hitLen(0)'length);
  --  hitLen(20) <= toSlv(5, hitLen(0)'length);
  --  hitLen(21) <= toSlv(4, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 76 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(7, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(1, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(3, hitLen(0)'length);
  --  hitLen(9) <= toSlv(5, hitLen(0)'length);
  --  hitLen(10) <= toSlv(5, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(5, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(0, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(0, hitLen(0)'length);
  --  hitLen(23) <= toSlv(2, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 77 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(5, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(1, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(1, hitLen(0)'length);
  --  hitLen(6) <= toSlv(5, hitLen(0)'length);
  --  hitLen(7) <= toSlv(5, hitLen(0)'length);
  --  hitLen(8) <= toSlv(0, hitLen(0)'length);
  --  hitLen(9) <= toSlv(4, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(7, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(1, hitLen(0)'length);
  --  hitLen(16) <= toSlv(4, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(1, hitLen(0)'length);
  --  hitLen(19) <= toSlv(10, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(1, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(6, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 78 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(5, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(4, hitLen(0)'length);
  --  hitLen(7) <= toSlv(1, hitLen(0)'length);
  --  hitLen(8) <= toSlv(8, hitLen(0)'length);
  --  hitLen(9) <= toSlv(4, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(5, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(5, hitLen(0)'length);
  --  hitLen(16) <= toSlv(0, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(1, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(7, hitLen(0)'length);
  --  hitLen(22) <= toSlv(5, hitLen(0)'length);
  --  hitLen(23) <= toSlv(1, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 79 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(5, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(1, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(0, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(7, hitLen(0)'length);
  --  hitLen(11) <= toSlv(6, hitLen(0)'length);
  --  hitLen(12) <= toSlv(1, hitLen(0)'length);
  --  hitLen(13) <= toSlv(1, hitLen(0)'length);
  --  hitLen(14) <= toSlv(1, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(1, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(6, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(1, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(2, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 80 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(0, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(1, hitLen(0)'length);
  --  hitLen(5) <= toSlv(6, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(1, hitLen(0)'length);
  --  hitLen(9) <= toSlv(6, hitLen(0)'length);
  --  hitLen(10) <= toSlv(1, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(6, hitLen(0)'length);
  --  hitLen(14) <= toSlv(5, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(4, hitLen(0)'length);
  --  hitLen(17) <= toSlv(2, hitLen(0)'length);
  --  hitLen(18) <= toSlv(4, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(9, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(5, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 81 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(1, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(6, hitLen(0)'length);
  --  hitLen(5) <= toSlv(1, hitLen(0)'length);
  --  hitLen(6) <= toSlv(1, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(7, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(1, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(3, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(5, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(6, hitLen(0)'length);
  --  hitLen(18) <= toSlv(5, hitLen(0)'length);
  --  hitLen(19) <= toSlv(4, hitLen(0)'length);
  --  hitLen(20) <= toSlv(7, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(5, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 82 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(1, hitLen(0)'length);
  --  hitLen(3) <= toSlv(4, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(4, hitLen(0)'length);
  --  hitLen(7) <= toSlv(6, hitLen(0)'length);
  --  hitLen(8) <= toSlv(3, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(4, hitLen(0)'length);
  --  hitLen(12) <= toSlv(0, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(6, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(5, hitLen(0)'length);
  --  hitLen(18) <= toSlv(1, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(8, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(6, hitLen(0)'length);
  --  hitLen(23) <= toSlv(5, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 83 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(5, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(1, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(4, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(0, hitLen(0)'length);
  --  hitLen(9) <= toSlv(1, hitLen(0)'length);
  --  hitLen(10) <= toSlv(7, hitLen(0)'length);
  --  hitLen(11) <= toSlv(4, hitLen(0)'length);
  --  hitLen(12) <= toSlv(1, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(6, hitLen(0)'length);
  --  hitLen(15) <= toSlv(5, hitLen(0)'length);
  --  hitLen(16) <= toSlv(1, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(5, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(4, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(4, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 84 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(0, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(1, hitLen(0)'length);
  --  hitLen(5) <= toSlv(6, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(0, hitLen(0)'length);
  --  hitLen(10) <= toSlv(5, hitLen(0)'length);
  --  hitLen(11) <= toSlv(4, hitLen(0)'length);
  --  hitLen(12) <= toSlv(11, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(7, hitLen(0)'length);
  --  hitLen(17) <= toSlv(6, hitLen(0)'length);
  --  hitLen(18) <= toSlv(5, hitLen(0)'length);
  --  hitLen(19) <= toSlv(0, hitLen(0)'length);
  --  hitLen(20) <= toSlv(7, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(6, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 85 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(1, hitLen(0)'length);
  --  hitLen(3) <= toSlv(6, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(7, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(5, hitLen(0)'length);
  --  hitLen(9) <= toSlv(4, hitLen(0)'length);
  --  hitLen(10) <= toSlv(6, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(6, hitLen(0)'length);
  --  hitLen(17) <= toSlv(1, hitLen(0)'length);
  --  hitLen(18) <= toSlv(1, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(5, hitLen(0)'length);
  --  hitLen(21) <= toSlv(9, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(2, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 86 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(5, hitLen(0)'length);
  --  hitLen(2) <= toSlv(2, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(4, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(1, hitLen(0)'length);
  --  hitLen(9) <= toSlv(1, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(3, hitLen(0)'length);
  --  hitLen(13) <= toSlv(1, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(2, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(0, hitLen(0)'length);
  --  hitLen(22) <= toSlv(2, hitLen(0)'length);
  --  hitLen(23) <= toSlv(7, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 87 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(5, hitLen(0)'length);
  --  hitLen(6) <= toSlv(0, hitLen(0)'length);
  --  hitLen(7) <= toSlv(0, hitLen(0)'length);
  --  hitLen(8) <= toSlv(3, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(1, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(0, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(7, hitLen(0)'length);
  --  hitLen(19) <= toSlv(7, hitLen(0)'length);
  --  hitLen(20) <= toSlv(6, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(4, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 88 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(9, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(5, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(1, hitLen(0)'length);
  --  hitLen(11) <= toSlv(4, hitLen(0)'length);
  --  hitLen(12) <= toSlv(1, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(5, hitLen(0)'length);
  --  hitLen(19) <= toSlv(5, hitLen(0)'length);
  --  hitLen(20) <= toSlv(4, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(2, hitLen(0)'length);
  --  hitLen(23) <= toSlv(6, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 89 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(5, hitLen(0)'length);
  --  hitLen(2) <= toSlv(8, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(5, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(1, hitLen(0)'length);
  --  hitLen(12) <= toSlv(2, hitLen(0)'length);
  --  hitLen(13) <= toSlv(6, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(2, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(10, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 90 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(2, hitLen(0)'length);
  --  hitLen(3) <= toSlv(1, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(4, hitLen(0)'length);
  --  hitLen(7) <= toSlv(5, hitLen(0)'length);
  --  hitLen(8) <= toSlv(3, hitLen(0)'length);
  --  hitLen(9) <= toSlv(1, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(5, hitLen(0)'length);
  --  hitLen(12) <= toSlv(5, hitLen(0)'length);
  --  hitLen(13) <= toSlv(4, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(1, hitLen(0)'length);
  --  hitLen(20) <= toSlv(3, hitLen(0)'length);
  --  hitLen(21) <= toSlv(1, hitLen(0)'length);
  --  hitLen(22) <= toSlv(3, hitLen(0)'length);
  --  hitLen(23) <= toSlv(5, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 91 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(1, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(0, hitLen(0)'length);
  --  hitLen(4) <= toSlv(6, hitLen(0)'length);
  --  hitLen(5) <= toSlv(6, hitLen(0)'length);
  --  hitLen(6) <= toSlv(2, hitLen(0)'length);
  --  hitLen(7) <= toSlv(1, hitLen(0)'length);
  --  hitLen(8) <= toSlv(6, hitLen(0)'length);
  --  hitLen(9) <= toSlv(1, hitLen(0)'length);
  --  hitLen(10) <= toSlv(6, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(5, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(6, hitLen(0)'length);
  --  hitLen(16) <= toSlv(3, hitLen(0)'length);
  --  hitLen(17) <= toSlv(2, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(6, hitLen(0)'length);
  --  hitLen(20) <= toSlv(6, hitLen(0)'length);
  --  hitLen(21) <= toSlv(4, hitLen(0)'length);
  --  hitLen(22) <= toSlv(2, hitLen(0)'length);
  --  hitLen(23) <= toSlv(4, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 92 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(1, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(0, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(6, hitLen(0)'length);
  --  hitLen(5) <= toSlv(5, hitLen(0)'length);
  --  hitLen(6) <= toSlv(10, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(8, hitLen(0)'length);
  --  hitLen(11) <= toSlv(5, hitLen(0)'length);
  --  hitLen(12) <= toSlv(1, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(5, hitLen(0)'length);
  --  hitLen(17) <= toSlv(3, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(6, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(5, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 93 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(5, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(2, hitLen(0)'length);
  --  hitLen(14) <= toSlv(6, hitLen(0)'length);
  --  hitLen(15) <= toSlv(3, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(1, hitLen(0)'length);
  --  hitLen(18) <= toSlv(8, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(6, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(4, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 94 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(1, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(3, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(4, hitLen(0)'length);
  --  hitLen(6) <= toSlv(1, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(1, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(2, hitLen(0)'length);
  --  hitLen(11) <= toSlv(6, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(1, hitLen(0)'length);
  --  hitLen(14) <= toSlv(1, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(4, hitLen(0)'length);
  --  hitLen(17) <= toSlv(2, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(0, hitLen(0)'length);
  --  hitLen(20) <= toSlv(4, hitLen(0)'length);
  --  hitLen(21) <= toSlv(0, hitLen(0)'length);
  --  hitLen(22) <= toSlv(2, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 95 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(4, hitLen(0)'length);
  --  hitLen(2) <= toSlv(4, hitLen(0)'length);
  --  hitLen(3) <= toSlv(2, hitLen(0)'length);
  --  hitLen(4) <= toSlv(2, hitLen(0)'length);
  --  hitLen(5) <= toSlv(6, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(1, hitLen(0)'length);
  --  hitLen(9) <= toSlv(5, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(6, hitLen(0)'length);
  --  hitLen(12) <= toSlv(6, hitLen(0)'length);
  --  hitLen(13) <= toSlv(5, hitLen(0)'length);
  --  hitLen(14) <= toSlv(2, hitLen(0)'length);
  --  hitLen(15) <= toSlv(2, hitLen(0)'length);
  --  hitLen(16) <= toSlv(0, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(4, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 96 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(6, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(7, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(3, hitLen(0)'length);
  --  hitLen(8) <= toSlv(5, hitLen(0)'length);
  --  hitLen(9) <= toSlv(2, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(0, hitLen(0)'length);
  --  hitLen(17) <= toSlv(5, hitLen(0)'length);
  --  hitLen(18) <= toSlv(5, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(5, hitLen(0)'length);
  --  hitLen(21) <= toSlv(3, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(4, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 97 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(4, hitLen(0)'length);
  --  hitLen(1) <= toSlv(1, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(7, hitLen(0)'length);
  --  hitLen(4) <= toSlv(4, hitLen(0)'length);
  --  hitLen(5) <= toSlv(3, hitLen(0)'length);
  --  hitLen(6) <= toSlv(3, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(4, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(3, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(1, hitLen(0)'length);
  --  hitLen(14) <= toSlv(3, hitLen(0)'length);
  --  hitLen(15) <= toSlv(4, hitLen(0)'length);
  --  hitLen(16) <= toSlv(2, hitLen(0)'length);
  --  hitLen(17) <= toSlv(5, hitLen(0)'length);
  --  hitLen(18) <= toSlv(2, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(4, hitLen(0)'length);
  --  hitLen(22) <= toSlv(5, hitLen(0)'length);
  --  hitLen(23) <= toSlv(1, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 98 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(1, hitLen(0)'length);
  --  hitLen(1) <= toSlv(2, hitLen(0)'length);
  --  hitLen(2) <= toSlv(2, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(3, hitLen(0)'length);
  --  hitLen(5) <= toSlv(0, hitLen(0)'length);
  --  hitLen(6) <= toSlv(6, hitLen(0)'length);
  --  hitLen(7) <= toSlv(4, hitLen(0)'length);
  --  hitLen(8) <= toSlv(3, hitLen(0)'length);
  --  hitLen(9) <= toSlv(3, hitLen(0)'length);
  --  hitLen(10) <= toSlv(4, hitLen(0)'length);
  --  hitLen(11) <= toSlv(5, hitLen(0)'length);
  --  hitLen(12) <= toSlv(5, hitLen(0)'length);
  --  hitLen(13) <= toSlv(9, hitLen(0)'length);
  --  hitLen(14) <= toSlv(0, hitLen(0)'length);
  --  hitLen(15) <= toSlv(6, hitLen(0)'length);
  --  hitLen(16) <= toSlv(0, hitLen(0)'length);
  --  hitLen(17) <= toSlv(4, hitLen(0)'length);
  --  hitLen(18) <= toSlv(3, hitLen(0)'length);
  --  hitLen(19) <= toSlv(2, hitLen(0)'length);
  --  hitLen(20) <= toSlv(2, hitLen(0)'length);
  --  hitLen(21) <= toSlv(5, hitLen(0)'length);
  --  hitLen(22) <= toSlv(1, hitLen(0)'length);
  --  hitLen(23) <= toSlv(3, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ------------------------------------------
  ------------------------------------------


  ------------------------------------------
  ----------------- hit = 99 ---------------
  ------------------------------------------
  --wait for CLK_PERIOD_SPARSE_C*93;
  --  hitLen(0) <= toSlv(2, hitLen(0)'length);
  --  hitLen(1) <= toSlv(3, hitLen(0)'length);
  --  hitLen(2) <= toSlv(5, hitLen(0)'length);
  --  hitLen(3) <= toSlv(3, hitLen(0)'length);
  --  hitLen(4) <= toSlv(5, hitLen(0)'length);
  --  hitLen(5) <= toSlv(6, hitLen(0)'length);
  --  hitLen(6) <= toSlv(6, hitLen(0)'length);
  --  hitLen(7) <= toSlv(2, hitLen(0)'length);
  --  hitLen(8) <= toSlv(2, hitLen(0)'length);
  --  hitLen(9) <= toSlv(8, hitLen(0)'length);
  --  hitLen(10) <= toSlv(3, hitLen(0)'length);
  --  hitLen(11) <= toSlv(2, hitLen(0)'length);
  --  hitLen(12) <= toSlv(4, hitLen(0)'length);
  --  hitLen(13) <= toSlv(3, hitLen(0)'length);
  --  hitLen(14) <= toSlv(4, hitLen(0)'length);
  --  hitLen(15) <= toSlv(5, hitLen(0)'length);
  --  hitLen(16) <= toSlv(1, hitLen(0)'length);
  --  hitLen(17) <= toSlv(2, hitLen(0)'length);
  --  hitLen(18) <= toSlv(5, hitLen(0)'length);
  --  hitLen(19) <= toSlv(3, hitLen(0)'length);
  --  hitLen(20) <= toSlv(5, hitLen(0)'length);
  --  hitLen(21) <= toSlv(2, hitLen(0)'length);
  --  hitLen(22) <= toSlv(4, hitLen(0)'length);
  --  hitLen(23) <= toSlv(2, hitLen(0)'length);
  --  sro <= '1';
  --wait for CLK_PERIOD_SPARSE_C*2;
  --  sro <= '0';
  ----------------------------------------
  ----------------------------------------

    -- do not touch begin
    wait;
    -- do not touch end

  end process stimulus;

  writeDataProcess: process(pgpClk)

    -- variables for file-writing
    file myFile  : text open write_mode is "pix2pgpRxDataDump.dat";
    variable row : line;

  begin
    if (rising_edge(pgpClk)) then
      -- first check if the rst is low
      if (rst = '0') then
        -- then check if the valid flag is high
        if pgpValid = '1' then
          -- syntax: write(row_variable,what_to_write,
          -- justification(right/left), trailing_whitespaces);
          -- writeline(file_variable, row_variable);
          hwrite(row, pgpData, right, 0);
          writeline(myFile,row);
        end if;
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
            clk     => sparseClk,
            rst     => rst,
            sro     => sroFinal,
            pause   => pause(col),
            hitLen  => hitLen(col),
            sof     => sof(col),
            eof     => eof(col),
            busy    => busy(col),
            overOcc => overOcc(col),
            ackN    => ackN(col),
            wrEn    => wrEn(col),
            dout    => din(col));
   end generate GEN_DUMMY_PIXEL;

   ------
   -- UUT
   ------
   U_Uut : entity pix2pgp.Pix2PgpTb
      generic map(
         TPD_G                      => TPD_G,
         RST_ASYNC_G                => RST_ASYNC_G,
         RST_POLARITY_G             => RST_POLARITY_G,
         DATAFIFO_PIPE_G            => DATAFIFO_PIPE_G,
         STATUSFIFO_PIPE_G          => STATUSFIFO_PIPE_G,
         PIPELINE_BRIDGE_DATA_G     => PIPELINE_BRIDGE_DATA_G,
         PIPELINE_BRIDGE_STATUS_G   => PIPELINE_BRIDGE_STATUS_G,
         COLMANAGER_DATA_DEPTH_G    => COLMANAGER_DATA_DEPTH_G,
         COLMANAGER_DATA_AF_LVL_G   => COLMANAGER_DATA_AF_LVL_G,
         COLMANAGER_STATUS_DEPTH_G  => COLMANAGER_STATUS_DEPTH_G,
         COLMANAGER_STATUS_AF_LVL_G => COLMANAGER_STATUS_AF_LVL_G,
         ADAPTER_DEPTH_G            => ADAPTER_DEPTH_G,
         ADAPTER_AF_LVL_G           => ADAPTER_AF_LVL_G,
         SUPER_FIFO_RD_DELAY_G      => SUPER_FIFO_RD_DELAY_G,
         ARB_DOUT_PIPE_G            => ARB_DOUT_PIPE_G)
      port map(
         sparseClk    => sparseClk,
         pgpClk       => pgpClk,
         rst          => rst,
         sro          => sroFinal,
         pause        => pause,
         sof          => sof,
         eof          => eof,
         busy         => busy,
         overOcc      => overOcc,
         ackN         => ackN,
         wrEn         => wrEn,
         din          => din,
         pgpDout      => pgpDout,
         pgpDoutValid => pgpDoutValid,
         pgpDoutReady => pgpDoutReady);

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
       pgpDin      => pgpDout,
       pgpDinValid => pgpDoutValid,
       pgpDinReady => pgpDoutReady,
       -- FPGA RX Interface
       pgpValid    => pgpValid,
       pgpData     => pgpData);

end architecture;
