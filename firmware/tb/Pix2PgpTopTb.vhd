library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

-- required for writing/reading std_logic etc.
use std.textio.all;
use ieee.std_logic_textio.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.SsiPkg.all;
use surf.Pgp4Pkg.all;
use surf.AxiStreamPacketizer2Pkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpTopTb is
   generic(
      TPD_G                    : time     := 1 ns;
      RST_ASYNC_G              : boolean  := True;
      RST_POLARITY_G           : sl       := '1';
      GHDL_SIM_G               : boolean  := True;
      DATAFIFO_PIPE_G          : positive := 2;
      STATUSFIFO_PIPE_G        : positive := 2;
      DATAFIFO_FWFT_G          : boolean  := True;
      PIPELINE_BRIDGE_DATA_G   : boolean  := False;
      PIPELINE_BRIDGE_STATUS_G : boolean  := True;
      COLMANAGER_FULL_LVL_G    : natural  := 3;
      PGPADAPTER_FULL_LVL_G    : natural  := 3;
      SUPER_FIFO_RD_DELAY_G    : natural  := 3;
      ARB_FIFO_RD_DELAY_G      : natural  := 1;
      ARB_DOUT_PIPE_G          : natural  := 2;
      NUM_VC_G                 : natural  := 1
   );
end entity Pix2PgpTopTb;

architecture test of Pix2PgpTopTb is

   constant CLK_PERIOD_C : time := 5.384 ns;

   signal clk   : sl := '0';
   signal rst   : sl := '1';
   signal sro   : sl := '0';

   signal tok   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '1');
   signal tokFb : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal ackN  : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '1');
   signal wrEn  : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal pause : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal din   : Pix2PgpSparseDinArray := (others => (others => '0'));

   type hitLenArray is array (0 to NUM_OF_COL_MANAGERS_C-1) of slv(9 downto 0);
   signal hitLen  : hitLenArray := (others => (others => '0'));
   signal overOcc : sl := '0';

   signal pgpValid  : sl := '0';
   signal pgpData   : slv(39 downto 0) := (others => '0');

begin

  -- rst and clk
  clk <= not clk after CLK_PERIOD_C - TPD_G;
  rst <= '1', '0' after CLK_PERIOD_C*200;

  -- Generate the test stimulus
  stimulus: process begin

    -- Wait for the rst to be released before
    wait until (rst = '0');
    for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
      -- only even number of events please
      hitLen(col) <= toSlv(0, hitLen(col)'length);
    end loop;

    wait for CLK_PERIOD_C*4200; -- extend wait to align pgp protocol
      sro <= '1';
    wait for CLK_PERIOD_C*2;
      sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  hitLen(5) <= toSlv(3, hitLen(5)'length);
    --  hitLen(6) <= toSlv(1, hitLen(6)'length);
    --  hitLen(7) <= toSlv(2, hitLen(7)'length);
    --  hitLen(8) <= toSlv(5, hitLen(8)'length);
    --  hitLen(9) <= toSlv(4, hitLen(9)'length);
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  hitLen(5) <= toSlv(8, hitLen(5)'length);
    --  hitLen(6) <= toSlv(6, hitLen(6)'length);
    --  hitLen(7) <= toSlv(3, hitLen(7)'length);
    --  hitLen(8) <= toSlv(5, hitLen(8)'length);
    --  hitLen(9) <= toSlv(1, hitLen(9)'length);
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
    --     hitLen(col) <= toSlv(5, hitLen(col)'length);
    --  end loop;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    wait for CLK_PERIOD_C*186;
      hitLen(3) <= toSlv(24, hitLen(5)'length);
      hitLen(4) <= toSlv(2, hitLen(5)'length);
      hitLen(5) <= toSlv(8, hitLen(5)'length);
      hitLen(6) <= toSlv(6, hitLen(6)'length);
      hitLen(7) <= toSlv(24, hitLen(7)'length);
      hitLen(8) <= toSlv(5, hitLen(8)'length);
      hitLen(9) <= toSlv(1, hitLen(9)'length);
      sro  <= '1';
    wait for CLK_PERIOD_C*2;
      sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
    --    hitLen(col) <= toSlv(0, hitLen(col)'length);
    --  end loop;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    --wait for CLK_PERIOD_C*186;
    --  sro  <= '1';
    --wait for CLK_PERIOD_C*2;
    --  sro  <= '0';

    -- do not touch
    wait;
    -- do not touch

  end process stimulus;

  writeDataProcess: process(clk)

    -- variables for file-writing
    file myFile  : text open write_mode is "pix2pgpRxDataDump.dat";
    variable row : line;

  begin
    if (rising_edge(clk)) then
      -- first check if the rst is low
      if (rst = '0') then
        -- then check if the valid flag is high
        if pgpValid = '1' then
          -- syntax: write(row_variable,what_to_write,
          -- justification(right/left), trailing_whitespaces);
          -- writeline(file_variable, row_variable);
          hwrite(row, pgpData, right, 0);
          writeline(myFile,row);
        end if;
      end if;
    end if;
  end process;

   --------
   -- Pixel
   --------
   GEN_DUMMY_PIXEL: for col in 0 to NUM_OF_COL_MANAGERS_C-1 generate
      U_DummyPixel : entity pix2pgp.DummyPixel
         generic map(
            TPD_G        => TPD_G,
            RST_ASYNC_G  => RST_ASYNC_G,
            WAIT_FB_G    => 2,
            WAIT_ACKN_G  => 2,
            WAIT_WREN_G  => 2,
            COL_ID_G     => col)
         port map(
            clk     => clk,
            rst     => rst,
            sro     => sro,
            pause   => pause(col),
            hitLen  => hitLen(col),
            tok     => tok(col),
            tokFb   => tokFb(col),
            ackN    => ackN(col),
            wrEn    => wrEn(col),
            dout    => din(col));
   end generate GEN_DUMMY_PIXEL;

   ------
   -- UUT
   ------
   U_Uut : entity pix2pgp.Pix2PgpTb
      generic map(
         TPD_G                    => TPD_G,
         RST_ASYNC_G              => RST_ASYNC_G,
         RST_POLARITY_G           => RST_POLARITY_G,
         GHDL_SIM_G               => GHDL_SIM_G,
         DATAFIFO_PIPE_G          => DATAFIFO_PIPE_G,
         STATUSFIFO_PIPE_G        => STATUSFIFO_PIPE_G,
         DATAFIFO_FWFT_G          => DATAFIFO_FWFT_G,
         PIPELINE_BRIDGE_DATA_G   => PIPELINE_BRIDGE_DATA_G,
         PIPELINE_BRIDGE_STATUS_G => PIPELINE_BRIDGE_STATUS_G,
         COLMANAGER_FULL_LVL_G    => COLMANAGER_FULL_LVL_G,
         PGPADAPTER_FULL_LVL_G    => PGPADAPTER_FULL_LVL_G,
         SUPER_FIFO_RD_DELAY_G    => SUPER_FIFO_RD_DELAY_G,
         ARB_FIFO_RD_DELAY_G      => ARB_FIFO_RD_DELAY_G,
         ARB_DOUT_PIPE_G          => ARB_DOUT_PIPE_G,
         NUM_VC_G                 => NUM_VC_G)
      port map(
         clk      => clk,
         rst      => rst,
         sro      => sro,
         pause    => pause,
         tok      => tok,
         tokFb    => tokFb,
         ackN     => ackN,
         wrEn     => wrEn,
         din      => din,
         pgpValid => pgpValid,
         pgpData  => pgpData);

end architecture;
