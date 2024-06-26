library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;


entity Pix2PgpArbiterTb is
end entity Pix2PgpArbiterTb;

architecture test of Pix2PgpArbiterTb is

   constant TPD_C       : time    := 0 ns;
   constant RST_ASYNC_C : boolean := true;
   constant ARB_FIFO_RD_DELAY_C      : positive := 3; -- standalone/generic FIFO
   --constant ARB_FIFO_RD_DELAY_C      : natural := ????; -- designware FIFO

   type dinArrayType is array (0 to NUM_OF_COL_MANAGERS_C-1) of slv(SPARSE_DWIDTH_C-1 downto 0);
   type doutArrayType is array (0 to NUM_OF_COL_MANAGERS_C-1) of slv(DATABUS_DWIDTH_C-1 downto 0);

   signal clk             : sl := '0';
   signal rst             : sl := '1';

   signal dataBusSel      : Pix2PgpDataBusType := DEFAULT_PIX2PGP_DATABUS_C;
   signal dataRd          : sl := '0';
   signal colSel          : slv(BITMAX_COL_MANAGERS_C downto 0) := (others => '0');
   signal columnEnable    : slv(BITMAX_COL_MANAGERS_C downto 0) := (others => '1');

   signal arbStart        : sl := '0';
   signal statusFifoError : sl := '0';
   signal dataFifoError   : sl := '0';
   signal overOccError    : sl := '0';
   signal alignError      : sl := '0';
   signal colBitmask      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0)  := (others => '0');
   signal trgNum          : slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0) := (others => '0');
   signal arbBusy         : sl := '0';
   --
   signal arbValid        : sl := '0';
   signal arbDout         : slv(DATABUS_DWIDTH_C-1 downto 0) := (others => '0');
   --
   signal wrEn            : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal dinArray        : dinArrayType := (others => (others => '0'));
   signal empty           : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal rdEn            : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal doutArray       : doutArrayType := (others => (others => '0'));

   signal fillFifos       : sl := '0';
   signal fillCnt         : natural range 0 to 1023;

   constant CLK_PERIOD_C  : time := 10 ns;

   signal statusBus       : Pix2PgpStatusBusArray := (others => DEFAULT_PIX2PGP_STATUSBUS_C);
   signal dataBus         : Pix2PgpDataBusArray   := (others => DEFAULT_PIX2PGP_DATABUS_C);

   signal statusBusSel    : Pix2PgpStatusBusType := DEFAULT_PIX2PGP_STATUSBUS_C;


begin

  -- rst and clk
  clk <= not clk after CLK_PERIOD_C - TPD_C;
  rst <= '1', '0' after CLK_PERIOD_C*20;


  -- Instantiate the design under test
   U_DUT : entity pix2pgp.Pix2PgpArbiter
      generic map (
         TPD_G           => TPD_C,
         RST_ASYNC_G     => RST_ASYNC_C,
         FIFO_RD_DELAY_G => ARB_FIFO_RD_DELAY_C)
      port map (
         -- General Interface
         pgpClk          => clk,
         rst             => rst,
         -- Column Manager Interface
         dataLenSel      => statusBusSel.dataLen,
         dataBusSel      => dataBusSel,
         dataRd          => dataRd,
         colSel          => colSel,
         -- Column Supervisor Interface
         arbStart        => arbStart,
         statusFifoError => statusFifoError,
         dataFifoError   => dataFifoError,
         overOccError    => overOccError,
         alignError      => alignError,
         colBitmask      => colBitmask,
         trgNum          => trgNum,
         arbBusy         => arbBusy,
         -- Gearbox Interface
         arbValid        => arbValid,
         arbDout         => arbDout);

  -- Generate the test stimulus
  stimulus: process begin

    -- Wait for the rst to be released before
    wait until (rst = '0');

    wait for CLK_PERIOD_C;
    for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
      -- only even number of events please
      statusBus(col).dataLen <= toSlv(4, statusBus(col).dataLen'length);
    end loop;

    wait for CLK_PERIOD_C*300;
      fillFifos <= '1';

    wait for CLK_PERIOD_C*320;
      fillFifos  <= '0';
      colBitmask <= x"ffffff";
      trgNum     <= toSlv(1, trgNum'length);

   wait for CLK_PERIOD_C*10;
      arbStart <= '1';

   wait for CLK_PERIOD_C*5;
      arbStart <= '0';

    wait;

  end process stimulus;

   GEN_DATA_FIFO: for fifo in 0 to NUM_OF_COL_MANAGERS_C-1 generate
      ------------------
      -- Dummy Data FIFO
      ------------------
      U_DataFifo : entity pix2pgp.Pix2PgpFifoWrapper
         generic map (
            TPD_G           => TPD_C,
            RST_ASYNC_G     => RST_ASYNC_C,
            GEN_SYNC_FIFO_G => false,
            WR_DATA_WIDTH_G => SPARSE_DWIDTH_C,
            RD_DATA_WIDTH_G => DATABUS_DWIDTH_C,
            ADDR_WIDTH_G    => 4,
            GHDL_SIM_G      => true)
         port map (
            -- Resets
            rst    => rst,
            -- Write Interface
            wrClk  => clk,
            wrEn   => wrEn(fifo),
            fullWr => open,
            din    => dinArray(fifo),
            -- Read Interface
            rdClk  => clk,
            empty  => empty(fifo),
            rdEn   => rdEn(fifo),
            fullRd => open,
            dout   => doutArray(fifo));

      dataBus(fifo).data <= doutArray(fifo);
   end generate GEN_DATA_FIFO;

   U_Bridge : entity pix2pgp.Pix2PgpBridge
      port map(
         -- General Interface
         pgpClk        => clk,
         columnEnable  => columnEnable,
         -- Column Manager Interface
         statusBusIn   => statusBus,
         dataBusIn     => dataBus,
         statusRdOut   => open,
         dataRdOut     => rdEn,
         -- Column Supervisor Interface
         statusRdIn    => '0',
         statusBusGlbl => open,
         -- Arbiter Interface
         dataRdIn      => dataRd,
         colSel        => colSel,
         statusBusSel  => statusBusSel,
         dataBusSel    => dataBusSel);

  proc: process(clk)
  begin
   if rising_edge(clk) then
      if fillFifos = '1' then

         if fillCnt < 800 then
            fillCnt <= fillCnt + 1;
         else
            fillCnt <= 0;
         end if;
         for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
            if fillCnt < unsigned(statusBus(col).dataLen) then
               wrEn(col)      <= '1';
               dinArray(col)(7 downto 0)  <= toSlv(fillCnt+1, dinArray(col)(7 downto 0)'length);
               dinArray(col)(15 downto 8) <= toSlv(col, dinArray(col)(15 downto 8)'length);
               dinArray(col)(19 downto 16)<= x"0";
            else
               wrEn(col)     <= '0';
               dinArray(col) <= (others => '0');
            end if;

         end loop;
      else
      end if;
   end if;
  end process;

end architecture;