-- Dummy Module

-- ... to test if it can be synthesized by the ASIC tools

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity DummyModule is
   generic(
      TPD_G          : time      := 1 ns;
      RST_POLARITY_G : std_logic := '1';
      RST_ASYNC_G    : boolean := True);
   port(
      pgpClk    : in  std_logic;
      rst       : in  std_logic;
      tok       : in  std_logic;
      txEofe    : out std_logic);
end entity DummyModule;

architecture rtl of DummyModule is

   -- constant TPD_G          : time := 1 ns;
   -- constant RST_POLARITY_G : std_logic := '1';
   -- constant RST_ASYNC_G    : boolean := True;

begin

   seq : process (pgpClk, rst) is
   begin
      if (RST_ASYNC_G and rst = RST_POLARITY_G) then
         txEofe <= tok after TPD_G;
      elsif rising_edge(pgpClk) then
         txEofe <= tok after TPD_G;
      end if;
   end process seq;

end architecture;