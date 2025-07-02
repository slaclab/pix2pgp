-- simple wrapper for the TopTb testbench;
-- includes a dummy verilog module in order to comply with some vcs versions...

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library pix2pgp;

entity Pix2PgpThriglavEmuTb is
   generic(
      TPD_G                     : time     := 1 ns;
      RST_ASYNC_G               : boolean  := true;
      RST_POLARITY_G            : std_logic:= '0';
      FPGA_SYNTH_G              : boolean  := false;
      PIPELINE_DATA_G           : boolean  := false;
      PIPELINE_STATUS_G         : boolean  := true;
      COLMANAGER_DATA_DEPTH_G   : integer  := 8;
      COLMANAGER_STATUS_DEPTH_G : integer  := 8;
      TIMEOUT_LIMIT_WIDTH_G     : positive := 12;
      ARB_DOUT_PIPE_G           : natural  := 1;
      DATAFIFO_PIPE_G           : natural  := 1;
      STATUSFIFO_PIPE_G         : natural  := 1;
      NUM_VC_G                  : natural  := 1
   );
end entity Pix2PgpThriglavEmuTb;

architecture test of Pix2PgpThriglavEmuTb is

   -- dummy verilog module for vcs (testbench has to be vhdl+verilog)
   component DummyModule
      port(
         clk     : in std_logic;
         rst     : in std_logic;
         inPort  : in std_logic;
         outPort : out std_logic);
   end component;

   constant CLK_PERIOD_C : time := 2 ns;

   signal clk   : std_logic := '0';
   signal rst   : std_logic := '0';

   begin

   ------
   -- UUT
   ------
   U_Uut : entity pix2pgp.Pix2PgpThriglavTopTb
      generic map(
         TPD_G                     => TPD_G,
         RST_ASYNC_G               => RST_ASYNC_G,
         RST_POLARITY_G            => RST_POLARITY_G,
         FPGA_SYNTH_G              => FPGA_SYNTH_G,
         DATAFIFO_PIPE_G           => DATAFIFO_PIPE_G,
         STATUSFIFO_PIPE_G         => STATUSFIFO_PIPE_G,
         PIPELINE_DATA_G           => PIPELINE_DATA_G,
         PIPELINE_STATUS_G         => PIPELINE_STATUS_G,
         COLMANAGER_DATA_DEPTH_G   => COLMANAGER_DATA_DEPTH_G,
         COLMANAGER_STATUS_DEPTH_G => COLMANAGER_STATUS_DEPTH_G,
         TIMEOUT_LIMIT_WIDTH_G     => TIMEOUT_LIMIT_WIDTH_G,
         NUM_VC_G                  => NUM_VC_G)
      port map(
         dummyIn => clk);

   -- dummy module for vcs (it has to be vhdl+verilog)
   Dummy_inst: DummyModule
      port map(
         clk     => clk,
         rst     => rst,
         inPort  => '0',
         outPort => open);

end architecture;
