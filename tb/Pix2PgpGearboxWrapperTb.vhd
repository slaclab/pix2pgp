library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;


entity Pix2PgpGearboxWrapperTb is
end entity Pix2PgpGearboxWrapperTb;

architecture test of Pix2PgpGearboxWrapperTb is

   constant TPD_C       : time    := 1 ns;
   constant RST_ASYNC_C : boolean := true;

   signal clk  : sl := '0';
   signal rst  : sl := '1';

   signal arbiterDvalid        : sl := '0';
   signal arbiterDout          : slv(ARB_GEARBOX_INPUT_WIDTH_G-1 downto 0) := (others => '0');
   signal arbiterGearboxReady  : sl := '0';

   signal pgpReady             : sl := '0';
   signal pgpValid             : sl := '0';
   signal pgpData              : slv(63 downto 0) := (others => '0');

   signal test                 : sl := '0';


   constant CLK_PERIOD_C : time := 10 ns;

begin


  -- rst and clk
  clk <= not clk after CLK_PERIOD_C - TPD_C;
  rst <= '1', '0' after CLK_PERIOD_C*20;

  -- Instantiate the design under test
   U_DUT : entity pix2pgp.Pix2PgpGearboxWrapper
      generic map (
         TPD_G       => TPD_C,
         RST_ASYNC_G => RST_ASYNC_C)
      port map (
         -- General Interface
         pgpClk              => clk,
         rst                 => rst,
         -- Arbiter Interface
         arbiterDvalid       => arbiterDvalid,
         arbiterDout         => arbiterDout,
         arbiterGearboxReady => arbiterGearboxReady,
         -- PGP Interface
         pgpValid            => pgpValid,
         pgpData             => pgpData,
         pgpReady            => '1');

  -- Generate the test stimulus
  stimulus: process begin

    -- Wait for the rst to be released before
    wait until (rst = '0');
    -- Testing complete

    wait;

  end process stimulus;

  proc: process(clk)
  begin
   if rising_edge(clk) then
      if rst = '0' then
         if allBits(arbiterDout, '0') and arbiterDvalid = '0' then
            arbiterDvalid <= '1';
         elsif arbiterDout = toSlv(31, arbiterDout'length) then
            arbiterDvalid <= '0';
         elsif allBits(arbiterDout, '1') then
            arbiterDout      <= (others => '1');
            arbiterDvalid <= '0';
         else
            arbiterDout      <= arbiterDout + 1;
         end if;
      end if;
   end if;
  end process;

end architecture;