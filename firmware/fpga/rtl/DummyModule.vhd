-- Dummy Module

-- ... to test if it can be synthesized by the ASIC tools

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

library surf;

entity DummyModule is
   generic(
      TPD_G          : time      := 1 ns;
      RST_ASYNC_G    : boolean   := True;
      RST_POLARITY_G : std_logic := '1');
   port(
      pgpClk    : in  std_logic;
      rst       : in  std_logic;
      tok0      : in  std_logic;
      tok1      : in  std_logic;
      txEofe    : out std_logic;
      txSof     : out std_logic);
end entity DummyModule;

architecture rtl of DummyModule is

   -- constant TPD_G          : time := 1 ns;
   -- constant RST_ASYNC_G    : boolean := True;
   -- constant RST_POLARITY_G : std_logic := '1';

begin

   seq : process (pgpClk, rst, tok0) is
   begin
      if (RST_ASYNC_G and rst = not(RST_POLARITY_G)) then
         txEofe <= tok0 after TPD_G;
      elsif (RST_ASYNC_G and rst = RST_POLARITY_G) then
         txEofe <= '0' after TPD_G;
      elsif rising_edge(pgpClk) then
         if (rst = not(RST_POLARITY_G)) then
            txEofe <= tok0 after TPD_G;
         else
            txEofe <= '0' after TPD_G;
         end if;
      end if;
   end process seq;

   U_testSurf : entity surf.Synchronizer
      generic map (
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         RST_POLARITY_G => RST_POLARITY_G,
         STAGES_G       => 2)
      port map (
         clk     => pgpClk,
         rst     => rst,
         dataIn  => tok1,
         dataOut => txSof);

end architecture;