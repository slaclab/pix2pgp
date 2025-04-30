-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp Lane Filter; checks on the trigger number
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
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpLaneFilter is
   generic(
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1'  -- '1' for active high rst, '0' for active low
   );
   port(
      -- General Interface
      sysClk         : in  sl;
      sysRst         : in  sl := not(RST_POLARITY_G);
      -- Lane Interface
      laneRxRst      : out sl;
      frameMetaRd    : out sl;
      frameMetaDout  : in  slv(LANERX_META_BUFF_WIDTH_C-1 downto 0);
      frameMetaValid : in  sl;
      -- AXI-Stream from Lane
      ibAxisMaster   : in  AxiStreamMasterType;
      ibAxisSlave    : out AxiStreamSlaveType;
      -- ASIC Rx Interface
      lastTrgCnt     : out slv(TRGCNT_WIDTH_C-1 downto 0);
      laneError      : out sl;
      laneRxMaster   : out AxiStreamMasterType;
      laneRxSlave    : in  AxiStreamSlaveType);
end Pix2PgpLaneFilter;

architecture rtl of Pix2PgpLaneFilter is

   -- how much to stretch laneRxRst
   constant LANE_RX_RST_WIDTH_C : natural := 10;

   type RegType is record
      errorFlag    : sl;
      laneError    : sl;
      frameMetaRd  : sl;
      checking     : sl;
      valid        : sl;
      waitCnt      : slv(1 downto 0);
      lastTrgCnt   : slv(TRGCNT_WIDTH_C-1 downto 0);
      laneRxMaster : AxiStreamMasterType;
      ibAxisSlave  : AxiStreamSlaveType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      errorFlag    => '0',
      laneError    => '0',
      frameMetaRd  => '0',
      checking     => '0',
      valid        => '0',
      waitCnt      => (others => '0'),
      lastTrgCnt   => (others => '0'),
      laneRxMaster => AXI_STREAM_MASTER_INIT_C,
      ibAxisSlave  => AXI_STREAM_SLAVE_INIT_C);

   signal r   : RegType;
   signal rin : RegType;

begin

   comb : process (r, frameMetaDout, sysRst, frameMetaValid, ibAxisMaster, laneRxSlave) is
      variable v       : RegType;
      variable axisTrg : slv(TRGCNT_WIDTH_C-1 downto 0);
      variable trg     : slv(TRGCNT_WIDTH_C-1 downto 0);
      variable flag    : sl;
   begin

      -- Latch the current value
      v := r;

      axisTrg := resize(ibAxisMaster.tData(TRGCNT_POS_C), TRGCNT_WIDTH_C);
      flag    := frameMetaDout(LANERX_META_BUFF_WIDTH_C-1);
      trg     := frameMetaDout(LANERX_META_BUFF_WIDTH_C-2 downto 0);

      -- defaults
      v.frameMetaRd := '0';

      -- refuse to receive the AXI-Stream by default
      v.ibAxisSlave.tReady := '0';
      v.laneRxMaster     := AXI_STREAM_MASTER_INIT_C;

      -- ready to accept data
      if r.valid = '1' then
         v.ibAxisSlave.tReady := laneRxSlave.tReady;
         v.laneRxMaster     := ibAxisMaster;
      end if;

      -- get the metadata first...
      if frameMetaValid = '1' and v.valid = '0' and r.checking = '0' and r.laneError = '0' then
         v.errorFlag  := flag;
         v.lastTrgCnt := trg;
         v.checking   := '1';
      end if;

      -- checking trigger counter against inbound AXI stream valid and checking errorFlag
      if r.errorFlag = '0' and r.checking = '1' and r.laneError = '0' then
         v.frameMetaRd := '1'; -- pop the metadata word
         v.checking    := '0'; -- drop the flag

         -- disable for now
         --if axisTrg /= r.lastTrgCnt then
         --   v.valid     := '0'; -- do not send data downstream
         --   v.laneError := '1'; -- can only be cleared by an upstream reset
         --else
         --   v.valid     := '1'; -- safe to pipe in the data
         --end if;

         v.valid := '1';  -- safe to pipe in the data

      elsif r.errorFlag = '1' and r.checking = '1' and r.laneError = '0' then
         v.laneError := '1'; -- can only be cleared by an upstream reset
      end if;

      if r.valid = '1' and ibAxisMaster.tLast = '1' and r.laneError = '0' then
         v.valid   := '0'; -- last word received; force the slave to non-ready again
         v.waitCnt := r.waitCnt + 1; -- start the wait counter
      end if;

      -- always wait before re-evaluating FIFO (to avoid double-reading)
      if uOr(r.waitCnt) = '1' then
         v.waitCnt := r.waitCnt + 1;
         if allBits(r.waitCnt, '1') then
            v.waitCnt  := (others => '0');
            v.checking := '0';
         end if;
      end if;

      -- Outputs
      laneRxMaster <= v.laneRxMaster;
      ibAxisSlave  <= v.ibAxisSlave;
      frameMetaRd  <= r.frameMetaRd;

      -- Reset
      if (RST_ASYNC_G = false and sysRst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (sysClk, sysRst) is
   begin
      if (RST_ASYNC_G and sysRst = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(sysClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

   U_PipelineError : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => 2)
      port map (
         clk     => sysClk,
         din(0)  => r.laneError,
         dout(0) => laneError);

   U_StretchRst : entity surf.SynchronizerOneShot
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         PULSE_WIDTH_G  => LANE_RX_RST_WIDTH_C)
      port map (
         clk     => sysClk,
         dataIn  => sysRst,
         dataOut => laneRxRst);

end rtl;
