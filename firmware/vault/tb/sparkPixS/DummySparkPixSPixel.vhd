-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Dummy SparkPix-S Pixel
--              Accepts the 'start/trigger' and 'pulse' control signals,
--              and outputs the relevant info to tixel_BE
--
-------------------------------------------------------------------------------
-- This file is part of 'EPIX HR Firmware'.
-- It is subject to the license terms in the LICENSE.txt file found in the
-- top-level directory of this distribution and at:
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
-- No part of 'EPIX HR Firmware', including this file,
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
use pix2pgp.Pix2PgpPkg.all;

entity DummySparkPixSPixel is
   generic (
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1';    -- '1' for active HIGH reset, '0' for active LOW reset
      WAIT_FB_G      : natural := 2; -- 2 cycles
      WAIT_ACKN_G    : natural := 2;
      WAIT_WREN_G    : natural := 3;
      COL_ID_G       : natural := 0);
   port (
      clk      : in  sl;
      rst      : in  sl := not RST_POLARITY_G;
      sro      : in  sl;
      pause    : in  sl;
      hitLen   : in  slv(9 downto 0);
      pauseAck : out sl;
      tok      : out sl;
      tokFb    : out sl;
      ackN     : out sl;
      wrEn     : out sl;
      dout     : out slv(19 downto 0));
end DummySparkPixSPixel;

architecture rtl of DummySparkPixSPixel is

   type StateType is (
      IDLE_S,
      ISSUE_ACKN_S,
      WAIT_ISSUE_FB_S,
      ISSUE_WREN_S
   );

   type RegType is record
      sro     : sl;
      hitLen  : slv(9 downto 0);
      tok     : sl;
      tokFb   : sl;
      ackN    : sl;
      wrEn    : sl;
      pause   : sl;
      busy    : sl;
      pauseAck: sl;
      dout    : slv(19 downto 0);
      --
      waitCnt : natural range 0 to 1023;
      ackCnt  : natural range 0 to 1023;
      hitCnt  : slv(9 downto 0);
      trgCnt  : slv(3 downto 0);
      state   : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      sro     => '0',
      hitLen  => (others => '0'),
      tok     => '1',
      tokFb   => '0',
      ackN    => '1',
      wrEn    => '0',
      pause   => '0',
      busy    => '0',
      pauseAck=> '0',
      dout    => (others => '0'),
      --
      waitCnt => 0,
      ackCnt  => 0,
      hitCnt  => toSlv(1, 10),
      trgCnt  => (others => '1'), -- so that it rolls-over to zero on first trigger
      state   => IDLE_S
   );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

comb : process (rst, r, hitLen, sro, pause) is

      variable v : RegType;

   begin
      -- Latch the current value
      v := r;

      -- Get the inputs
      v.sro     := sro;
      v.pause   := pause;

      -- defaults
      v.tok  := '1';
      v.ackN := '1';
      v.wrEn := '0';

      if (v.sro = '1') then -- reset everything
         v.tok    := '0';
         v.trgCnt := r.trgCnt + 1;
         v.state  := IDLE_S;
      end if;

      case r.state is

         ----------------------------------------------------------------------
         when IDLE_S =>
            -- only register the hitLen if idle
            v.hitLen   := hitLen;
            v.tokFb    := '1';
            v.waitCnt  := 0;
            v.hitCnt   := toSlv(1, 10);
            v.ackCnt   := 0;
            v.busy     := '0';
            v.pauseAck := '0';

            if (r.sro = '1') then
               v.tokFb := '0';
               v.busy  := '1';
               v.dout(19 downto 16) := r.trgCnt;
               if (r.hitLen > 0) then
                  v.state := ISSUE_ACKN_S;
               else
                  v.state := WAIT_ISSUE_FB_S;
               end if;
            end if;

            ----------------------------------------------------------------------
            when ISSUE_ACKN_S =>
               v.pauseAck := r.pause;
               if (v.pause = '0') then
                  v.waitCnt := r.waitCnt + 1;
                  if (v.waitCnt = WAIT_ACKN_G) then
                     v.ackN    := '0';
                     v.waitCnt := 0;
                     v.ackCnt  := r.ackCnt + 1;
                     v.state   := ISSUE_WREN_S;
                  end if;
               end if;

            ----------------------------------------------------------------------
            when ISSUE_WREN_S =>
               v.pauseAck := r.pause;
               if (v.pause = '0') then
                  v.waitCnt := r.waitCnt + 1;
                  if (v.waitCnt = WAIT_WREN_G) then
                     v.wrEn               := '1';
                     v.dout(9 downto 0)   := r.hitCnt;
                     v.dout(15 downto 10)  := toSlv(COL_ID_G, v.dout(15 downto 10)'length);
                     --v.dout(19 downto 16) := r.trgCnt;
                     v.waitCnt := 0;
                     if (r.ackCnt = unsigned(r.hitLen)) then
                        v.state := WAIT_ISSUE_FB_S;
                     else
                        v.hitCnt := r.hitCnt + 1;
                        v.state  := ISSUE_ACKN_S;
                     end if;
                  end if;
               end if;

            ----------------------------------------------------------------------
            when WAIT_ISSUE_FB_S =>
               v.pauseAck := r.pause;
               if (v.pause = '0') then
                     v.waitCnt := r.waitCnt + 1;
                  if (r.waitCnt = WAIT_FB_G) then
                     v.state := IDLE_S;
                  end if;
               end if;
      end case;

      -- General Outputs
      tok    <= r.tok;
      tokFb  <= r.tokFb;
      ackN   <= r.ackN;
      wrEn   <= r.wrEn;
      dout   <= r.dout;
      pauseAck <= r.pauseAck;

      ----------------------------------------------------------------------

      -- Reset
      if (RST_ASYNC_G = false and rst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (clk, rst) is
   begin
      if (RST_ASYNC_G and rst = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif (rising_edge(clk)) then
         r <= rin after TPD_G;
      end if;
   end process seq;

end rtl;
