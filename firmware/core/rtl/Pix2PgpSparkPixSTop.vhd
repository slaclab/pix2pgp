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
      TPD_G                      : time      := 1 ns;
      RST_ASYNC_G                : boolean   := true;
      RST_POLARITY_G             : std_logic := '0';
      PIPELINE_BRIDGE_DATA_G     : boolean   := false;
      PIPELINE_BRIDGE_STATUS_G   : boolean   := true;
      COLMANAGER_DATA_DEPTH_G    : integer   := 6;
      COLMANAGER_STATUS_DEPTH_G  : integer   := 4;
      ADAPTER_DEPTH_G            : integer   := 16;
      ADAPTER_AF_LVL_G           : integer   := 2;
      SUPER_FIFO_RD_DELAY_G      : natural   := 3;
      DATAFIFO_PIPE_G            : positive  := 1;
      STATUSFIFO_PIPE_G          : positive  := 1;
      ARB_DOUT_PIPE_G            : natural   := 1);
   port(
      -- General Interface
      sparseClk    : in  std_logic;
      pgpClk       : in  std_logic;
      sparseRst    : in  std_logic;
      pgpRst       : in  std_logic;
      sel          : in  std_logic;
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
      sof          : in  std_logic_vector(23 downto 0);
      eof          : in  std_logic_vector(23 downto 0);
      overOcc      : in  std_logic_vector(23 downto 0);
      pauseAck     : in  std_logic_vector(23 downto 0);
      wrEn         : in  std_logic_vector(23 downto 0);
      busy         : out std_logic_vector(23 downto 0);
      pause        : out std_logic_vector(23 downto 0);
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
         TPD_G                      => TPD_G,
         RST_ASYNC_G                => RST_ASYNC_G,
         RST_POLARITY_G             => RST_POLARITY_G,
         COLMANAGER_DATA_DEPTH_G    => COLMANAGER_DATA_DEPTH_G,
         COLMANAGER_STATUS_DEPTH_G  => COLMANAGER_STATUS_DEPTH_G,
         ADAPTER_DEPTH_G            => ADAPTER_DEPTH_G,
         ADAPTER_AF_LVL_G           => ADAPTER_AF_LVL_G,
         PIPELINE_BRIDGE_DATA_G     => PIPELINE_BRIDGE_DATA_G,
         PIPELINE_BRIDGE_STATUS_G   => PIPELINE_BRIDGE_STATUS_G,
         DATAFIFO_PIPE_G            => DATAFIFO_PIPE_G,
         STATUSFIFO_PIPE_G          => STATUSFIFO_PIPE_G,
         SUPER_FIFO_RD_DELAY_G      => SUPER_FIFO_RD_DELAY_G,
         ARB_DOUT_PIPE_G            => ARB_DOUT_PIPE_G)
      port map (
         -- General Interface
         sparseClk    => sparseClk,
         pgpClk       => pgpClk,
         sparseRst    => sparseRst,
         pgpRst       => pgpRst,
         columnEnable => columnEnableMuxed,
         -- Column Manager Interface
         sof          => sof,
         eof          => eof,
         overOcc      => overOcc,
         pauseAck     => pauseAck,
         wrEn         => wrEn,
         din          => din,
         busy         => busy,
         pause        => pause,
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
         if sel = '1' then
            columnEnableMuxed <= columnEnable;
         end if;
      end if;
   end process;

end architecture;