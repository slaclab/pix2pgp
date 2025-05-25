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
      TPD_G                  : time     := 1 ns;
      RST_ASYNC_G            : boolean  := false;
      RST_POLARITY_G         : sl       := '1';  -- '1' for active high rst, '0' for active low
      ASIC_ID_G              : natural  := 0;
      TIMEOUT_LIMIT_WIDTH_G  : positive := 12;
      LANE_PIPE_STAGES_G     : natural  := 1;
      STREAM_PIPE_STAGES_G   : natural  := 1;
      TRG_FIFO_ADDR_WIDTH_G  : positive := 6;
      META_FIFO_ADDR_WIDTH_G : positive := 6;
      AXIS_FIFO_ADDR_WIDTH_G : positive := 6;
      DROP_BAD_COL_TRG_G     : boolean  := true);
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
   constant MAX_CNT_C               : slv(4 downto 0) := (others => '1');

   signal laneRxMasters   : AxiStreamMasterArray(NUM_OF_SERIALIZERS_C-1 downto 0)
                          := (others => AXI_STREAM_MASTER_INIT_C);
   signal laneRxSlaves    : AxiStreamSlaveArray(NUM_OF_SERIALIZERS_C-1 downto 0)
                          := (others => AXI_STREAM_SLAVE_INIT_C);

   type TrgCntArray is array (NUM_OF_SERIALIZERS_C-1 downto 0) of slv(TRGCNT_WIDTH_C-1 downto 0);

   signal laneStatus      : Pix2PgpLaneStatusArray := (others => DEFAULT_PIX2PGP_LANESTATUS_C);

   signal asicSroSync     : sl := '0';
   signal asicSroEnaSync  : sl := '0';
   signal asicRstSync     : sl := '0';

   signal trgBuffDout     : slv(TRGCNT_WIDTH_C-1 downto 0) := (others => '0');
   signal trgBuffValid    : sl := '0';
   signal timeout         : sl := '0';

   signal readMaster      : AxiLiteReadMasterType;
   signal readSlave       : AxiLiteReadSlaveType;
   signal writeMaster     : AxiLiteWriteMasterType;
   signal writeSlave      : AxiLiteWriteSlaveType;

   signal laneRst         : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => not(RST_POLARITY_G));

   signal dropBadColTrg   : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal lanePostError   : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal obAxisMaster    : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal obAxisSlave     : AxiStreamSlaveType  := AXI_STREAM_SLAVE_INIT_C;

   signal laneMetaValid   : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal laneMetaRd      : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   type StateType is (
      IDLE_S,
      TX_PREAMBLE_S,
      EVAL_LANES_S,
      TX_HEADER_S,
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
      laneRst         : sl;
      lanePostError   : sl;
      laneEval        : sl;
      laneSel         : slv(BITMAX_SERIALIZERS_C downto 0);
      laneReady       : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneValid       : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneTimeout     : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneTrgCnt      : TrgCntArray;
      waitLaneSel     : sl;
      laneMetaRd      : sl;
      asicEnable      : sl;
      waitCnt         : slv(3 downto 0);
      state           : StateType;
      -- Registers
      dropBadColTrg   : sl;
      cntRst          : sl;
      fpgaId          : slv(15 downto 0);
      timeoutLimit    : slv(TIMEOUT_LIMIT_WIDTH_G-1 downto 0);
      laneEnable      : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneEnableSet   : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneDecError    : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      lanePauseError  : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneOverOcc     : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      lanePause       : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
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
      lanePostError   => '0',
      laneEval        => '0',
      armTimeout      => '0',
      laneRst         => '0',
      laneSel         => (others => '0'),
      laneReady       => (others => '0'),
      laneValid       => (others => '0'),
      laneTimeout     => (others => '0'),
      laneTrgCnt      => (others => (others => '0')),
      waitLaneSel     => '0',
      laneMetaRd      => '0',
      asicEnable      => '0',
      waitCnt         => (others => '0'),
      state           => IDLE_S,
      -- Registers
      dropBadColTrg   => toSl(DROP_BAD_COL_TRG_G),
      cntRst          => '1',
      fpgaId          => FPGA_ID_DEFAULT_C,
      timeoutLimit    => TIMEOUT_LIMIT_DEFAULT_C,
      laneEnable      => (others => '0'),
      laneEnableSet   => LANE_ENABLE_DEFAULT_C,
      laneDecError    => (others => '0'),
      lanePauseError  => (others => '0'),
      laneOverOcc     => (others => '0'),
      lanePause       => (others => '0'),
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
                   asicSroEnaSync, trgBuffValid, laneStatus, asicRstSync,
                   trgBuffDout, timeout, laneRxMasters, r) is

      variable v      : RegType;
      variable axilEp : AxiLiteEndpointType;

      -- internal variables
      variable preamble      : slv(FPGA_PREAMBLE_LEN_C-1 downto 0)   := (others => '0');
      variable header        : slv(FPGA_HEADER_LEN_C-1 downto 0)     := (others => '0');
      variable laneAxiStream : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
      variable laneIdx       : natural := 0;
      variable frameSize     : slv(STREAMRX_FRAME_SIZE_WIDTH_C-1 downto 0) := (others => '0');

      variable laneOk        : slv(NUM_OF_SERIALIZERS_C-1 downto 0)  := (others => '0');
      variable laneInError   : slv(NUM_OF_SERIALIZERS_C-1 downto 0)  := (others => '0');

      variable laneTrgCntRef : slv(TRGCNT_WIDTH_C-1 downto 0) := (others => '0');
      variable trgMisalign   : sl := '0';
      variable inPause       : sl := '0';

   begin
      -- Latch the current value
      v := r;

      -- Defaults
      v.trgBuffWr   := '0';
      v.trgBuffRd   := '0';
      v.laneMetaRd  := '0';
      v.cntRst      := '0';
      v.armTimeout  := '0';
      v.asicEnable  := '0';
      v.laneTimeout := (others => '0');

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
         axiSlaveRegisterR(axilEp, toSlv(512+4*i,  12), 0, r.laneDecErrCnt(i));   -- StartAddr=0x200
         axiSlaveRegisterR(axilEp, toSlv(768+4*i,  12), 0, r.lanePauseErrCnt(i)); -- StartAddr=0x300
         axiSlaveRegisterR(axilEp, toSlv(1024+4*i, 12), 0, r.laneFullCnt(i));     -- StartAddr=0x400
         axiSlaveRegisterR(axilEp, toSlv(1280+4*i, 12), 0, laneStatus(i).trgCnt); -- StartAddr=0x500
      end loop;

      axiSlaveRegisterR(axilEp, x"600", 0, r.fpgaTrgCnt);

      axiSlaveRegister (axilEp, x"604", 0, v.fpgaId);
      axiSlaveRegister (axilEp, x"608", 0, v.timeoutLimit);
      axiSlaveRegister (axilEp, x"60C", 0, v.laneEnableSet);
      axiSlaveRegister (axilEp, x"610", 0, v.dropBadColTrg);

      axiSlaveRegister (axilEp, x"614", 0, v.cntRst);
      axiSlaveRegisterR(axilEp, x"618", 0, laneOk);
      axiSlaveRegisterR(axilEp, x"61C", 0, laneInError);
      axiSlaveRegisterR(axilEp, x"620", 0, r.laneFull);
      axiSlaveRegisterR(axilEp, x"624", 0, r.asicEnable);

      -- Closeout the transaction
      axiSlaveDefault(axilEp, v.writeSlave, v.readSlave, AXI_RESP_DECERR_C);
      ----------------------------------------------------------------------------------------------
      ----------------------------------------------------------------------------------------------

      -- Register inputs
      v.asicSro := asicSroSync;

      -- trigger counter management
      -------------------------------

      -- used in downstream logic
      if (asicRstSync and uOr(r.laneEnableSet)) = '1' then
         v.asicEnable := '1';
      end if;

      if asicRstSync = '0' then
         v.fpgaTrgCnt := FPGA_TRGCNT_DEFAULT_C;
      end if;

      -- posedge detection
      if v.asicSro = '1' and r.asicSro = '0' and asicSroEnaSync = '1' and r.asicEnable = '1' then
         v.fpgaTrgCnt := r.fpgaTrgCnt + 1;
      end if;

      -- negedge detection
      if v.asicSro = '0' and r.asicSro = '1' and asicSroEnaSync = '1' and r.asicEnable = '1' then
         v.trgBuffWr := '1';
      end if;
      -------------------------------

      -- global lane status loop;
      -- lane valid indicates data from that lane can be read-out;
      -- lane ready indicates that some action needs to be taken: either reset or read-out data
      for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop

         -- not from metadata FIFO
         v.laneFull(lane)     := laneStatus(lane).overflow;
         laneOk(lane)         := laneStatus(lane).rxOk;
         laneInError(lane)    := laneStatus(lane).inError;

         -- from metadata FIFO
         v.lanePauseError(lane) := laneStatus(lane).pauseError and laneStatus(lane).valid;
         v.laneOverOcc(lane)    := laneStatus(lane).overOcc and laneStatus(lane).valid;
         v.lanePause(lane)      := laneStatus(lane).pause and laneStatus(lane).valid;
         v.laneDecError(lane)   := laneStatus(lane).decError and laneStatus(lane).valid;

         v.laneEnable(lane) := r.laneEnableSet(lane) and r.asicEnable;

         if r.laneEval = '1' then

            inPause := '0'; -- always reset this flag when re-evaluating the lane statuses

            if timeout = '1' and r.laneValid(lane) = '0' and r.laneReady(lane) = '0' then
               v.laneTimeout(lane) := '1';
            end if;

            if r.laneEnable(lane) = '1' and r.laneTimeout(lane) = '0' then
               v.laneReady(lane) := (r.laneValid(lane) and laneStatus(lane).valid) or
                                    (laneStatus(lane).overflow or r.laneDecError(lane));
            else
               v.laneReady(lane) := '1';
            end if;

            -- check for pause
            if uOr(r.lanePause) = '0' then
               v.laneValid(lane) := (laneRxMasters(lane).tValid) and
                                       not(r.laneDecError(lane)) and
                                       not(laneStatus(lane).overflow);

            else

               v.laneValid(lane) := (laneRxMasters(lane).tValid) and
                                       not(r.laneDecError(lane)) and
                                  not(laneStatus(lane).overflow) and
                                     (r.lanePause(lane)); -- drain only in-pause lanes

            end if;

         end if;

      end loop;

      if r.laneEval = '1' then
         -- set timeout counter if not all ready and if the state is not changing
         if uOr(r.laneReady) = '1' and uAnd(r.laneReady) = '0' and r.laneReady = v.laneReady then
            v.armTimeout := '1';
         end if;

      end if;

      ----------------------------------------------------------------------------------------------

      for i in NUM_OF_SERIALIZERS_C-1 downto 0 loop
         -- increment counters on rising edge
         if  (v.laneDecError(i) = '1' and r.laneDecError(i) = '0') and (r.laneEnable(i) = '1')
         and (r.laneDecErrCnt(i) /= MAX_CNT_C) then
            v.laneDecErrCnt(i) := r.laneDecErrCnt(i) + 1;
         end if;

         if  (v.lanePauseError(i) = '1' and r.lanePauseError(i) = '0') and (r.laneEnable(i) = '1')
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

      header := fpgaHeaderMap(r.laneDecError,
                              r.laneOverOcc,
                              r.lanePause,
                              r.lanePauseError,
                              r.laneFull,
                              r.laneTimeout,
                              r.laneValid);

      laneIdx := conv_integer(unsigned(r.laneSel));

      laneAxiStream := laneRxMasters(laneIdx);

      frameSize := resize(laneStatus(laneIdx).frameSize, STREAMRX_FRAME_SIZE_WIDTH_C);

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------

         ----------------------------------------------------------------------
         -- wait for a word to be written into the sro/trigger buffer
         when IDLE_S =>
            v.laneRst       := '0';
            v.lanePostError := '0';
            v.waitCnt       := (others => '0');

            -- first check if anything is enabled
            if uOr(r.laneEnable) = '1' then

               -- if got full, go-to reset state
               if uOr(r.laneFull) = '1' then
                  v.state := DONE_S;

               -- nominal operation; new trigger in buffer
               elsif trgBuffValid = '1' then
                  v.trgCntBuff := trgBuffDout;
                  v.state      := TX_PREAMBLE_S;
               end if;

            end if;

         ----------------------------------------------------------------------
         -- transmit the pix2pgp preamble via axi
         when TX_PREAMBLE_S =>
            if v.obAxisMaster.tValid = '0' then
               v.obAxisMaster.tValid := '1';

               v.obAxisMaster.tKeep  := tKeepSet(FPGA_PREAMBLE_LEN_C);
               ssiSetUserSof(PIX2PGP_FPGA_AXI_CONFIG_C, v.obAxisMaster, '1');
               v.obAxisMaster.tData(FPGA_PREAMBLE_LEN_C-1 downto 0) := preamble;
               v.state := EVAL_LANES_S;
            end if;

         ----------------------------------------------------------------------
         -- wait for lanes to present data;
         -- evaluate, change, and register statuses
         when EVAL_LANES_S =>

            v.laneEval := '1';

            -- observe the behavior for pause:
            -- if any lane is in-pause -> wait a bit before draining *only* the paused lanes

            -- check for pause
            if uOr(r.lanePause) = '0' then

               if uAnd(r.laneReady) = '1' then
                  v.state := TX_HEADER_S;
               end if;

            else

               v.waitCnt := r.waitCnt + 1;

               if allBits(r.waitCnt, '1') then
                  v.waitCnt := (others => '0');
                  v.state   := TX_HEADER_S;
               end if;

            end if;

         ----------------------------------------------------------------------
         -- transmit event header infromation
         when TX_HEADER_S =>

            v.laneEval := '0'; -- freeze the lane statuses

            -- essentially waits for all lanes to have something; either valid data or some error
            if v.obAxisMaster.tValid = '0' then

               v.obAxisMaster.tValid := '1';

               v.obAxisMaster.tKeep := tKeepSet(FPGA_HEADER_LEN_C);
               v.obAxisMaster.tData(FPGA_HEADER_LEN_C-1 downto 0) := header;

               v.state := TX_FRAME_SIZE_S;

            end if;

         ----------------------------------------------------------------------
         -- transmit all (valid) lane frame size data
         -- also grab the trigger counter values; will evaluate alignment later
         when TX_FRAME_SIZE_S =>
            if v.obAxisMaster.tValid = '0' then

               v.obAxisMaster.tValid := '1';
               v.obAxisMaster.tKeep  := tKeepSet(STREAMRX_FRAME_SIZE_WIDTH_C);
               v.obAxisMaster.tData(STREAMRX_FRAME_SIZE_WIDTH_C-1 downto 0) := frameSize;
               v.laneTrgCnt(laneIdx) := laneStatus(laneIdx).trgCnt;

               if r.laneValid(laneIdx) = '0' then
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
            if r.laneValid(laneIdx) = '0' then
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
         -- transmit trailer and pop the trigger count;
         -- but only if this was not a pause event
         when TX_TRAILER_S =>

            if uOr(r.lanePause) = '0' then

               if v.obAxisMaster.tValid = '0' then
                  v.obAxisMaster.tKeep  := tKeepSet(FPGA_TRAILER_LEN_C);
                  v.obAxisMaster.tData(FPGA_TRAILER_LEN_C-1 downto 0) :=
                     resize(PIX2PGP_ID_C, FPGA_TRAILER_LEN_C);
                  v.obAxisMaster.tValid := '1';
                  v.obAxisMaster.tLast  := '1';
                  v.trgBuffRd           := '1';

               end if;

            else

               inPause := '1';

            end if;

            v.laneMetaRd := '1';
            v.state      := DONE_S;

         ----------------------------------------------------------------------
         -- pop the metadata and internal trigger buffer info FIFOs;
         -- check the trigger counters and make sure they have the same value;
         -- issue resets if necessary
         when DONE_S =>
            trgMisalign := '0';
            v.laneSel   := (others => '0');
            v.laneReady := (others => '0');
            v.laneValid := (others => '0');
            v.waitCnt   := r.waitCnt + 1;

            -- check if every trigger is aligned:
            -- first get the first valid trigger...
            for lane in NUM_OF_SERIALIZERS_C-1 downto 0 loop
               if r.laneValid(lane) = '1' and r.laneDecError(lane) = '0' then
                  laneTrgCntRef := r.laneTrgCnt(lane);
                  exit;
               end if;
            end loop;

            -- then check against the rest...
            for lane in NUM_OF_SERIALIZERS_C-1 downto 0 loop
               if r.laneValid(lane) = '1' and r.laneDecError(lane) = '0' then
                  if r.laneTrgCnt(lane) /= laneTrgCntRef then
                     trgMisalign := '1';
                     exit;
                  end if;
               end if;
            end loop;

            -- reset all lanes in case of error;
            -- cannot just reset one lane -> if we do that, it will lead to trg misalignment
            if (uOr(r.laneDecError) or uOr(r.laneTimeout) or
                uOr(r.laneFull)     or trgMisalign) = '1' and r.laneRst = '0' then
               v.laneRst       := '1';
               v.lanePostError := '1';
            end if;

            if r.waitCnt = toSlv(4, r.waitCnt'length) then

               v.state := IDLE_S;

               if inPause = '1' and r.lanePostError = '0' then
                  v.state := EVAL_LANES_S;
               end if;

            elsif r.waitCnt = toSlv(2, r.waitCnt'length) then
               v.laneRst := '0';
            end if;

      end case;
      -------------------------------------------------------------------------


      ----------------------------------------------------------------------------------------------
      -- Outputs
      ----------------------------------------------------------------------------------------------
      for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop
         dropBadColTrg(lane) <= r.dropBadColTrg; -- fan-out
         lanePostError(lane) <= r.lanePostError; -- fan-out

         laneMetaRd(lane) <= r.laneMetaRd and (r.laneValid(lane)); -- only read the valid lanes

         -- enable mapping
         if RST_POLARITY_G = '1' then
            laneRst(lane) <= pgpRxRst or r.laneRst or not(r.laneEnable(lane));
         else
            laneRst(lane) <= pgpRxRst and not(r.laneRst) and(r.laneEnable(lane));
         end if;

      end loop;

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
         ADDR_WIDTH_G    => TRG_FIFO_ADDR_WIDTH_G)
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
            TPD_G                  => TPD_G,
            RST_ASYNC_G            => RST_ASYNC_G,
            RST_POLARITY_G         => RST_POLARITY_G,
            PIPE_STAGES_G          => LANE_PIPE_STAGES_G,
            META_FIFO_ADDR_WIDTH_G => META_FIFO_ADDR_WIDTH_G,
            AXIS_FIFO_ADDR_WIDTH_G => AXIS_FIFO_ADDR_WIDTH_G)
         port map(
            -- General Interface
            laneClk        => pgpRxClk,
            laneRst        => laneRst(lane),
            -- RX FIFO Interface
            pgp4RxMaster   => pgp4RxMaster(lane),
            pgp4RxSlave    => pgp4RxSlave(lane),
            -- ASIC Rx Interface
            dropBadColTrg  => dropBadColTrg(lane),
            lanePostError  => lanePostError(lane),
            laneStatus     => laneStatus(lane),
            laneMetaRd     => laneMetaRd(lane),
            laneRxMaster   => laneRxMasters(lane),
            laneRxSlave    => laneRxSlaves(lane));

   end generate GEN_LANE;

      -- Watchdog
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
            limit   => r.timeoutLimit,
            -- Control Interface
            set     => r.armTimeout,
            timeout => timeout);

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
