-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp Lane Merging Logic
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
use pix2pgp.Pix2PgpAsicPkg.all;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpLaneMerger is
   generic(
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1';  -- '1' for active high rst, '0' for active low
      ASIC_ID_G      : natural := 0);
   port(
      -- General Interface
      pgpRxClk      : in  sl;
      pgpRxRst      : in  sl := not(RST_POLARITY_G);
      config        : in  Pix2PgpStreamRxConfigType;
      -- Supervisor Interface
      mergerBusy    : out sl;
      asicStatus    : in  Pix2PgpLaneStatusArray;
      fpgaTrgCnt    : in  slv(TRGCNT_WIDTH_C-1 downto 0);
      reqDrop       : in  sl;
      reqNominal    : in  sl;
      reqPause      : in  sl;
      dumpData      : in  sl;
      -- Lane AXI-Stream Input Interface
      laneRxMasters : in  AxiStreamMasterArray;
      laneRxSlaves  : out AxiStreamSlaveArray;
      -- AXI-Stream Output Interface (on pgpRxClk domain)
      obAxiMaster   : out AxiStreamMasterType;
      obAxiSlave    : in  AxiStreamSlaveType);
end Pix2PgpLaneMerger;

architecture rtl of Pix2PgpLaneMerger is

   type StateType is (
      IDLE_S,
      TX_PREAMBLE_S,
      TX_HEADER_S,
      TX_FRAME_SIZE_S,
      TX_LANE_DATA_S,
      DUMP_S,
      DONE_S,
      TX_TRAILER_S);

   type RegType is record
      busy         : sl;
      reqDrop      : sl;
      reqNominal   : sl;
      reqPause     : sl;
      dumpData     : sl;
      inPause      : sl;
      laneSel      : slv(BITMAX_SERIALIZERS_C-1 downto 0);
      asicType     : slv(ASIC_TYPE_LEN_C-1 downto 0);
      laneDumpAck  : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- AXI-Stream
      obAxiMaster  : AxiStreamMasterType;
      laneRxSlaves : AxiStreamSlaveArray(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- FSM
      state        : stateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      busy         => '0',
      reqDrop      => '0',
      reqNominal   => '0',
      reqPause     => '0',
      dumpData     => '0',
      inPause      => '0',
      laneSel      => (others => '0'),
      asicType     => toSlv(ASIC_TYPE_C, ASIC_TYPE_LEN_C),
      laneDumpAck  => (others => '0'),
      -- AXI-Stream
      obAxiMaster  => AXI_STREAM_MASTER_INIT_C,
      laneRxSlaves => (others => AXI_STREAM_SLAVE_INIT_C),
      -- FSM
      state        => IDLE_S
   );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   -------------------------------------------------------------------------------------------------
   -------------------------------------------------------------------------------------------------
   comb : process (r, pgpRxRst, asicStatus, fpgaTrgCnt, reqDrop, reqNominal,
                   reqPause, dumpData, laneRxMasters, obAxiSlave, config) is
      variable v : RegType;

      -- internal variables
      variable laneIdx        : natural := 0;
      variable preamble       : slv(FPGA_PREAMBLE_LEN_C-1 downto 0)         := (others => '0');
      variable header         : slv(FPGA_HEADER_LEN_C-1 downto 0)           := (others => '0');
      variable frameSize      : slv(STREAMRX_FRAME_SIZE_WIDTH_C-1 downto 0) := (others => '0');

      variable laneAxiStream  : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;

      variable laneDecError   : slv(NUM_OF_SERIALIZERS_C-1 downto 0)        := (others => '0');
      variable laneOverOcc    : slv(NUM_OF_SERIALIZERS_C-1 downto 0)        := (others => '0');
      variable lanePause      : slv(NUM_OF_SERIALIZERS_C-1 downto 0)        := (others => '0');
      variable laneFull       : slv(NUM_OF_SERIALIZERS_C-1 downto 0)        := (others => '0');
      variable laneDown       : slv(NUM_OF_SERIALIZERS_C-1 downto 0)        := (others => '0');
      variable lanePauseError : slv(NUM_OF_SERIALIZERS_C-1 downto 0)        := (others => '0');
      variable laneTimeout    : slv(NUM_OF_SERIALIZERS_C-1 downto 0)        := (others => '0');
      variable laneValid      : slv(NUM_OF_SERIALIZERS_C-1 downto 0)        := (others => '0');
   begin

      -- Latch the current value
      v := r;

      -- Register inputs (trigger on rising edges)
      v.reqDrop    := reqDrop;
      v.reqNominal := reqNominal;
      v.reqPause   := reqPause;

      if r.reqDrop = '1' then
         v.reqDrop := '1';
      else
         v.reqDrop := (v.reqDrop and not(r.reqDrop));
      end if;

      if r.reqNominal = '1' then
         v.reqNominal := '1';
      else
         v.reqNominal := (v.reqNominal and not(r.reqNominal));
      end if;

      if r.reqPause = '1' then
         v.reqPause := '1';
      else
         v.reqPause := (v.reqPause and not(r.reqPause));
      end if;

      -- Default values
      v.busy := '1';

      -- flow control check
      if obAxiSlave.tReady = '1' then
         v.obAxiMaster.tValid := '0';
         v.obAxiMaster.tLast  := '0';
         v.obAxiMaster.tUser  := (others => '0');
         v.obAxiMaster.tData  := (others => '0');
         v.obAxiMaster.tKeep  := (others => '0');
      end if;

      -- lane loop
      for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop
         v.laneRxSlaves(lane).tReady := '0'; -- disable by default
         -- lane status variable allocation
         laneDecError(lane)   := asicStatus(lane).decError;
         laneOverOcc(lane)    := asicStatus(lane).overOcc;
         lanePause(lane)      := asicStatus(lane).pause;
         laneFull(lane)       := asicStatus(lane).overflow;
         laneDown(lane)       := asicStatus(lane).down;
         lanePauseError(lane) := asicStatus(lane).pauseError;
         laneTimeout(lane)    := asicStatus(lane).timeout;
         laneValid(lane)      := asicStatus(lane).valid;
      end loop;

      preamble := fpgaPreambleMap(PIX2PGP_ID_C, r.asicType, toSlv(ASIC_ID_G, ASIC_ID_LEN_C),
                                  config.fpgaId, fpgaTrgCnt);

      header := fpgaHeaderMap(laneDecError, laneOverOcc, lanePause, lanePauseError,
                              laneFull, laneTimeout, laneDown, laneValid);

      laneIdx := conv_integer(unsigned(r.laneSel));

      laneAxiStream := laneRxMasters(laneIdx);

      frameSize := resize(asicStatus(laneIdx).frameSize, STREAMRX_FRAME_SIZE_WIDTH_C);

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- wait for a request signal
         when IDLE_S =>
            v.busy         := '0';
            v.asicType     := toSlv(ASIC_TYPE_C, ASIC_TYPE_LEN_C);
            v.laneDumpAck := (others => '0');

            if (r.reqDrop or r.reqNominal or r.reqPause) = '1' then

               v.state := TX_PREAMBLE_S;

               -- override designated asicType with the drop-trigger type identifier;
               -- will transmit preamble and then trailer (in next state)
               if r.reqDrop = '1' and r.inPause = '0' then
                  v.asicType := toSlv(0, ASIC_TYPE_LEN_C);
               end if;

               -- extreme corner-case; need to close the axi-frame;
               -- will then come back here and transmit the drop-frame (inPause is gnd'd later)
               if r.reqDrop = '1' and r.inPause = '1' then
                  v.state := TX_TRAILER_S;
               end if;

               -- regular pause-continuation request; skip preamble
               if r.reqDrop = '0' and r.inPause = '1' then
                  v.state := TX_HEADER_S;
               end if;

               if r.reqDrop = '0' and dumpData = '1' then
                  v.state := DUMP_S;
               end if;

            end if;

         ----------------------------------------------------------------------
         -- transmit the pix2pgp preamble via axi
         when TX_PREAMBLE_S =>
            if v.obAxiMaster.tValid = '0' then
               v.obAxiMaster.tValid := '1';

               v.obAxiMaster.tKeep := tKeepSet(FPGA_PREAMBLE_LEN_C);
               ssiSetUserSof(PIX2PGP_FPGA_AXI_CONFIG_C, v.obAxiMaster, '1');
               v.obAxiMaster.tData(FPGA_PREAMBLE_LEN_C-1 downto 0) := preamble;

               v.state := TX_HEADER_S;

               if r.reqDrop = '1' then
                  v.reqDrop := '0';
                  v.state   := TX_TRAILER_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- transmit event header infromation
         when TX_HEADER_S =>
            if v.obAxiMaster.tValid = '0' then

               v.obAxiMaster.tValid := '1';

               v.obAxiMaster.tKeep := tKeepSet(FPGA_HEADER_LEN_C);
               v.obAxiMaster.tData(FPGA_HEADER_LEN_C-1 downto 0) := header;

               v.state := TX_FRAME_SIZE_S;
            end if;

         ----------------------------------------------------------------------
         -- transmit all (valid) lane frame size data
         when TX_FRAME_SIZE_S =>
            if v.obAxiMaster.tValid = '0' then

               v.obAxiMaster.tValid := '1';
               v.obAxiMaster.tKeep  := tKeepSet(STREAMRX_FRAME_SIZE_WIDTH_C);
               v.obAxiMaster.tData(STREAMRX_FRAME_SIZE_WIDTH_C-1 downto 0) := frameSize;

               if laneValid(laneIdx) = '0' then
                  v.obAxiMaster.tData(LANERX_FRAME_SIZE_WIDTH_C-1 downto 0) := (others => '0');
               end if;

               if laneIdx = NUM_OF_SERIALIZERS_C-1 then
                  v.laneSel := (others => '0');
                  v.state   := TX_LANE_DATA_S;
               else
                  v.laneSel := r.laneSel + 1;
               end if;

            end if;

         ----------------------------------------------------------------------
         -- switch mux to the lanes that have valid data until done
         when TX_LANE_DATA_S =>

            if laneValid(laneIdx) = '0' then

               if laneIdx = NUM_OF_SERIALIZERS_C-1 then
                  v.state := DONE_S;
               else
                  v.laneSel := r.laneSel + 1;
               end if;

            elsif v.obAxiMaster.tValid = '0' then
               v.obAxiMaster.tKeep := laneAxiStream.tKeep;
               v.obAxiMaster.tData := laneAxiStream.tData;

               v.obAxiMaster.tValid           := laneRxMasters(laneIdx).tValid;
               v.laneRxSlaves(laneIdx).tReady := obAxiSlave.tReady;

               if laneRxMasters(laneIdx).tLast = '1' and
                  obAxiSlave.tReady            = '1' then

                  if laneIdx = NUM_OF_SERIALIZERS_C-1 then
                     v.state := DONE_S;
                  else
                     v.laneSel := r.laneSel + 1;
                  end if;

               end if;

            end if;

         ----------------------------------------------------------------------
         -- determine what to do in case this was a pause event
         when DONE_S =>
            v.laneSel    := (others => '0');
            v.reqDrop    := '0';
            v.reqNominal := '0';
            v.reqPause   := '0';
            v.state      := TX_TRAILER_S;

            -- if this was a pause event, do not transmit the trailer;
            -- raise the in-pause flag, which determines if a preamble is tx'd
            if r.reqPause = '1' then
               v.inPause := '1';
               v.state   := IDLE_S;
            end if;

         ----------------------------------------------------------------------
         -- transmit trailer; clear all request flags
         when TX_TRAILER_S =>
            v.inPause := '0';

            if v.obAxiMaster.tValid = '0' then
               v.obAxiMaster.tKeep  := tKeepSet(FPGA_TRAILER_LEN_C);
               v.obAxiMaster.tData(FPGA_TRAILER_LEN_C-1 downto 0) :=
                  resize(PIX2PGP_ID_C, FPGA_TRAILER_LEN_C);
               v.obAxiMaster.tValid := '1';
               v.obAxiMaster.tLast  := '1';

               v.state := IDLE_S;
            end if;

         ----------------------------------------------------------------------
         -- empty the event from the axi-stream FIFO of all lanes
         when DUMP_S =>
            v.reqDrop    := '0';
            v.reqNominal := '0';
            v.reqPause   := '0';

            for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop

               -- latch the ack on last or on not-valid
               if laneRxMasters(lane).tLast = '1' or
                  r.laneDumpAck(lane)       = '1' or
                  laneValid(lane)           = '0' then

                  v.laneDumpAck(lane) := '1';

               end if;

               -- drain if we still have data;
               -- the tLast signal will halt this on the next cycle
               v.laneRxSlaves(lane).tReady := laneValid(lane) and not(r.laneDumpAck(lane));

            end loop;

            if uAnd(r.laneDumpAck) = '1' then
               v.state := IDLE_S;
            end if;

      end case;
      -----------------------------------------------------------------------

      -- Outputs
      mergerBusy   <= r.busy;

      -- AXI-Stream Outputs
      laneRxSlaves <= v.laneRxSlaves;
      obAxiMaster  <= r.obAxiMaster;

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

end rtl;
