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
      RST_POLARITY_G : sl      := '1';  -- '1' for active high rst, '0' for active low
      DELAY_G        : natural := 1);
   port(
      -- General Interface
      pgpRxClk      : in  sl;
      pgpRxRst      : in  sl := not(RST_POLARITY_G);
      config        : in  Pix2PgpStreamRxConfigType;
      pgp4RxLinkUp  : in  slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- Lane Interface
      laneStatus    : in  Pix2PgpLaneStatusArray;
      laneMetaRd    : out slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      dropBadColTrg : out slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      lanePostError : out slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- Trigger Buffer Interface
      trgBuffTrgCnt : in  slv(TRGCNT_WIDTH_C-1 downto 0);
      trgBuffSroEn  : in  sl;
      trgBuffValid  : in  sl;
      trgBuffRd     : out sl;
      -- Lane Merger Interface
      asicStatus    : out Pix2PgpLaneStatusArray;
      laneTimeout   : out slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneDown      : out slv(NUM_OF_SERIALIZERS_C-1 downto 0));
end Pix2PgpLaneSupervisor;

architecture rtl of Pix2PgpLaneSupervisor is

   signal timeout    : sl := '0';
   signal linkUpSync : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   type LaneUpCntArray is array (NUM_OF_SERIALIZERS_C-1 downto 0) of slv(7 downto 0);

   type StateType is (
      IDLE_S,
      COUNT_S);

   type RegType is record
      reqDrop    : sl;
      reqNominal : sl;
      reqPause   : sl;
      mergerBusy : sl;
      armTimeout : sl;
      laneValid  : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneUpCnt  : LaneUpCntArray;
      state      : stateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      reqDrop    => '0',
      reqNominal => '0',
      reqPause   => '0',
      mergerBusy => '0',
      armTimeout => '0',
      laneValid  => (others => '0');
      laneUpCnt  => (others => (others => '0')),
      state      => IDLE_S);
   );

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

   -----------------------------------------------------------------------
   -----------------------------------------------------------------------
   comb : process (r, pgpRxRst, trgBuffValid, trgBuffSroEn, mergerBusy, timeout, config,
                   linkUpSync, laneStatus) is
      variable v            : RegType;
      variable inPause      : sl := '0';
      variable laneUp       : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
      variable laneReady    : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
      variable laneError    : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
      variable laneTimeout  : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
      variable laneEnable   : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
      variable evalLanes    : sl := '0';
      variable rstEvalLanes : sl := '0';
   begin

      -- Latch the current value
      v := r;

      -- Register Inputs
      v.mergerBusy := mergerBusy;

      -- Default values
      v.reqDrop    := '0';
      v.reqNominal := '0';
      v.reqPause   := '0';
      v.armTimeout := '0';
      v.trgBuffRd  := '0';
      evalLanes    := '0';
      rstEvalLanes := '0';

      for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop

         laneEnable := config(lane).laneEnable;

         -- link stability counters
         if linkUpSync(lane) = '1' and uAnd(r.laneUpCnt(lane)) /= '1' then
            v.laneUpCnt(lane) := r.laneUpCnt(lane) + 1;
         end if;

         if linkUpSync(lane) = '0' then
            v.laneUpCnt(lane) := (others => '0');
         end if;

         laneUp(lane) := uAnd(r.laneUpCnt(lane));

         -- activate lane evaluation only in specific parts of the FSM
         if evalLanes = '1' then

            if timeout = '1' then
               laneTimeout(lane) := not(laneStatus(lane).valid);
            end if;

            -- determine if a lane is in error or not
            -- a lane is not in error if the link is down
            laneError(lane) := (laneStatus(lane).overflow or laneStatus(lane).decError) and
                                not(laneUp(lane));

            -- determine if a lane is ready to be read-out or not;
            -- a lane is 'ready' if its link is down
            laneReady(lane) := laneStatus(lane).valid or
                               laneTimeout(lane)      or
                               laneError(lane)        or
                               not(laneUp(lane));

            -- determine if a lane is actually valid by masking out any errors
            v.laneValid(lane) := laneStatus(lane).valid and
                                 not(laneTimeout(lane)) and
                                 not(laneError(lane))   and
                                 laneUp(lane);
         end if;

      end loop;

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- wait for the trigger buffer to have a word
         when IDLE_S =>
            rstEvalLanes := '1';

            if trgBuffValid = '1' then

               v.state := WAIT_LANES_S;

               -- if this trigger never reached the ASIC, send a 'drop' frame
               -- same if no receiver lane is enabled/stable
               if trgBuffSroEn = '0' or uOr(laneUp) = '0' then
                  v.reqDrop := '1';
                  v.state   := WAIT_MERGER_S;
               end if;

            end if;

         -------------------------------------------------------------------------
         -- wait for all activated lanes to go to a ready state
         -- 'ready' might mean that the lane has a valid frame;
         -- or, that the lane is in some error state
         when WAIT_LANES_S =>
            v.armTimeout := '1';
            evalLanes    := '1';

            if laneReady = laneEnable then
               v.state := EVAL_TRG_CNT_S;
            end if;


         -------------------------------------------------------------------------
         -- scan all trigger counter values of valid lanes;
         -- if all of equal value -> proceed with read-out;
         -- it not, force an error
         when EVAL_TRG_CNT_S =>
            -- cycle through all valids...

            -- if all trgCnts the same -> make the second check, which is the postReset check.
            -- if postReset = '1', make sure that the current TrgCnt is DIFFERENT wrt the old one.
            -- if it is, drop the postReset flag and continue.

            -- also grab the pause status and set the inPause reg,
            -- make the associated request depending if we are in pause or not

            -- then wait for merger...

            -- before making the request, make sure that you pipe the statuses downstream to merger
            -- the Pix2PgpLaneStatusType.trgCnt is the fpga trigger counter value

            -- TO-DO: add the hitmask count into the status (r.activeColCnt in lanerx);
            -- add it in Pix2PgpLaneStatusType.
            -- then add a relevant field in the fpga-generated header;
            -- it should be transmitted after the frameSize.

            -- if not all trgCnts same... -> set the laneError and decError to all ones;
            -- also set laneValid to all zeros.

            -- request nominal, and then go-to WAIT_MERGER_S


         ----------------------------------------------------------------------
         -- wait for merger to finish sending out the frame;
         -- also figure out if we need a reset or not...
         when WAIT_MERGER_S =>
            if v.mergerBusy = '0' and r.mergerBusy = '1' then
               v.state := DONE_S;

               if uOr(laneError) = '1' then
                  postReset := '1';
                  v.state   := RESET_S;
               end if;

            end if;

         -------------------------------------------------------------------------
         -- grab the trigger counter. reset the inPause flag
         -- perform the reset; do the postError and all that...
         -- then go-to DONE_S when done resetting
         when RESET_S =>

         ----------------------------------------------------------------------
         -- pop the trigger buffer word and wait
         when DONE_S =>

            v.waitCnt := r.waitCnt + 1;

            if uOr(r.waitCnt) = '0' then
               v.trgBuffRd := '1';
            end if;

            if uAnd(r.waitCnt) = '1' then

               v.state := IDLE_S;

               -- override if after a reset
               if postReset = '1' then
                  v.state := POST_RESET_S;
               end if;

            end if;

            -- still more data to come for this event; don't pop the word;
            -- re-evaluate lane statuses instead
            if inPause = '1' then
               v.trgBuffRd  := '0';
               rstEvalLanes := '1';
               v.state      := WAIT_LANES_S;
            end if;

         -------------------------------------------------------------------------
         -- in post-reset, raise the evalLanes flag.
         -- if ANY lane is in error, reset again
         -- if there is no error and laneReady = laneEnable, go-to idle_s.
         -- the postReset flag needs to be retained to make the extra trgCnt check.
         when POST_RESET_S =>

      end case;
      -----------------------------------------------------------------------

      if rstEvalLanes = '1' then
         laneTimeout := (others => '0');
         laneReady   := (others => '0');
         laneError   := (others => '0');
         v.laneValid := (others => '0');
         v.waitCnt   := (others => '0');
      end if;

      -- Outputs
      dout <= r.cnt;

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
   -----------------------------------------------------------------------
   -----------------------------------------------------------------------

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
