library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;


entity Pix2PgpTopTb is
end entity Pix2PgpTopTb;

architecture test of Pix2PgpTopTb is

   constant TPD_C          : time    := 1 ns;
   constant RST_ASYNC_C    : boolean := true;
   constant RST_POLARITY_C : sl := '1';
   constant STANDALONE_C   : boolean := true;
   constant PIPELINE_C     : boolean := true;
   constant CLK_PERIOD_C   : time := 5.384 ns;

   type dinArrayType is array (0 to NUM_OF_COL_MANAGERS_C-1) of slv(SPARSE_DWIDTH_C-1 downto 0);
   type doutArrayType is array (0 to NUM_OF_COL_MANAGERS_C-1) of slv(DATABUS_DWIDTH_C-1 downto 0);

   signal clk       : sl := '0';
   signal rst       : sl := '1';

   signal tok       : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal tokFb     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal ackN      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal wrEn      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal din       : Pix2PgpSparseDinArray := (others => (others => '0'));

   signal txReady   : sl := '1';
   signal txValid   : sl := '0';
   signal txData    : slv(63 downto 0) := (others => '0');
   signal txSof     : sl := '0';
   signal txEof     : sl := '0';
   signal txEofe    : sl := '0';

   signal pgpValid  : sl := '0';
   signal pgpData   : slv(PGP_DWIDTH_C-1 downto 0) := (others => '0');

   signal frameSize : slv(5 downto 0) := toSlv(2, 6);

   signal fillFifos : sl := '0';
   signal fillCnt   : natural range 0 to 1023;

begin

  -- rst and clk
  clk <= not clk after CLK_PERIOD_C - TPD_C;
  rst <= '1', '0' after CLK_PERIOD_C*20;


  -- Instantiate the design under test
   U_Pix2PgpTop : entity pix2pgp.Pix2PgpTop
      generic map (
         TPD_G          => TPD_C,
         RST_ASYNC_G    => RST_ASYNC_C,
         RST_POLARITY_G => RST_POLARITY_C,
         STANDALONE_G   => STANDALONE_C,
         PIPELINE_G     => PIPELINE_C)
      port map (
         -- General Interface
         sparseClk => clk,
         pgpClk    => clk,
         rst       => rst,
         -- Column Manager Interface
         tok       => tok,
         tokFb     => tokFb,
         ackN      => ackN,
         wrEn      => wrEn,
         din       => din,
         -- Pgp4TxLite Interface
         txReady   => txReady,
         txValid   => txValid,
         txData    => txData,
         txSof     => txSof,
         txEof     => txEof,
         txEofe    => txEofe,
         -- Temporary Debugging Interface (TO-DO: remove me)
         pgpValid  => pgpValid,
         pgpData   => pgpData,
         -- Configuration Register Interface (TO-DO: add more)
         frameSize => frameSize);

  -- Generate the test stimulus
  stimulus: process begin

    -- Wait for the rst to be released before
    wait until (rst = '0');

    wait for CLK_PERIOD_C*300;
      fillFifos <= '1';

    wait for CLK_PERIOD_C*320;
      fillFifos  <= '0';
    wait;

  end process stimulus;

end architecture;