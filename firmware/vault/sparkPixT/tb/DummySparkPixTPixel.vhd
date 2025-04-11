-- only for simulation

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

library surf;
use surf.StdRtlPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity DummySparkPixTPixel is
    generic (
        TPD_G           : time     := 1 ns;
        RST_ASYNC_G     : boolean  := true;
        RST_POLARITY_G  : sl       := '1';
        WAIT_WREN_G     : positive := 4;
        COL_ID_G        : natural  := 0);
    port (
        clk        : in  sl;
        df_reset_n : in  sl := not RST_POLARITY_G;
        sro        : in  sl; -- acts as a SOF
        trigger    : in  sl; -- acts as an EOF
        hitLen     : in  slv(15 downto 0);
        pause      : in  sl;
        pauseAck   : out sl;
        sof        : out sl;
        eof        : out sl;
        overOcc    : out sl;
        wrEn       : out sl;
        dout       : out slv(31 downto 0));
end entity;

architecture tb of DummySparkPixTPixel is

    type StateType is (
      IDLE_S,
      WAIT_WREN_S,
      ISSUE_WREN_S,
      WAIT_TRG_S
   );

   type RegType is record
      sof      : sl;
      eof      : sl;
      sro      : sl;
      trigger  : sl;
      hitLen   : slv(15 downto 0);
      wrEn     : sl;
      pause    : sl;
      pauseAck : sl;
      overOcc  : sl;
      dout     : slv(31 downto 0);
      --
      waitCnt  : natural range 0 to 1023;
      hitCnt   : slv(15 downto 0);
      trgCnt   : slv(5 downto 0);
      state    : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      sof      => '0',
      eof      => '0',
      sro      => '0',
      trigger  => '0',
      hitLen   => (others => '0'),
      wrEn     => '0',
      pause    => '0',
      pauseAck => '0',
      overOcc  => '0',
      dout     => (others => '0'),
      --
      waitCnt  => 0,
      hitCnt   => toSlv(1, 16),
      trgCnt   => (others => '1'), -- so that it rolls-over to zero on first trigger
      state    => IDLE_S
   );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

comb : process (df_reset_n, r, hitLen, trigger, sro, pause) is

      variable v : RegType;

   begin
      -- Latch the current value
      v := r;

      -- Get the inputs
      v.sro     := sro;
      v.trigger := trigger;
      v.pause   := pause;

      -- defaults
      v.sof     := '0';
      v.eof     := '0';
      v.overOcc := '0';
      v.wrEn    := '0';

      if (v.sro = '1' and r.sro = '0') then -- reset everything
         v.trgCnt := r.trgCnt + 1;
         v.state  := IDLE_S;
         if r.state /= IDLE_S or r.pause = '1' then
            v.overOcc := '1';
         end if;
      end if;

      case r.state is

      ----------------------------------------------------------------------
      when IDLE_S =>
         -- only register the hitLen if idle
         v.hitLen   := hitLen;
         v.waitCnt  := 0;
         v.hitCnt   := toSlv(1, 16);
         v.pauseAck := r.pause;

         if (r.sro = '1' and v.pause = '0') then
            v.sof                := '1';
            v.dout(31 downto 26) := r.trgCnt;
            if (r.hitLen > 0) then
               v.state := WAIT_WREN_S;
            else
               v.state := WAIT_TRG_S;
            end if;
         end if;

         ----------------------------------------------------------------------
         when WAIT_WREN_S =>
             v.pauseAck := r.pause;

             if (v.pause = '0') then
                v.waitCnt := r.waitCnt + 1;
               if (v.waitCnt = WAIT_WREN_G) then
                  v.waitCnt := 0;
                  v.state   := ISSUE_WREN_S;
               end if;
             end if;

         ----------------------------------------------------------------------
         when ISSUE_WREN_S =>
            v.waitCnt := r.waitCnt + 1;
            if (v.waitCnt = WAIT_WREN_G) then
               --v.dout(31 downto 28) := r.trgCnt; -- issued on IDLE_S
               v.dout(25 downto 16) := toSlv(COL_ID_G, v.dout(25 downto 16)'length);
               v.dout(15 downto 0)  := r.hitCnt;
               v.waitCnt            := 0;
               v.wrEn               := '1';
               if (r.hitCnt = r.hitLen) then
                  v.state := WAIT_TRG_S;
               else
                  v.hitCnt := r.hitCnt + 1;
                  v.state  := WAIT_WREN_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         when WAIT_TRG_S =>
            v.pauseAck := r.pause;
            if (v.trigger = '1' and r.trigger = '0' and v.pause = '0') then
               v.eof   := '1';
               v.state := IDLE_S;
            end if;
      end case;

      -- General Outputs
      pauseAck <= r.pauseAck;
      wrEn     <= r.wrEn;
      dout     <= r.dout;
      sof      <= r.sof;
      eof      <= r.eof;
      overOcc  <= r.overOcc;

      ----------------------------------------------------------------------

      -- Reset
      if (RST_ASYNC_G = false and df_reset_n = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (clk, df_reset_n) is
   begin
      if (RST_ASYNC_G and df_reset_n = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif (rising_edge(clk)) then
         r <= rin after TPD_G;
      end if;
   end process seq;

end tb;
