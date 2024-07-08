-- SparkPixS Wrapper

-- keeping it simple
-- maybe can create a dinArray equivalent in systemVerilog?
-- breaking down the din into individual std_logic_vectors works too though...

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpSparkPixSTop is
   generic(
      TPD_G                    : time      := 1 ns;
      RST_ASYNC_G              : boolean   := true;
      RST_POLARITY_G           : std_logic := '1';
      SERIALIZER_ID_G          : integer   := 0;
      SYNTHESIZE_G             : boolean   := true;
      GHDL_SIM_G               : boolean   := false;
      DATAFIFO_PIPE_G          : positive  := 1;
      STATUSFIFO_PIPE_G        : positive  := 1;
      DATAFIFO_FWFT_G          : boolean   := true;
      PIPELINE_BRIDGE_DATA_G   : boolean   := false;
      PIPELINE_BRIDGE_STATUS_G : boolean   := true;
      COLMANAGER_DEPTH_G       : integer   := 6;
      COLMANAGER_FULL_LVL_G    : integer   := 5;
      PGPADAPTER_DEPTH_G       : integer   := 6;
      PGPADAPTER_FULL_LVL_G    : integer   := 5;
      SUPER_FIFO_RD_DELAY_G    : natural   := 2;
      ARB_FIFO_RD_DELAY_G      : natural   := 1;
      ARB_DOUT_PIPE_G          : natural   := 1);
   port(
      -- General Interface
      sparseClk    : in  std_logic;
      pgpClk       : in  std_logic;
      rst          : in  std_logic;
      serSel       : in  std_logic_vector(3 downto 0);
      columnEnable : in  std_logic_vector(23 downto 0);
      -- Column Manager Interface
      -- dataIn
      din0         : in  std_logic_vector(19 downto 0);
      din1         : in  std_logic_vector(19 downto 0);
      din2         : in  std_logic_vector(19 downto 0);
      din3         : in  std_logic_vector(19 downto 0);
      din4         : in  std_logic_vector(19 downto 0);
      din5         : in  std_logic_vector(19 downto 0);
      din6         : in  std_logic_vector(19 downto 0);
      din7         : in  std_logic_vector(19 downto 0);
      din8         : in  std_logic_vector(19 downto 0);
      din9         : in  std_logic_vector(19 downto 0);
      din10        : in  std_logic_vector(19 downto 0);
      din11        : in  std_logic_vector(19 downto 0);
      din12        : in  std_logic_vector(19 downto 0);
      din13        : in  std_logic_vector(19 downto 0);
      din14        : in  std_logic_vector(19 downto 0);
      din15        : in  std_logic_vector(19 downto 0);
      din16        : in  std_logic_vector(19 downto 0);
      din17        : in  std_logic_vector(19 downto 0);
      din18        : in  std_logic_vector(19 downto 0);
      din19        : in  std_logic_vector(19 downto 0);
      din20        : in  std_logic_vector(19 downto 0);
      din21        : in  std_logic_vector(19 downto 0);
      din22        : in  std_logic_vector(19 downto 0);
      din23        : in  std_logic_vector(19 downto 0);
      -- flags
      tok          : in  std_logic_vector(23 downto 0);
      tokFb        : in  std_logic_vector(23 downto 0);
      ackN         : in  std_logic_vector(23 downto 0);
      wrEn         : in  std_logic_vector(23 downto 0);
      -- Pgp4TxLite Interface
      txReady      : in  std_logic;
      txValid      : out std_logic;
      txData       : out std_logic_vector(63 downto 0);
      txSof        : out std_logic;
      txEof        : out std_logic;
      txEofe       : out std_logic);
end entity Pix2PgpSparkPixSTop;

architecture rtl of Pix2PgpSparkPixSTop is

   signal din               : Pix2PgpSparseDinArray := (others => (others => '0'));
   signal columnEnableMuxed : std_logic_vector(23 downto 0);

begin

   -- Top Level
   U_Pix2PgpTop : entity pix2pgp.Pix2PgpTop
      generic map (
         TPD_G                    => TPD_G,
         RST_ASYNC_G              => RST_ASYNC_G,
         RST_POLARITY_G           => RST_POLARITY_G,
         GHDL_SIM_G               => GHDL_SIM_G,
         SYNTHESIZE_G             => SYNTHESIZE_G,
         DATAFIFO_FWFT_G          => DATAFIFO_FWFT_G,
         COLMANAGER_DEPTH_G       => COLMANAGER_DEPTH_G,
         COLMANAGER_FULL_LVL_G    => COLMANAGER_FULL_LVL_G,
         PGPADAPTER_DEPTH_G       => PGPADAPTER_DEPTH_G,
         PGPADAPTER_FULL_LVL_G    => PGPADAPTER_FULL_LVL_G,
         PIPELINE_BRIDGE_DATA_G   => PIPELINE_BRIDGE_DATA_G,
         PIPELINE_BRIDGE_STATUS_G => PIPELINE_BRIDGE_STATUS_G,
         DATAFIFO_PIPE_G          => DATAFIFO_PIPE_G,
         STATUSFIFO_PIPE_G        => STATUSFIFO_PIPE_G,
         SUPER_FIFO_RD_DELAY_G    => SUPER_FIFO_RD_DELAY_G,
         ARB_FIFO_RD_DELAY_G      => ARB_FIFO_RD_DELAY_G,
         ARB_DOUT_PIPE_G          => ARB_DOUT_PIPE_G)
      port map (
         -- General Interface
         sparseClk    => sparseClk,
         pgpClk       => pgpClk,
         rst          => rst,
         columnEnable => columnEnableMuxed,
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
         txEofe       => txEofe);

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
   process(pgpClk)
   begin
      if (rising_edge(pgpClk)) then
         if serSel = conv_std_logic_vector(SERIALIZER_ID_G, serSel'length) then
            columnEnableMuxed <= columnEnable;
         end if;
      end if;
   end process;

end architecture;