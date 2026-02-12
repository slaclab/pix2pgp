-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Model for SparkPix-T column
--
-------------------------------------------------------------------------------
-- This file is part of 'Pix2Pgp'.
-- It is subject to the license terms in the LICENSE.txt file found in the
-- top-level directory of this distribution and at:
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
-- No part of 'Pix2Pgp', including this file,
-- may be copied, modified, propagated, or distributed except according to
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

library surf;
use surf.StdRtlPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpAsicPkg.all;
use pix2pgp.Pix2PgpPkg.all;

entity SparkPixTColumnModel is
    generic (
        TPD_G           : time     := 1 ns;
        RST_ASYNC_G     : boolean  := true;
        RST_POLARITY_G  : sl       := '1';
        WAIT_WREN_G     : positive := 4;
        IGNORE_ERO_G    : boolean  := false;
        MAX_ROW_G       : natural  := 168;
        SER_ID_G        : natural  := 0;
        COL_ID_G        : natural  := 0);
    port (
        clk        : in  sl;
        df_reset_n : in  sl := not RST_POLARITY_G;
        sro        : in  sl; -- acts as a SOF
        ero        : in  sl; -- acts as an EOF
        hitLen     : in  slv(15 downto 0);
        pause      : in  sl;
        pauseAck   : out sl;
        sof        : out sl;
        eof        : out sl;
        overOcc    : out sl;
        wrEn       : out sl;
        dout       : out slv(31 downto 0));
end entity;

architecture tb of SparkPixTColumnModel is

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
      ero      : sl;
      hitLen   : slv(15 downto 0);
      wrEn     : sl;
      pause    : sl;
      pauseAck : sl;
      overOcc  : sl;
      dout     : slv(31 downto 0);
      --
      waitCnt  : natural range 0 to 1023;
      hitCnt   : slv(7 downto 0);
      hitLenCnt: slv(15 downto 0);
      trgCnt   : slv(7 downto 0);
      state    : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      sof      => '0',
      eof      => '0',
      sro      => '0',
      ero      => '0',
      hitLen   => (others => '0'),
      wrEn     => '0',
      pause    => '0',
      pauseAck => '0',
      overOcc  => '0',
      dout     => (others => '0'),
      --
      waitCnt  => 0,
      hitCnt   => (others => '0'),
      hitLenCnt=> toSlv(1, 16),
      trgCnt   => (others => '0'),
      state    => IDLE_S
   );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

comb : process (df_reset_n, r, hitLen, ero, sro, pause) is

      variable v       : RegType;
      variable rowAddr : slv(7 downto 0);

   begin
      -- Latch the current value
      v := r;

      -- Get the inputs
      v.sro      := sro;
      v.ero      := ero;
      v.pause    := pause;
      v.pauseAck := r.pause;

      -- defaults
      v.sof     := '0';
      v.eof     := '0';
      v.overOcc := '0';
      v.wrEn    := '0';
      rowAddr   := resize((r.trgCnt + r.hitCnt), 8);
      v.dout(31 downto 24) := rowAddr;
      v.dout(23 downto 16) := toSlv((COL_ID_G+1)*10, 8); -- 25 x 10 = 250 < 255
      v.dout(15 downto  8) := toSlv((COL_ID_G+1)*1,  8); -- 25 x 10 = 250 < 255
      v.dout(7  downto  0) := toSlv((COL_ID_G+1)*10, 8); -- 25 x 10 = 250 < 255

      if (v.sro = '1' and r.sro = '0') then -- reset everything
         v.trgCnt := r.trgCnt + 1;
         v.state  := IDLE_S;
         if r.state /= IDLE_S or r.pause = '1' then
            v.overOcc := '1';
         end if;
      end if;

      if (v.ero = '1' and r.ero = '0' and r.state /= WAIT_TRG_S) then
         v.state  := IDLE_S;
         if r.state /= IDLE_S or r.pause = '1' then
            v.overOcc := '1';
         end if;
      end if;

      case r.state is

      ----------------------------------------------------------------------
      when IDLE_S =>
         -- only register the hitLen if idle
         v.hitLen    := hitLen;
         v.waitCnt   := 0;
         v.hitCnt    := (others => '0');
         v.hitLenCnt := toSlv(1, 16);

         if (r.sro = '1' and v.pause = '0') then
            v.sof := '1';
            if (r.hitLen > 0) then
               v.state := WAIT_WREN_S;
            else
               v.state := WAIT_TRG_S;
            end if;
         end if;

         ----------------------------------------------------------------------
         when WAIT_WREN_S =>
             if (v.pause = '0') then
                v.waitCnt := r.waitCnt + 1;
               if (v.waitCnt = WAIT_WREN_G) then
                  v.waitCnt := 0;
                  v.state   := ISSUE_WREN_S;
               end if;
             end if;

         ----------------------------------------------------------------------
         when ISSUE_WREN_S =>
            if (v.pause = '0') then
               v.waitCnt := r.waitCnt + 1;
               if (v.waitCnt = WAIT_WREN_G) then
                  v.wrEn    := '1';
                  v.waitCnt := 0;
                  if (r.hitLenCnt = r.hitLen) then
                     v.state := WAIT_TRG_S;
                  else
                     if rowAddr >= MAX_ROW_G then
                        v.hitCnt := (others => '0');
                        v.trgCnt := (others => '0');
                     else
                        v.hitCnt := r.hitCnt + 1;
                     end if;

                     v.hitLenCnt := r.hitLenCnt + 1;
                     v.state     := WAIT_WREN_S;
                  end if;
               end if;
            end if;

         ----------------------------------------------------------------------
         when WAIT_TRG_S =>
            if (v.pause = '0') then
               if (v.ero = '1' and r.ero = '0' and IGNORE_ERO_G = false) then
                  v.eof   := '1';
                  v.state := IDLE_S;
               elsif (IGNORE_ERO_G = true) then
                  v.eof   := '1';
                  v.state := IDLE_S;
               end if;
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
