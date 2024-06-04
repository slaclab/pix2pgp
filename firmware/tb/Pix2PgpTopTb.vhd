library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

-- required for writing/reading std_logic etc.
use std.textio.all;
use ieee.std_logic_textio.all;

library surf;
use surf.StdRtlPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;


entity Pix2PgpTopTb is
end entity Pix2PgpTopTb;

architecture test of Pix2PgpTopTb is

   constant TPD_C                 : time    := 1 ns;
   constant RST_ASYNC_C           : boolean := True;
   constant RST_POLARITY_C        : sl := '1';
   constant GHDL_SIM_C            : boolean := True;
   constant DATAFIFO_PIPE_C       : positive := 2;
   constant STATUSFIFO_PIPE_C     : positive := 2;
   constant DATAFIFO_FWFT_C       : boolean := True;
   constant PIPELINE_BRIDGE_C     : boolean := False;
   constant SUPER_FIFO_RD_DELAY_C : natural := 3;
   constant ARB_FIFO_RD_DELAY_C   : natural := 1;
   constant ARB_DOUT_PIPE_C       : natural := 2;
   --
   constant CLK_PERIOD_C          : time := 5.384 ns;

   signal clk          : sl := '0';
   signal rst          : sl := '1';

   signal tok          : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '1');
   signal tokFb        : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal ackN         : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '1');
   signal wrEn         : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal din          : Pix2PgpSparseDinArray := (others => (others => '0'));

   signal txReady      : sl := '1';
   signal txValid      : sl := '0';
   signal txData       : slv(63 downto 0) := (others => '0');
   signal txSof        : sl := '0';
   signal txEof        : sl := '0';
   signal txEofe       : sl := '0';

   signal arbValidDbg  : sl := '0';
   signal arbDataDbg   : slv(DATABUS_DWIDTH_C-1 downto 0) := (others => '0');

   signal frameSize    : slv(5 downto 0) := toSlv(2, 6);

   signal fillFifos    : sl := '0';
   signal fillCnt      : natural range 0 to 1023;

   type hitLenArray is array (0 to NUM_OF_COL_MANAGERS_C-1) of slv(9 downto 0);
   signal hitLen  : hitLenArray := (others => (others => '0'));
   signal overOcc : sl := '0';
   signal sro     : sl := '0';

   signal phyTxValid  : sl := '0';
   signal phyTxReady  : sl := '0';
   signal phyTxData   : slv(65 downto 0) := (others => '0');

   signal pgpData32b  : slv(31 downto 0) := (others => '0');
begin

  -- rst and clk
  clk <= not clk after CLK_PERIOD_C - TPD_C;
  rst <= '1', '0' after CLK_PERIOD_C*20;

  -- Instantiate the design under test
   U_Pix2PgpTop : entity pix2pgp.Pix2PgpTop
      generic map (
         TPD_G                 => TPD_C,
         RST_ASYNC_G           => RST_ASYNC_C,
         RST_POLARITY_G        => RST_POLARITY_C,
         GHDL_SIM_G            => GHDL_SIM_C,
         DATAFIFO_FWFT_G       => DATAFIFO_FWFT_C,
         PIPELINE_BRIDGE_G     => PIPELINE_BRIDGE_C,
         DATAFIFO_PIPE_G       => DATAFIFO_PIPE_C,
         STATUSFIFO_PIPE_G     => STATUSFIFO_PIPE_C,
         SUPER_FIFO_RD_DELAY_G => SUPER_FIFO_RD_DELAY_C,
         ARB_FIFO_RD_DELAY_G   => ARB_FIFO_RD_DELAY_C,
         ARB_DOUT_PIPE_G       => ARB_DOUT_PIPE_C)
      port map (
         -- General Interface
         sparseClk    => clk,
         pgpClk       => clk,
         rst          => rst,
         -- Column Manager Interface
         tok          => tok,
         tokFb        => tokFb,
         ackN         => ackN,
         wrEn         => wrEn,
         din          => din,
         -- Pgp4TxLite Interface
         txReady      => txReady,
         txValid      => txValid,
         txData       => txData,
         txSof        => txSof,
         txEof        => txEof,
         txEofe       => txEofe,
         -- Temporary Debugging Interface (TO-DO: remove me)
         arbValidDbg  => arbValidDbg,
         arbDataDbg   => arbDataDbg,
         -- Configuration Register Interface (TO-DO: add more)
         frameSize    => frameSize);

    -- Instantiate the PGP4TxLiteWrapper
    --U_Pgp4TxLiteWrapper : entity surf.Pgp4TxLiteWrapper
    --  port map(
    --    -- Clock and Reset
    --    clk        => clk,
    --    rst        => rst,
    --    -- 64-bit Input Framing Interface
    --    txReady    => txReady,
    --    txValid    => txValid,
    --    txData     => txData,
    --    txSof      => txSof,
    --    txEof      => txEof,
    --    txEofe     => txEofe,
    --    -- 66-bit Output Interface
    --    phyTxValid => phyTxValid,
    --    phyTxReady => phyTxReady,
    --    phyTxData  => phyTxData);

    --U_Serializer : entity surf.Gearbox
    --  generic map (
    --     TPD_G          => TPD_C,
    --     RST_ASYNC_G    => RST_ASYNC_C,
    --     SLAVE_WIDTH_G  => 66,
    --     MASTER_WIDTH_G => 32)
    --  port map (
    --     -- Clock and Reset
    --     clk            => clk,
    --     rst            => rst,
    --     -- Slave Interface
    --     slaveValid     => phyTxValid,
    --     slaveReady     => phyTxReady,
    --     slaveData      => phyTxData,
    --     slaveBitOrder  => '0',
    --     -- Master Interface
    --     masterBitOrder => '0',
    --     masterData     => pgpData32b);

   GEN_DUMMY_PIXEL: for col in 0 to NUM_OF_COL_MANAGERS_C-1 generate
      U_DummyPixel : entity pix2pgp.DummyPixel
         generic map(
            TPD_G        => TPD_C,
            RST_ASYNC_G  => RST_ASYNC_C,
            WAIT_FB_G    => 2,
            WAIT_ACKN_G  => 1,
            WAIT_WREN_G  => 1,
            COL_ID_G     => col)
         port map(
            clk     => clk,
            rst     => rst,
            sro     => sro,
            hitLen  => hitLen(col),
            overOcc => overOcc,
            tok     => tok(col),
            tokFb   => tokFb(col),
            ackN    => ackN(col),
            wrEn    => wrEn(col),
            dout    => din(col));
   end generate GEN_DUMMY_PIXEL;

  -- Generate the test stimulus
  stimulus: process begin

    -- Wait for the rst to be released before
    wait until (rst = '0');
    for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
      -- only even number of events please
      hitLen(col) <= toSlv(0, hitLen(col)'length);
    end loop;

    wait for CLK_PERIOD_C*300;
      sro <= '1';
    wait for CLK_PERIOD_C*2;
      sro  <= '0';

    wait for CLK_PERIOD_C*186;
      sro  <= '1';
    wait for CLK_PERIOD_C*2;
      sro  <= '0';

    wait for CLK_PERIOD_C*186;
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
         hitLen(col) <= toSlv(4, hitLen(col)'length);
      end loop;
      sro  <= '1';
    wait for CLK_PERIOD_C*2;
      sro  <= '0';

    wait for CLK_PERIOD_C*186;
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
         hitLen(col) <= toSlv(0, hitLen(col)'length);
      end loop;
      sro  <= '1';
    wait for CLK_PERIOD_C*2;
      sro  <= '0';

    wait for CLK_PERIOD_C*186;
      sro  <= '1';
    wait for CLK_PERIOD_C*2;
      sro  <= '0';

    wait for CLK_PERIOD_C*186;
      hitLen(0) <= toSlv(2, hitLen(0)'length);
      hitLen(5) <= toSlv(2, hitLen(5)'length);
      sro  <= '1';
    wait for CLK_PERIOD_C*2;
      sro  <= '0';

    wait for CLK_PERIOD_C*186;
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
        hitLen(col) <= toSlv(0, hitLen(col)'length);
      end loop;
      sro  <= '1';
    wait for CLK_PERIOD_C*2;
      sro  <= '0';

    wait for CLK_PERIOD_C*186;
      sro  <= '1';
    wait for CLK_PERIOD_C*2;
      sro  <= '0';

    wait for CLK_PERIOD_C*186;
      sro  <= '1';
    wait for CLK_PERIOD_C*2;
      sro  <= '0';

    wait for CLK_PERIOD_C*186;
      sro  <= '1';
    wait for CLK_PERIOD_C*2;
      sro  <= '0';
    wait;

  end process stimulus;

  writeDataProcess: process(clk)

    -- variables for file-writing
    file myFile  : text open write_mode is "pix2pgpArbDataDump.dat";
    variable row : line;

  begin
    if (rising_edge(clk)) then
      -- first check if the rst is low
      if (rst = '0') then
        -- then check if the valid flag is high
        if arbValidDbg = '1' then
          -- syntax: write(row_variable,what_to_write,
          -- justification(right/left), trailing_whitespaces);
          -- writeline(file_variable, row_variable);
          hwrite(row, arbDataDbg, right, 0);
          writeline(myFile,row);
        end if;
      end if;
    end if;
  end process;


end architecture;