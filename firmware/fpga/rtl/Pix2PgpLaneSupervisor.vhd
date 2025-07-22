-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp Lane Supervising Module
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
use surf.SsiPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpLaneSupervisor is
   generic(
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1');  -- '1' for active high rst, '0' for active low
   port(
      -- General Interface
      pgpRxClk       : in  sl;
      pgpRxRst       : in  sl := not(RST_POLARITY_G);
      config         : in  Pix2PgpStreamRxConfigType;
      pgp4RxLinkUp   : in  slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      pgp4RxLinkDown : out  slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- Lane Interface
      laneRst        : out slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneStatus     : in  Pix2PgpLaneStatusArray;
      laneMetaRd     : out slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      lanePostError  : out slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- Trigger Buffer Interface
      trgBuffTrgCnt  : in  slv(TRGCNT_WIDTH_C-1 downto 0);
      trgBuffSroEn   : in  sl;
      trgBuffValid   : in  sl;
      trgBuffRd      : out sl;
      -- Lane Merger Interface
      mergerBusy     : in  sl;
      asicStatus     : out Pix2PgpLaneStatusArray;
      fpgaTrgCnt     : out slv(TRGCNT_WIDTH_C-1 downto 0);
      reqDrop        : out sl;
      reqNominal     : out sl;
      reqPause       : out sl);
end Pix2PgpLaneSupervisor;

architecture rtl of Pix2PgpLaneSupervisor is

   signal timeout    : sl := '0';
   signal linkUpSync : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   type LaneUpCntArray is array (NUM_OF_SERIALIZERS_C-1 downto 0) of slv(7 downto 0);

   type StateType is (
      IDLE_S,
      EVAL_LANES_S,
      EVAL_TRG_CNT_S,
      START_MERGER_S,
      WAIT_MERGER_S,
      RESET_S,
      DONE_S,
      POST_RESET_S);

   type RegType is record
      reqDrop       : sl;
      reqNominal    : sl;
      reqPause      : sl;
      mergerBusy    : sl;
      armTimeout    : sl;
      inPause       : sl;
      evalLanes     : sl;
      trgBuffRd     : sl;
      trgMisalign   : sl;
      postReset     : sl;
      laneRst       : sl;
      lanePostError : sl;
      laneMetaRd    : sl;
      laneValid     : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneUpCnt     : LaneUpCntArray;
      asicStatus    : Pix2PgpLaneStatusArray;
      laneUp        : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneReady     : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneError     : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneTimeout   : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneEnable    : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      lanePause     : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      refTrgCnt     : slv(TRGCNT_WIDTH_C-1 downto 0);
      fpgaTrgCnt    : slv(TRGCNT_WIDTH_C-1 downto 0);
      prvTrgCnt     : slv(TRGCNT_WIDTH_C-1 downto 0);
      waitCnt       : slv(3 downto 0);
      state         : stateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      reqDrop       => '0',
      reqNominal    => '0',
      reqPause      => '0',
      mergerBusy    => '0',
      armTimeout    => '0',
      inPause       => '0',
      evalLanes     => '0',
      trgBuffRd     => '0',
      trgMisalign   => '0',
      postReset     => '0',
      laneRst       => '0',
      lanePostError => '0',
      laneMetaRd    => '0',
      laneValid     => (others => '0'),
      laneUpCnt     => (others => (others => '0')),
      asicStatus    => (others => DEFAULT_PIX2PGP_LANESTATUS_C),
      laneUp        => (others => '0'),
      laneReady     => (others => '0'),
      laneError     => (others => '0'),
      laneTimeout   => (others => '0'),
      laneEnable    => (others => '0'),
      lanePause     => (others => '0'),
      refTrgCnt     => (others => '0'),
      fpgaTrgCnt    => (others => '0'),
      prvTrgCnt     => (others => '0'),
      waitCnt       => (others => '0'),
      state         => IDLE_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   U_SyncLinkUp : entity surf.SynchronizerVector
      generic map (
         TPD_G   => TPD_G,
         WIDTH_G => NUM_OF_SERIALIZERS_C)
      port map (
         clk     => pgpRxClk,
         dataIn  => pgp4RxLinkUp,
         dataOut => linkUpSync);

   -------------------------------------------------------------------------------------------------
   -------------------------------------------------------------------------------------------------
   comb : process (r, pgpRxRst, trgBuffValid, trgBuffSroEn, mergerBusy,
                   timeout, config, linkUpSync, laneStatus, trgBuffTrgCnt) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Register Inputs
      v.mergerBusy := mergerBusy;
      v.fpgaTrgCnt := trgBuffTrgCnt;

      -- Default values
      v.reqDrop    := '0';
      v.reqNominal := '0';
      v.reqPause   := '0';
      v.armTimeout := '0';
      v.trgBuffRd  := '0';
      v.evalLanes  := '0';

      -- global status loop
      for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop

         v.laneEnable(lane) := config.laneEnable(lane);

         -- link stability counters
         if linkUpSync(lane) = '1' and uAnd(r.laneUpCnt(lane)) /= '1' then
            v.laneUpCnt(lane) := r.laneUpCnt(lane) + 1;
         end if;

         if linkUpSync(lane) = '0' then
            v.laneUpCnt(lane) := (others => '0');
         end if;

         v.laneUp(lane) := uAnd(r.laneUpCnt(lane));

         -- activate lane evaluation only in specific parts of the FSM
         if r.evalLanes = '1' then

            if timeout = '1' then
               v.laneTimeout(lane) := not(laneStatus(lane).valid);
            end if;

            v.lanePause(lane) := laneStatus(lane).pause;

            -- determine if a lane is in error or not
            -- a lane is not in error if the link is down
            v.laneError(lane) := (laneStatus(lane).overflow or laneStatus(lane).decError) and
                              not(r.laneUp(lane));

            -- determine if a lane is ready to be read-out or not;
            -- a lane is 'ready' if its link is down
            v.laneReady(lane) := laneStatus(lane).valid or
                                 r.laneTimeout(lane)    or
                                 r.laneError(lane)      or
                                 not(r.laneUp(lane));

            -- determine if a lane is actually valid by masking out any errors
            v.laneValid(lane) := laneStatus(lane).valid   and
                                 not(r.laneTimeout(lane)) and
                                 not(r.laneError(lane))   and
                                 r.laneEnable(lane)       and
                                 r.laneUp(lane);
         end if;

      end loop;


      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- wait for the trigger buffer to have a word
         when IDLE_S =>
            v.laneTimeout := (others => '0');
            v.laneReady   := (others => '0');
            v.laneError   := (others => '0');
            v.laneValid   := (others => '0');
            v.waitCnt     := (others => '0');

            if trgBuffValid = '1' then

               v.state := EVAL_LANES_S;

               -- if this trigger never reached the ASIC, send a 'drop' frame
               -- same if no receiver lane is enabled/stable
               if trgBuffSroEn = '0' or uOr(r.laneUp) = '0' or uOr(r.laneEnable) = '0' then
                  v.reqDrop := '1';
                  v.state   := WAIT_MERGER_S;
               end if;

            end if;

         -------------------------------------------------------------------------
         -- wait for all activated lanes to go to a ready state
         -- 'ready' might mean that the lane has a valid frame;
         -- or, that the lane is in some error state
         when EVAL_LANES_S =>
            v.armTimeout := '1';
            v.evalLanes  := '1';

            if r.laneReady = r.laneEnable then
               v.state := EVAL_TRG_CNT_S;
            end if;

         -------------------------------------------------------------------------
         -- scan all trigger counter values of valid lanes;
         -- if all of equal value -> proceed normally
         -- it not, force an error to all lanes
         -- note that all this is done in one cycle (hence the use of v.)
         when EVAL_TRG_CNT_S =>
            v.refTrgCnt   := (others => '0');
            v.trgMisalign := '0';

            -- first grab the first valid trigger counter...
            for lane in NUM_OF_SERIALIZERS_C-1 downto 0 loop

               if r.laneValid(lane) = '1' then
                  v.refTrgCnt := laneStatus(lane).trgCnt;
                  exit;
               end if;

            end loop;

            -- then check against the rest...
            for lane in NUM_OF_SERIALIZERS_C-1 downto 0 loop

               if r.laneValid(lane) = '1' and laneStatus(lane).trgCnt /= v.refTrgCnt then
                  v.trgMisalign := '1';
                  exit;
               end if;

            end loop;

            -- two types of trigger misalignment
            if r.postReset = '1' and v.refTrgCnt = r.prvTrgCnt then
               v.trgMisalign := '1';
            end if;

            -- can continue readout of lanes since we moved on to the next event
            if v.trgMisalign = '0' and r.postReset = '1' and v.refTrgCnt /= r.prvTrgCnt then
               v.postReset := '0';
            end if;

            v.state := START_MERGER_S;

         -------------------------------------------------------------------------
         -- start the merger FSM; update the status bits sent to the merger
         when START_MERGER_S =>

            -- pipeline the statuses
            for lane in NUM_OF_SERIALIZERS_C-1 downto 0 loop
               v.asicStatus(lane).decError     := laneStatus(lane).decError;
               v.asicStatus(lane).overOcc      := laneStatus(lane).overOcc;
               v.asicStatus(lane).pause        := laneStatus(lane).pause;
               v.asicStatus(lane).pauseError   := laneStatus(lane).pauseError;
               v.asicStatus(lane).overflow     := laneStatus(lane).overflow;
               v.asicStatus(lane).valid        := r.laneValid(lane);
               v.asicStatus(lane).down         := not(r.laneUp(lane));
               v.asicStatus(lane).timeout      := r.laneTimeout(lane);
               v.asicStatus(lane).activeColCnt := laneStatus(lane).activeColCnt;
               v.asicStatus(lane).trgCnt       := r.refTrgCnt;
               v.asicStatus(lane).frameSize    := laneStatus(lane).frameSize;

               -- override if triggers are misaligned
               if r.trgMisalign = '1' then
                  v.asicStatus(lane).decError := '1';
                  v.laneError(lane)           := '1';
                  v.asicStatus(lane).valid    := '0';
               end if;

            end loop;

            if uOr(r.lanePause) = '1' then
               v.inPause    := '1';
               v.reqPause   := '1';
               v.reqNominal := '0';
            else
               v.inPause    := '0';
               v.reqPause   := '0';
               v.reqNominal := '1';
            end if;

            v.state := WAIT_MERGER_S;

         ----------------------------------------------------------------------
         -- wait for merger to finish sending out the frame;
         -- also figure out if we need a reset or not...
         when WAIT_MERGER_S =>
            if v.mergerBusy = '0' and r.mergerBusy = '1' then
               v.laneMetaRd := '1';

               v.state := DONE_S;

               if uOr(r.laneError) = '1' then
                  v.state := RESET_S;
               end if;

            end if;

         -------------------------------------------------------------------------
         -- grab the trigger counter. reset the inPause flag
         -- perform the reset; do the postError and all that...
         -- then go-to DONE_S when done resetting
         when RESET_S =>
            v.prvTrgCnt     := r.refTrgCnt;
            v.inPause       := '0';
            v.laneRst       := '1';
            v.lanePostError := '1';
            v.state         := DONE_S;

         ----------------------------------------------------------------------
         -- pop the trigger buffer word and wait
         when DONE_S =>
            v.waitCnt     := r.waitCnt + 1;
            v.laneTimeout := (others => '0');
            v.laneReady   := (others => '0');
            v.laneError   := (others => '0');
            v.laneValid   := (others => '0');

            if uOr(r.waitCnt) = '0' then
               v.laneRst   := '0';
               v.trgBuffRd := '1';
            end if;

            if r.waitCnt = toSlv(4, r.waitCnt'length) then
               v.waitCnt       := (others => '0');
               v.lanePostError := '0';
               v.state         := IDLE_S;

               -- override if after a reset
               if r.lanePostError = '1' then
                  v.state := POST_RESET_S;
               end if;

            end if;

            -- still more data to come for this event; don't pop the word;
            -- re-evaluate lane statuses instead
            if r.inPause = '1' and r.lanePostError = '0' then
               v.trgBuffRd := '0';
               v.waitCnt   := (others => '0');
               v.state     := EVAL_LANES_S;
            end if;

         -------------------------------------------------------------------------
         -- in post-reset, raise the evalLanes flag.
         -- if ANY lane is in error, reset again
         -- if there is no error and laneReady = laneEnable, go-to idle_s.
         -- the postReset flag needs to be retained to make the extra trgCnt check.
         when POST_RESET_S =>
            v.postReset := '1';
            v.evalLanes := '1';

            if r.laneReady = r.laneEnable then
               v.state := IDLE_S;
            end if;

            if uOr(r.laneError) = '1' then
               v.state := RESET_S;
            end if;

      end case;
      -----------------------------------------------------------------------

      -- Outputs
      asicStatus     <= r.asicStatus;
      reqDrop        <= r.reqDrop;
      reqNominal     <= r.reqNominal;
      reqPause       <= r.reqPause;
      fpgaTrgCnt     <= r.fpgaTrgCnt;
      trgBuffRd      <= r.trgBuffRd;
      pgp4RxLinkDown <= not(r.laneUp);

      for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop
         if RST_POLARITY_G = '1' then
            laneRst(lane) <= pgpRxRst or r.laneRst
                          or not(r.laneEnable(lane)) or not(r.laneUp(lane));
         else
            laneRst(lane) <= pgpRxRst and not(r.laneRst)
                          and(r.laneEnable(lane)) and(r.laneUp(lane));
         end if;

         lanePostError(lane) <= r.lanePostError;

         -- only read the valid lanes
         laneMetaRd(lane) <= r.laneMetaRd and (r.laneValid(lane));

      end loop;

      -- Reset
      if (RST_ASYNC_G = false and pgpRxRst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (pgpRxClk, pgpRxRst) is
   begin
      if (RST_ASYNC_G and pgpRxRst = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(pgpRxClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;
   -------------------------------------------------------------------------------------------------
   -------------------------------------------------------------------------------------------------

   -- Watchdog
   U_Watchdog : entity pix2pgp.Pix2PgpWatchdog
      generic map(
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         RST_POLARITY_G => RST_POLARITY_G,
         CNT_WIDTH_G    => FPGA_TIMEOUT_LIMIT_WIDTH_C)
      port map(
         -- General Interface
         clk     => pgpRxClk,
         rst     => pgpRxRst,
         limit   => config.timeoutLimit,
         -- Control Interface
         set     => r.armTimeout,
         timeout => timeout);

end rtl;
