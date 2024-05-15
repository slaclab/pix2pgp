library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;


entity SampleTb is
end entity SampleTb;

architecture test of SampleTb is

   constant TPD_C       : time    := 1 ns;
   constant RST_ASYNC_C : boolean := true;

  signal clk  : sl := '0';
  signal rst  : sl := '1';

  signal din  : sl := '0';
  signal dout : sl := '0';

begin


  -- rst and clk
  clk <= not clk after 2 ns;
  rst <= '1', '0' after 5 ns;

  -- Instantiate the design under test
   U_wrRdy : entity surf.Synchronizer
      generic map (
         TPD_G       => TPD_C,
         RST_ASYNC_G => RST_ASYNC_C,
         STAGES_G    => 2)
      port map (
         clk     => clk,
         rst     => rst,
         dataIn  => din,
         dataOut => dout);

  -- Generate the test stimulus
  stimulus: process begin

    -- Wait for the rst to be released before
    wait until (rst = '0');

    din <= '1';

    wait for 12 ns;
    din <= '0';

    wait for 22 ns;
    din <= '1';

    -- Testing complete

    wait;

  end process stimulus;

end architecture;