-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp ASIC Stream Receiver;
--              Merges all inbound data lanes into a single AXI stream
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
use surf.AxiLitePkg.all;
use surf.AxiStreamPkg.all;
use surf.SsiPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpAsicStreamRx is
   generic(
      TPD_G                       : time     := 1 ns;
      RST_ASYNC_G                 : boolean  := false;
      RST_POLARITY_G              : sl       := '1';  -- '1' for active high rst, '0' for active low
      ASIC_ID_G                   : natural  := 0;
      SINGLE_LANE_ID_G            : natural  := 0;
      TIMEOUT_LIMIT_WIDTH_G       : positive := 12;
      LANE_PIPE_STAGES_G          : natural  := 1;
      STREAM_PIPE_STAGES_G        : natural  := 1;
      META_FIFO_ADDR_WIDTH_G      : positive := 4;
      LANE_AXIS_FIFO_ADDR_WIDTH_G : positive := 8;
      FILT_AXIS_FIFO_ADDR_WIDTH_G : positive := 10;
      DISCARD_BAD_COL_TRG_G       : boolean  := true);
   port(
      -- General Interface
      pgpRxClk        : in  sl;
      pgpRxRst        : in  sl := not(RST_POLARITY_G);
      -- ASIC Domain Interface
      asicClk         : in  sl;
      asicRst         : in  sl; -- active-low always
      asicSro         : in  sl;
      asicSroEna      : in  sl;
      -- PGP4Rx Input Interface (on pgpRxClk domain)
      pgp4RxMaster    : in  AxiStreamMasterArray;
      pgp4RxSlave     : out AxiStreamSlaveArray;
      -- AXI-Stream Output Interface (on pgpRxClk domain)
      asicRxMaster    : out AxiStreamMasterType;
      asicRxSlave     : in  AxiStreamSlaveType;
      -- AXI-Lite Interface
      axilClk         : in  sl;
      axilRst         : in  sl;
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType);
end Pix2PgpAsicStreamRx;

architecture rtl of Pix2PgpAsicStreamRx is

   constant FPGA_TRGCNT_DEFAULT_C   : slv(TRGCNT_WIDTH_C-1 downto 0)        := (others => '1');
   constant TIMEOUT_LIMIT_DEFAULT_C : slv(TIMEOUT_LIMIT_WIDTH_G-1 downto 0) := (others => '1');
   constant LANE_ENABLE_DEFAULT_C   : slv(NUM_OF_SERIALIZERS_C-1 downto 0)  := (others => '1');
   constant MAX_CNT_C               : slv(5 downto 0) := (others => '1');

   type timeoutArray is array (NUM_OF_SERIALIZERS_C-1 downto 0) of slv(TIMEOUT_LIMIT_WIDTH_G-1 downto 0);

   type trgCntArray is array (NUM_OF_SERIALIZERS_C-1 downto 0) of slv(TRGCNT_WIDTH_C-1 downto 0);

   signal laneTrgCnt      : trgCntArray := (others => (others => '0'));

   signal laneRxMasters   : AxiStreamMasterArray(NUM_OF_SERIALIZERS_C-1 downto 0)
                          := (others => AXI_STREAM_MASTER_INIT_C);
   signal laneRxSlaves    : AxiStreamSlaveArray(NUM_OF_SERIALIZERS_C-1 downto 0)
                          := (others => AXI_STREAM_SLAVE_INIT_C);

   signal laneDecError    : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal laneFull        : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal lanePauseError  : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal asicSroSync     : sl := '0';
   signal asicSroEnaSync  : sl := '0';
   signal asicRstSync     : sl := '0';

   signal trgBuffDout     : slv(TRGCNT_WIDTH_C-1 downto 0) := (others => '0');
   signal trgBuffValid    : sl := '0';
   signal timeoutLimit    : timeoutArray := (others => (others => '1'));
   signal timeoutLimitDly : timeoutArray := (others => (others => '1'));
   signal armTimeout      : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal armTimeoutDly   : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal timeout         : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal laneTimeout     : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal readMaster      : AxiLiteReadMasterType;
   signal readSlave       : AxiLiteReadSlaveType;
   signal writeMaster     : AxiLiteWriteMasterType;
   signal writeSlave      : AxiLiteWriteSlaveType;

   signal laneRst         : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => not(RST_POLARITY_G));

   signal discBadColTrg   : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal obAxisMaster    : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal obAxisSlave     : AxiStreamSlaveType  := AXI_STREAM_SLAVE_INIT_C;

   signal laneFrameSize   : Pix2PgpLaneFrameSizeArray := (others => (others => '0'));

   signal laneMetaValid   : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal laneMetaRd      : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   type StateType is (
      IDLE_S,
      TX_PREAMBLE_S,
      WAIT_LANES_S,
      TX_FRAME_SIZE_S,
      SWITCH_MUX_S,
      WAIT_TLAST_S,
      TX_TRAILER_S,
      DONE_S);

   type RegType is record
      -- Internal
      asicSro         : sl;
      fpgaTrgCnt      : slv(TRGCNT_WIDTH_C-1 downto 0);
      trgBuffWr       : sl;
      trgBuffRd       : sl;
      trgCntBuff      : slv(TRGCNT_WIDTH_C-1 downto 0);
      armTimeout      : sl;
      laneSel         : slv(BITMAX_SERIALIZERS_C downto 0);
      laneRst         : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      waitLaneSel     : sl;
      laneMetaRd      : sl;
      waitCnt         : slv(1 downto 0);
      state           : StateType;
      -- Registers
      discBadColTrg   : sl;
      cntRst          : sl;
      fpgaId          : slv(15 downto 0);
      timeoutLimit    : slv(TIMEOUT_LIMIT_WIDTH_G-1 downto 0);
      laneEnable      : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneDecErr      : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      lanePauseErr    : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneFull        : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneDecErrCnt   : Slv5Array(NUM_OF_SERIALIZERS_C-1 downto 0);
      lanePauseErrCnt : Slv5Array(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneFullCnt     : Slv5Array(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- AXI-Stream
      obAxisMaster    : AxiStreamMasterType;
      laneRxSlaves    : AxiStreamSlaveArray(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- AXI-Lite
      readSlave       : AxiLiteReadSlaveType;
      writeSlave      : AxiLiteWriteSlaveType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- Internal
      asicSro         => '0',
      fpgaTrgCnt      => FPGA_TRGCNT_DEFAULT_C,
      trgBuffWr       => '0',
      trgBuffRd       => '0',
      trgCntBuff      => (others => '0'),
      armTimeout      => '0',
      laneSel         => (others => '0'),
      laneRst         => (others => '0'),
      waitLaneSel     => '0',
      laneMetaRd      => '0',
      waitCnt         => (others => '0'),
      state           => IDLE_S,
      -- Registers
      discBadColTrg   => toSl(DISCARD_BAD_COL_TRG_G),
      cntRst          => '1',
      fpgaId          => FPGA_ID_DEFAULT_C,
      timeoutLimit    => TIMEOUT_LIMIT_DEFAULT_C,
      laneEnable      => LANE_ENABLE_DEFAULT_C,
      laneDecErr      => (others => '0'),
      lanePauseErr    => (others => '0'),
      laneFull        => (others => '0'),
      laneDecErrCnt   => (others => (others => '0')),
      lanePauseErrCnt => (others => (others => '0')),
      laneFullCnt     => (others => (others => '0')),
      -- AXI-Stream
      obAxisMaster    => AXI_STREAM_MASTER_INIT_C,
      laneRxSlaves    => (others => AXI_STREAM_SLAVE_INIT_C),
      -- AXI-Lite
      readSlave       => AXI_LITE_READ_SLAVE_INIT_C,
      writeSlave      => AXI_LITE_WRITE_SLAVE_INIT_C);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   U_SyncSro : entity surf.Synchronizer
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G)
      port map (
         clk     => pgpRxClk,
         dataIn  => asicSro,
         dataOut => asicSroSync);

   U_SyncSroEna : entity surf.Synchronizer
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G)
      port map (
         clk     => pgpRxClk,
         dataIn  => asicSroEna,
         dataOut => asicSroEnaSync);

   U_SyncRst : entity surf.Synchronizer
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G)
      port map (
         clk     => pgpRxClk,
         dataIn  => asicRst,
         dataOut => asicRstSync);

   U_AxiLiteAsync : entity surf.AxiLiteAsync
      generic map (
         TPD_G           => TPD_G,
         NUM_ADDR_BITS_G => 12)
      port map (
         -- Slave Interface
         sAxiClk         => axilClk,
         sAxiClkRst      => axilRst,
         sAxiReadMaster  => axilReadMaster,
         sAxiReadSlave   => axilReadSlave,
         sAxiWriteMaster => axilWriteMaster,
         sAxiWriteSlave  => axilWriteSlave,
         -- Master Interface
         mAxiClk         => pgpRxClk,
         mAxiClkRst      => pgpRxRst,
         mAxiReadMaster  => readMaster,
         mAxiReadSlave   => readSlave,
         mAxiWriteMaster => writeMaster,
         mAxiWriteSlave  => writeSlave);

   comb : process (readMaster, pgpRxRst, writeMaster, asicSroSync, obAxisSlave,
                   asicSroEnaSync, laneFrameSize, laneRst, trgBuffValid, laneFull,
                   asicRstSync, trgBuffDout, laneTimeout, laneDecError, lanePauseError,
                   laneRxMasters, laneTrgCnt, laneMetaValid, r) is

      variable v      : RegType;
      variable axilEp : AxiLiteEndpointType;

      -- internal variables
      variable preamble      : slv(FPGA_PREAMBLE_LEN_C-1 downto 0)   := (others => '0');
      variable header        : slv(FPGA_HEADER_LEN_C-1 downto 0)     := (others => '0');
      variable laneValid     : slv(NUM_OF_SERIALIZERS_C-1 downto 0)  := (others => '0');
      variable laneReady     : slv(NUM_OF_SERIALIZERS_C-1 downto 0)  := (others => '0');
      variable laneAxiStream : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
      variable laneIdx       : natural := 0;
      variable frameSize     : slv(LANERX_FRAME_SIZE_WIDTH_C-1 downto 0) := (others => '0');

      variable laneDecErrorMask : slv(NUM_OF_SERIALIZERS_C-1 downto 0)  := (others => '0');

   begin
      -- Latch the current value
      v := r;

      -- Defaults
      v.trgBuffWr  := '0';
      v.trgBuffRd  := '0';
      v.laneMetaRd := '0';
      v.cntRst     := '0';

      -- flow control check
      if obAxisSlave.tReady = '1' then
         v.obAxisMaster.tValid := '0';
         v.obAxisMaster.tLast  := '0';
         v.obAxisMaster.tUser  := (others => '0');
         v.obAxisMaster.tData  := (others => '0');
         v.obAxisMaster.tKeep  := (others => '0');
      end if;

      -- default flags
      for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop
         v.laneRxSlaves(lane).tReady := '0'; -- disable by default
      end loop;

      ----------------------------------------------------------------------------------------------
      -- AXI-Lite Transactions
      ----------------------------------------------------------------------------------------------

      -- Determine the transaction type
      axiSlaveWaitTxn(axilEp, writeMaster, readMaster, v.writeSlave, v.readSlave);

      for i in NUM_OF_SERIALIZERS_C-1 downto 0 loop
         -- (Stride=4 bytes)
         axiSlaveRegisterR(axilEp, toSlv(512+4*i,  12), 0, r.laneDecErr(i));   -- StartAddr=0x200
         axiSlaveRegisterR(axilEp, toSlv(768+4*i,  12), 0, r.lanePauseErr(i)); -- StartAddr=0x300
         axiSlaveRegisterR(axilEp, toSlv(1024+4*i, 12), 0, r.laneFull(i));     -- StartAddr=0x400
         axiSlaveRegisterR(axilEp, toSlv(1280+4*i, 12), 0, laneTrgCnt(i));     -- StartAddr=0x500
      end loop;

      axiSlaveRegister (axilEp, x"600", 0, v.fpgaId);
      axiSlaveRegister (axilEp, x"604", 0, v.timeoutLimit);
      axiSlaveRegister (axilEp, x"608", 0, v.laneEnable);
      axiSlaveRegister (axilEp, x"60C", 0, v.discBadColTrg);

      axiSlaveRegisterR(axilEp, x"610", 0, r.fpgaTrgCnt);

      axiSlaveRegister (axilEp, x"614", 0, v.cntRst);

      -- Closeout the transaction
      axiSlaveDefault(axilEp, v.writeSlave, v.readSlave, AXI_RESP_DECERR_C);
      ----------------------------------------------------------------------------------------------
      ----------------------------------------------------------------------------------------------

      -- Register inputs
      v.asicSro := asicSroSync;

      if asicRstSync = '0' then
         v.fpgaTrgCnt := FPGA_TRGCNT_DEFAULT_C;
      end if;

      -- posedge detection
      if v.asicSro = '1' and r.asicSro = '0' and asicSroEnaSync = '1' then
         v.fpgaTrgCnt := r.fpgaTrgCnt + 1;
      end if;

      -- negedge detection
      if v.asicSro = '0' and r.asicSro = '1' and asicSroEnaSync = '1' then
         v.trgBuffWr := '1';
      end if;

      -- global lane status loop;
      -- lane valid indicates data from that lane can be read-out;
      -- lane ready indicates that some action needs to be taken: either reset or read-out data
      for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop

         laneDecErrorMask(lane) := laneDecError(lane) and laneMetaValid(lane);

         laneValid(lane)     := laneRxMasters(lane).tValid and not(laneDecErrorMask(lane)) and
                                    not(laneTimeout(lane)) and not(laneFull(lane));

         if r.laneEnable(lane) = '1' then
            laneReady(lane) := (laneValid(lane) and laneMetaValid(lane)) or
                               (laneTimeout(lane) or laneFull(lane) or laneDecErrorMask(lane));
         else
            laneReady(lane) := '1';
         end if;

      end loop;

      ----------------------------------------------------------------------------------------------
      -- status counters
      v.laneDecErr   := laneDecErrorMask;
      v.lanePauseErr := lanePauseError;
      v.laneFull     := laneFull;

      for i in NUM_OF_SERIALIZERS_C-1 downto 0 loop
         -- increment counters on rising edge
         if  (v.laneDecErr(i) = '1' and r.laneDecErr(i) = '0') and (r.laneEnable(i) = '1')
         and (r.laneDecErrCnt(i) /= MAX_CNT_C) then
            v.laneDecErrCnt(i) := r.laneDecErrCnt(i) + 1;
         end if;

         if  (v.lanePauseErr(i) = '1' and r.lanePauseErr(i) = '0') and (r.laneEnable(i) = '1')
         and (r.lanePauseErrCnt(i) /= MAX_CNT_C) then
            v.lanePauseErrCnt(i) := r.lanePauseErrCnt(i) + 1;
         end if;

         if  (v.laneFull(i) = '1' and r.laneFull(i) = '0') and (r.laneEnable(i) = '1')
         and (r.laneFullCnt(i) /= MAX_CNT_C) then
            v.laneFullCnt(i) := r.laneFullCnt(i) + 1;
         end if;

         if (r.cntRst = '1') then
            v.laneDecErrCnt(i)   := (others => '0');
            v.lanePauseErrCnt(i) := (others => '0');
            v.laneFullCnt(i)     := (others => '0');
         end if;
      end loop;
      ----------------------------------------------------------------------------------------------

      preamble := fpgaPreambleMap(PIX2PGP_ID_C,
                                  toSlv(ASIC_TYPE_C, 32),
                                  toSlv(ASIC_ID_G, 32),
                                  r.fpgaId,
                                  r.trgCntBuff);

      header := fpgaHeaderMap(laneDecErrorMask,
                              lanePauseError,
                              laneFull,
                              laneTimeout,
                              laneValid);

      laneIdx := conv_integer(unsigned(r.laneSel));

      laneAxiStream := laneRxMasters(laneIdx);

      frameSize := laneFrameSize(laneIdx);

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- wait for a word to be written into the sro/trigger buffer
         when IDLE_S =>
            v.armTimeout := '0';
            v.laneRst    := (others => '0');
            v.laneSel    := (others => '0');

            -- new trigger in queue; start read-out
            if trgBuffValid = '1' and toBoolean(uOr(r.laneEnable)) then
               v.trgCntBuff := trgBuffDout;
               v.armTimeout := '1';
               v.state      := TX_PREAMBLE_S;
            end if;

            -- or...error detected
            if toBoolean(uOr(laneDecErrorMask)) then
               v.armTimeout := '1';
               v.state      := TX_PREAMBLE_S;
            end if;

         ----------------------------------------------------------------------
         -- transmit the pix2pgp preamble via axi
         when TX_PREAMBLE_S =>
            if v.obAxisMaster.tValid = '0' then
               v.obAxisMaster.tValid := '1';

               v.obAxisMaster.tKeep  := tKeepSet(FPGA_PREAMBLE_LEN_C);
               ssiSetUserSof(FPGA_RX_AXI_CONFIG_C, v.obAxisMaster, '1');
               v.obAxisMaster.tData(FPGA_PREAMBLE_LEN_C-1 downto 0) := preamble;
               v.state := WAIT_LANES_S;
            end if;

         ----------------------------------------------------------------------
         -- wait for lanes to present data
         when WAIT_LANES_S =>

            if v.obAxisMaster.tValid = '0' then
               -- done; either all lanes are valid, or all in timeout/error state
               if allBits(laneReady, '1') then
                  v.obAxisMaster.tValid := '1';

                  v.obAxisMaster.tKeep := tKeepSet(FPGA_HEADER_LEN_C);
                  v.obAxisMaster.tData(FPGA_HEADER_LEN_C-1 downto 0) := header;

                  -- reset the troubled lanes
                  for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop
                     v.laneRst(lane) := laneDecErrorMask(lane) or
                                        laneTimeout(lane) or
                                        laneFull(lane);
                  end loop;

                  v.armTimeout := '0'; -- release timeout

                  v.state := TX_FRAME_SIZE_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- transmit all (valid) lane frame size data
         when TX_FRAME_SIZE_S =>
            if v.obAxisMaster.tValid = '0' then

               v.obAxisMaster.tValid := '1';
               v.obAxisMaster.tKeep  := tKeepSet(LANERX_FRAME_SIZE_WIDTH_C);
               v.obAxisMaster.tData(LANERX_FRAME_SIZE_WIDTH_C-1 downto 0) := frameSize;

               if laneValid(laneIdx) = '0' then
                  v.obAxisMaster.tData(LANERX_FRAME_SIZE_WIDTH_C-1 downto 0) := (others => '0');
               end if;

               if laneIdx = NUM_OF_SERIALIZERS_C-1 then
                  v.laneSel := (others => '0');
                  v.state := SWITCH_MUX_S;
               else
                  v.laneSel := r.laneSel + 1;
               end if;

            end if;


         ----------------------------------------------------------------------
         -- check if the current lane has any valid data
         when SWITCH_MUX_S =>
            if laneValid(laneIdx) = '0' then
               --
               if laneIdx = NUM_OF_SERIALIZERS_C-1 then
                  v.state := TX_TRAILER_S;
               else
                  v.laneSel := r.laneSel + 1;
               end if;

            else

               v.state := WAIT_TLAST_S;

            end if;

         ----------------------------------------------------------------------
         -- switch mux to the lane with the valid data until done
         -- reverse endianness on a per-ASIC-word basis
         when WAIT_TLAST_S =>
            if v.obAxisMaster.tValid = '0' then
               axiStreamEndianSwap(laneAxiStream,
                                   FPGA_RX_AXI_CONFIG_C,
                                   ASIC_DATA_AXI_CONFIG_C.TDATA_BYTES_C);

               v.obAxisMaster.tKeep := laneAxiStream.tKeep;
               v.obAxisMaster.tData := laneAxiStream.tData;

               v.obAxisMaster.tValid          := laneRxMasters(laneIdx).tValid;
               v.laneRxSlaves(laneIdx).tReady := obAxisSlave.tReady;

               if laneRxMasters(laneIdx).tLast = '1' and
                  obAxisSlave.tReady           = '1' then

                  v.state := SWITCH_MUX_S;

                  -- that was it; transmit trailer
                  if laneIdx = NUM_OF_SERIALIZERS_C-1 then
                     v.state := TX_TRAILER_S;
                  else
                     v.laneSel := r.laneSel + 1;
                  end if;

               end if;
            end if;

         ----------------------------------------------------------------------
         -- transmit trailer;
         -- also acknowledge any errors and reset the timeout watchdog
         when TX_TRAILER_S =>
            if v.obAxisMaster.tValid = '0' then
               v.obAxisMaster.tKeep  := tKeepSet(FPGA_TRAILER_LEN_C);
               v.obAxisMaster.tData(FPGA_TRAILER_LEN_C-1 downto 0) :=
                  resize(PIX2PGP_ID_C, FPGA_TRAILER_LEN_C);
               v.obAxisMaster.tValid := '1';
               v.obAxisMaster.tLast  := '1';
               v.laneMetaRd          := '1';
               v.trgBuffRd           := '1';
               v.state               := DONE_S;
            end if;

         ----------------------------------------------------------------------
         -- wait before re-evaluating FIFO valid signals
         when DONE_S =>
            v.waitCnt := r.waitCnt + 1;

            if allBits(r.waitCnt, '1') then
               v.waitCnt := (others => '0');
               v.state   := IDLE_S;
            end if;

      end case;
      -----------------------------------------------------------------------


      ----------------------------------------------------------------------------------------------
      -- Outputs
      ----------------------------------------------------------------------------------------------

      for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop
         timeoutLimit(lane)  <= r.timeoutLimit;
         armTimeout(lane)    <= r.armTimeout and not(laneValid(lane));
         discBadColTrg(lane) <= r.discBadColTrg; -- fan-out
         laneMetaRd(lane)    <= r.laneMetaRd;    -- fan-out

         -- enable mapping
         if RST_POLARITY_G = '1' then
            laneRst(lane) <= pgpRxRst or r.laneRst(lane) or not(r.laneEnable(lane));
         else
            laneRst(lane) <= pgpRxRst and not(r.laneRst(lane)) and(r.laneEnable(lane));
         end if;

      end loop;

      -- endianness swap (per-byte)
      axiStreamEndianSwap(v.obAxisMaster, FPGA_RX_AXI_CONFIG_C, 1);

      -- AXI-Stream Outputs
      laneRxSlaves <= v.laneRxSlaves;
      obAxisMaster <= r.obAxisMaster;

      -- AXI-Lite Outputs
      writeSlave <= r.writeSlave;
      readSlave  <= r.readSlave;

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

   ----------------------------------------
   -- Trigger/SRO Buffer
   ----------------------------------------
   U_TriggerBuffer : entity surf.Fifo
      generic map (
         TPD_G           => TPD_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         MEMORY_TYPE_G   => "block",
         FWFT_EN_G       => true,
         DATA_WIDTH_G    => TRGCNT_WIDTH_C,
         ADDR_WIDTH_G    => 6)
      port map (
         rst      => pgpRxRst,
         -- Write Ports
         wr_clk   => pgpRxClk,
         wr_en    => r.trgBuffWr,
         din      => r.fpgaTrgCnt,
         -- Read Ports
         rd_clk   => pgpRxClk,
         rd_en    => r.trgBuffRd,
         dout     => trgBuffDout,
         valid    => trgBuffValid);

   -----------------
   -- Lane Receivers
   -----------------
   GEN_LANE: for lane in 0 to NUM_OF_SERIALIZERS_C-1 generate

      U_LaneWrapper: entity pix2pgp.Pix2PgpLaneRxWrapper
         generic map(
            TPD_G                       => TPD_G,
            RST_ASYNC_G                 => RST_ASYNC_G,
            RST_POLARITY_G              => RST_POLARITY_G,
            PIPE_STAGES_G               => LANE_PIPE_STAGES_G,
            META_FIFO_ADDR_WIDTH_G      => META_FIFO_ADDR_WIDTH_G,
            LANE_AXIS_FIFO_ADDR_WIDTH_G => LANE_AXIS_FIFO_ADDR_WIDTH_G,
            FILT_AXIS_FIFO_ADDR_WIDTH_G => FILT_AXIS_FIFO_ADDR_WIDTH_G)
         port map(
            -- General Interface
            laneClk        => pgpRxClk,
            laneRst        => laneRst(lane),
            -- RX FIFO Interface
            pgp4RxMaster   => pgp4RxMaster(lane),
            pgp4RxSlave    => pgp4RxSlave(lane),
            -- ASIC Rx Interface
            discBadColTrg  => discBadColTrg(lane),
            laneTrgCnt     => laneTrgCnt(lane),
            laneFrameSize  => laneFrameSize(lane),
            laneDecError   => laneDecError(lane),
            laneFull       => laneFull(lane),
            lanePauseError => lanePauseError(lane),
            laneMetaValid  => laneMetaValid(lane),
            laneMetaRd     => laneMetaRd(lane),
            laneRxMaster   => laneRxMasters(lane),
            laneRxSlave    => laneRxSlaves(lane));

      -- Watchdog (on a per-lane basis)
      U_Watchdog : entity pix2pgp.Pix2PgpWatchdog
         generic map(
            TPD_G          => TPD_G,
            RST_ASYNC_G    => RST_ASYNC_G,
            RST_POLARITY_G => RST_POLARITY_G,
            CNT_WIDTH_G    => TIMEOUT_LIMIT_WIDTH_G)
         port map(
            -- General Interface
            clk     => pgpRxClk,
            rst     => pgpRxRst,
            limit   => timeoutLimitDly(lane),
            -- Control Interface
            set     => armTimeoutDly(lane),
            timeout => timeout(lane));

      U_PipelineWatchdogTimeout : entity surf.SlvDelay
         generic map (
            TPD_G          => TPD_G,
            RST_POLARITY_G => RST_POLARITY_G,
            WIDTH_G        => TIMEOUT_LIMIT_WIDTH_G,
            DELAY_G        => 2)
         port map (
            clk  => pgpRxClk,
            din  => timeoutLimit(lane),
            dout => timeoutLimitDly(lane));

   end generate GEN_LANE;

   U_PipelineArmTimeout : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => NUM_OF_SERIALIZERS_C,
         DELAY_G        => 2)
      port map (
         clk  => pgpRxClk,
         din  => armTimeout,
         dout => armTimeoutDly);

   U_PipelineTimeout : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => NUM_OF_SERIALIZERS_C,
         DELAY_G        => 2)
      port map (
         clk  => pgpRxClk,
         din  => timeout,
         dout => laneTimeout);

   --------------------------
   -- Pipeline Stage (or not)
   --------------------------
   GEN_PIPE: if STREAM_PIPE_STAGES_G > 0 generate

      U_Pipe : entity surf.AxiStreamPipeline
         generic map (
            TPD_G          => TPD_G,
            RST_ASYNC_G    => RST_ASYNC_G,
            RST_POLARITY_G => RST_POLARITY_G,
            PIPE_STAGES_G  => STREAM_PIPE_STAGES_G)
         port map (
            -- Clock and Reset
            axisClk     => pgpRxClk,
            axisRst     => pgpRxRst,
            -- Slave Port
            sAxisMaster => obAxisMaster,
            sAxisSlave  => obAxisSlave,
            -- Master Port
            mAxisMaster => asicRxMaster,
            mAxisSlave  => asicRxSlave);

   end generate GEN_PIPE;

   GEN_NO_PIPE: if STREAM_PIPE_STAGES_G <= 0 generate

      asicRxMaster <= obAxisMaster;
      obAxisSlave  <= asicRxSlave;

   end generate GEN_NO_PIPE;


end rtl;
