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
      TIMEOUT_LIMIT_WIDTH_G  : positive := 16;
      LANE_PIPE_STAGES_G     : natural  := 1;
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
      asicSroEn       : in  sl;
      -- PGP4Rx Input Interface (on pgpRxClk domain)
      pgp4RxMaster    : in  AxiStreamMasterArray;
      pgp4RxSlave     : out AxiStreamSlaveArray;
      pgp4RxLinkUp    : in  slv(NUM_OF_SERIALIZERS_C-1 downto 0);
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

   signal laneRxMasters : AxiStreamMasterArray(NUM_OF_SERIALIZERS_C-1 downto 0)
                        := (others => AXI_STREAM_MASTER_INIT_C);
   signal laneRxSlaves  : AxiStreamSlaveArray(NUM_OF_SERIALIZERS_C-1 downto 0)
                        := (others => AXI_STREAM_SLAVE_INIT_C);

   type TrgCntArray is array (NUM_OF_SERIALIZERS_C-1 downto 0) of slv(TRGCNT_WIDTH_C-1 downto 0);

   signal laneStatus    : Pix2PgpLaneStatusArray := (others => DEFAULT_PIX2PGP_LANESTATUS_C);

   signal asicSroSync   : sl := '0';
   signal asicSroEnSync : sl := '0';
   signal asicRstSync   : sl := '0';

   signal glblRst       : sl := not(RST_POLARITY_G);
   signal usrRst        : sl := not(RST_POLARITY_G);

   signal trgBuffDout   : slv(TRGCNT_WIDTH_C-1 downto 0) := (others => '0');
   signal trgBuffValid  : sl  := '0';
   signal timeout       : sl  := '0';
   signal axiFifoRst    : sl  := '0';
   signal linkUpSync    : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal readMaster    : AxiLiteReadMasterType;
   signal readSlave     : AxiLiteReadSlaveType;
   signal writeMaster   : AxiLiteWriteMasterType;
   signal writeSlave    : AxiLiteWriteSlaveType;

   signal laneRst       : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => not(RST_POLARITY_G));

   signal dropBadColTrg : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal lanePostError : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal laneMetaValid : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal laneMetaRd    : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   type LaneUpCntArray is array (NUM_OF_SERIALIZERS_C-1 downto 0) of slv(7 downto 0);

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
      laneSel         : slv(BITMAX_SERIALIZERS_C downto 0);
      laneReady       : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneValid       : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneTimeout     : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneTrgCnt      : TrgCntArray;
      laneUpCnt       : LaneUpCntArray;
      waitLaneSel     : sl;
      laneMetaRd      : sl;
      waitCnt         : slv(3 downto 0);
      state           : StateType;
      -- Registers
      dropBadColTrg   : sl;
      cntRst          : sl;
      usrRst          : sl;
      fpgaId          : slv(15 downto 0);
      timeoutLimit    : slv(TIMEOUT_LIMIT_WIDTH_G-1 downto 0);
      laneEnable      : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneEnableSet   : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneDecError    : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      lanePauseError  : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneOverOcc     : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      lanePause       : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneFull        : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneStable      : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneDecErrCnt   : Slv5Array(NUM_OF_SERIALIZERS_C-1 downto 0);
      lanePauseErrCnt : Slv5Array(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneFullCnt     : Slv5Array(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- AXI-Stream
      asicRxMaster    : AxiStreamMasterType;
      laneRxSlaves    : AxiStreamSlaveArray(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- AXI-Lite
      readSlave       : AxiLiteReadSlaveType;
      writeSlave      : AxiLiteWriteSlaveType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- Internal
      asicSro         => '0',
      fpgaTrgCnt      => (others => '1'),
      trgBuffWr       => '0',
      trgBuffRd       => '0',
      trgCntBuff      => (others => '0'),
      lanePostError   => '0',
      armTimeout      => '0',
      laneRst         => '0',
      laneSel         => (others => '0'),
      laneReady       => (others => '0'),
      laneValid       => (others => '0'),
      laneTimeout     => (others => '0'),
      laneTrgCnt      => (others => (others => '0')),
      laneUpCnt       => (others => (others => '0')),
      waitLaneSel     => '0',
      laneMetaRd      => '0',
      waitCnt         => (others => '0'),
      state           => IDLE_S,
      -- Registers
      dropBadColTrg   => toSl(DROP_BAD_COL_TRG_G),
      cntRst          => '1',
      usrRst          => not(RST_POLARITY_G),
      fpgaId          => FPGA_ID_DEFAULT_C,
      timeoutLimit    => (others => '1'),
      laneEnable      => (others => '0'),
      laneEnableSet   => (others => '1'),
      laneDecError    => (others => '0'),
      lanePauseError  => (others => '0'),
      laneOverOcc     => (others => '0'),
      lanePause       => (others => '0'),
      laneFull        => (others => '0'),
      laneStable      => (others => '0'),
      laneDecErrCnt   => (others => (others => '0')),
      lanePauseErrCnt => (others => (others => '0')),
      laneFullCnt     => (others => (others => '0')),
      -- AXI-Stream
      asicRxMaster    => AXI_STREAM_MASTER_INIT_C,
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

   U_SyncSroEn : entity surf.Synchronizer
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G)
      port map (
         clk     => pgpRxClk,
         dataIn  => asicSroEn,
         dataOut => asicSroEnSync);

   U_SyncRst : entity surf.Synchronizer
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G)
      port map (
         clk     => pgpRxClk,
         dataIn  => asicRst,
         dataOut => asicRstSync);

   U_SyncLinkUp : entity surf.SynchronizerVector
      generic map (
         TPD_G   => TPD_G,
         WIDTH_G => NUM_OF_SERIALIZERS_C)
      port map (
         clk     => pgpRxClk,
         dataIn  => pgp4RxLinkUp,
         dataOut => linkUpSync);

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
         mAxiClkRst      => glblRst,
         mAxiReadMaster  => readMaster,
         mAxiReadSlave   => readSlave,
         mAxiWriteMaster => writeMaster,
         mAxiWriteSlave  => writeSlave);

   comb : process (readMaster, glblRst, writeMaster, asicSroSync, asicRxSlave,
                   asicSroEnSync, trgBuffValid, laneStatus, asicRstSync,
                   trgBuffDout, timeout, laneRxMasters, linkUpSync, r) is

      variable v      : RegType;
      variable axilEp : AxiLiteEndpointType;

      -- internal variables
      variable preamble      : slv(FPGA_PREAMBLE_LEN_C-1 downto 0)   := (others => '0');
      variable header        : slv(FPGA_HEADER_LEN_C-1 downto 0)     := (others => '0');
      variable laneAxiStream : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
      variable laneIdx       : natural := 0;
      variable frameSize     : slv(STREAMRX_FRAME_SIZE_WIDTH_C-1 downto 0) := (others => '0');

      variable laneDown      : slv(NUM_OF_SERIALIZERS_C-1 downto 0)  := (others => '0');

      variable laneTrgCntRef : slv(TRGCNT_WIDTH_C-1 downto 0) := (others => '0');
      variable trgMisalign   : sl := '0';

   begin
      -- Latch the current value
      v := r;

      -- Defaults
      v.trgBuffWr  := '0';
      v.trgBuffRd  := '0';
      v.laneMetaRd := '0';
      v.cntRst     := '0';
      v.armTimeout := '0';
      v.usrRst     := '0';
      v.laneStable := (others => '0');

      -- flow control check
      if asicRxSlave.tReady = '1' then
         v.asicRxMaster.tValid := '0';
         v.asicRxMaster.tLast  := '0';
         v.asicRxMaster.tUser  := (others => '0');
         v.asicRxMaster.tData  := (others => '0');
         v.asicRxMaster.tKeep  := (others => '0');
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
      --
      axiSlaveRegisterR(axilEp, x"618", 0, r.laneDecError);
      axiSlaveRegisterR(axilEp, x"61C", 0, r.laneFull);
      axiSlaveRegisterR(axilEp, x"620", 0, laneDown);
      --
      axiSlaveRegister (axilEp, x"700", 0, v.usrRst);

      -- Closeout the transaction
      axiSlaveDefault(axilEp, v.writeSlave, v.readSlave, AXI_RESP_DECERR_C);
      ----------------------------------------------------------------------------------------------
      ----------------------------------------------------------------------------------------------

      -- Register inputs
      v.asicSro := asicSroSync;

      -- trigger counter management
      -------------------------------
      if asicRstSync = '0' then
         v.fpgaTrgCnt := (others => '1');
      end if;

      -- posedge detection
      if v.asicSro = '1' and r.asicSro = '0' then

         if (asicRstSync and asicSroEnSync) = '1' then
            v.fpgaTrgCnt := r.fpgaTrgCnt + 1;
         end if;

      end if;

      -- negedge detection
      if v.asicSro = '0' and r.asicSro = '1' then

         if (asicRstSync and asicSroEnSync and uOr(r.laneEnable)) = '1' then
            v.trgBuffWr := '1';
         end if;

      end if;
      -------------------------------
      -- global lane status loop;
      -- lane enable indicates a lane has been enabled by the user and is stable
      -- lane valid indicates data from that lane can be read-out;
      -- lane ready indicates that some action needs to be taken: either reset or read-out data
      -- note that a link must be up for consecutive cycles before being labeled as stable
      for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop

         -- link stability counters
         if linkUpSync(lane) = '1' and uAnd(r.laneUpCnt(lane)) /= '1' then
            v.laneUpCnt(lane) := r.laneUpCnt(lane) + 1;
         end if;

         if linkUpSync(lane) = '0' then
            v.laneUpCnt(lane) := (others => '0');
         end if;

         v.laneStable(lane) := uAnd(r.laneUpCnt(lane));

         laneDown(lane) := not(r.laneStable(lane));

         -- lane-enable controls the downstream logic
         v.laneEnable(lane) := r.laneEnableSet(lane) and not(laneDown(lane)) and asicRstSync;

         -- not from metadata FIFO
         v.laneFull(lane) := laneStatus(lane).overflow;

         -- from metadata FIFO
         v.lanePauseError(lane) := laneStatus(lane).pauseError and laneStatus(lane).valid;
         v.laneOverOcc(lane)    := laneStatus(lane).overOcc    and laneStatus(lane).valid;
         v.lanePause(lane)      := laneStatus(lane).pause      and laneStatus(lane).valid;
         v.laneDecError(lane)   := laneStatus(lane).decError   and laneStatus(lane).valid;

         if r.laneEnable(lane) = '1' and r.laneTimeout(lane) = '0' then
            v.laneReady(lane) := (r.laneValid(lane) and laneStatus(lane).valid) or
                                 (laneStatus(lane).overflow or r.laneDecError(lane));
         else
            v.laneReady(lane) := '1';
         end if;

      end loop;

      ----------------------------------------------------------------------------------------------
      -- status counters
      for i in NUM_OF_SERIALIZERS_C-1 downto 0 loop
         -- increment counters on rising edge
         if  (v.laneDecError(i) = '1' and r.laneDecError(i) = '0') and (r.laneEnable(i) = '1')
         and uAnd(r.laneDecErrCnt(i)) /= '1' then
            v.laneDecErrCnt(i) := r.laneDecErrCnt(i) + 1;
         end if;

         if  (v.lanePauseError(i) = '1' and r.lanePauseError(i) = '0') and (r.laneEnable(i) = '1')
         and  uAnd(r.lanePauseErrCnt(i)) /= '1' then
            v.lanePauseErrCnt(i) := r.lanePauseErrCnt(i) + 1;
         end if;

         if  (v.laneFull(i) = '1' and r.laneFull(i) = '0') and (r.laneEnable(i) = '1')
         and  uAnd(r.laneFullCnt(i)) /= '1' then
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
                              laneDown,
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
            v.laneSel       := (others => '0');
            v.laneTimeout   := (others => '0');
            v.waitCnt       := (others => '0');

            -- first check if anything is enabled and if the PGP link is up
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
            if v.asicRxMaster.tValid = '0' then
               v.asicRxMaster.tValid := '1';

               v.asicRxMaster.tKeep  := tKeepSet(FPGA_PREAMBLE_LEN_C);
               ssiSetUserSof(PIX2PGP_FPGA_AXI_CONFIG_C, v.asicRxMaster, '1');
               v.asicRxMaster.tData(FPGA_PREAMBLE_LEN_C-1 downto 0) := preamble;
               v.state := EVAL_LANES_S;
            end if;

         ----------------------------------------------------------------------
         -- wait for lanes to present data;
         -- evaluate, change, and register statuses
         when EVAL_LANES_S =>

            -- set timeout counter if not all ready and if the state is not changing
            if uAnd(r.laneReady) = '0' and r.laneReady = v.laneReady then
               v.armTimeout := '1';
            end if;

            -- lane loop; assign laneValid and any timeouts;
            -- observe the behavior for pause:
            -- if any lane is in-pause -> wait a bit before draining *only* the paused lanes
            for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop

               if timeout = '1' and r.laneValid(lane) = '0' and r.laneReady(lane) = '0' then
                  v.laneTimeout(lane) := '1';
               end if;

               -- check for pause
               if uOr(r.lanePause) = '0' then
                  v.laneValid(lane) := (laneRxMasters(lane).tValid) and
                                    not(laneDown(lane)) and
                                    not(r.laneDecError(lane)) and
                                    not(laneStatus(lane).overflow);

                  if uAnd(r.laneReady) = '1' then
                     v.state := TX_HEADER_S;
                  end if;

               else
                  v.waitCnt := r.waitCnt + 1;

                  v.laneValid(lane) := (laneRxMasters(lane).tValid) and
                                    not(laneDown(lane)) and
                                    not(r.laneDecError(lane)) and
                                    not(laneStatus(lane).overflow) and
                                       (r.lanePause(lane)); -- drain only in-pause lanes

                  if allBits(r.waitCnt, '1') then
                     v.waitCnt := (others => '0');
                     v.state   := TX_HEADER_S;
                  end if;

               end if;

            end loop;

         ----------------------------------------------------------------------
         -- transmit event header infromation
         when TX_HEADER_S =>

            -- essentially waits for all lanes to have something; either valid data or some error
            if v.asicRxMaster.tValid = '0' then

               v.asicRxMaster.tValid := '1';

               v.asicRxMaster.tKeep := tKeepSet(FPGA_HEADER_LEN_C);
               v.asicRxMaster.tData(FPGA_HEADER_LEN_C-1 downto 0) := header;

               v.state := TX_FRAME_SIZE_S;

            end if;

         ----------------------------------------------------------------------
         -- transmit all (valid) lane frame size data
         -- also grab the trigger counter values; will evaluate alignment later
         when TX_FRAME_SIZE_S =>
            if v.asicRxMaster.tValid = '0' then

               v.asicRxMaster.tValid := '1';
               v.asicRxMaster.tKeep  := tKeepSet(STREAMRX_FRAME_SIZE_WIDTH_C);
               v.asicRxMaster.tData(STREAMRX_FRAME_SIZE_WIDTH_C-1 downto 0) := frameSize;
               v.laneTrgCnt(laneIdx) := laneStatus(laneIdx).trgCnt;

               if r.laneValid(laneIdx) = '0' then
                  v.asicRxMaster.tData(LANERX_FRAME_SIZE_WIDTH_C-1 downto 0) := (others => '0');
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
            if v.asicRxMaster.tValid = '0' then
               v.asicRxMaster.tKeep := laneAxiStream.tKeep;
               v.asicRxMaster.tData := laneAxiStream.tData;

               v.asicRxMaster.tValid          := laneRxMasters(laneIdx).tValid;
               v.laneRxSlaves(laneIdx).tReady := asicRxSlave.tReady;

               if laneRxMasters(laneIdx).tLast = '1' and
                  asicRxSlave.tReady           = '1' then

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
         -- transmit trailer, but only if this was not a pause event
         when TX_TRAILER_S =>

            if uOr(r.lanePause) = '0' and allBits(r.waitCnt, '0') then

               if v.asicRxMaster.tValid = '0' then
                  v.asicRxMaster.tKeep  := tKeepSet(FPGA_TRAILER_LEN_C);
                  v.asicRxMaster.tData(FPGA_TRAILER_LEN_C-1 downto 0) :=
                     resize(PIX2PGP_ID_C, FPGA_TRAILER_LEN_C);
                  v.asicRxMaster.tValid := '1';
                  v.asicRxMaster.tLast  := '1';
                  v.trgBuffRd           := '1';
                  v.laneMetaRd          := '1';
                  v.state               := DONE_S;
               end if;

            else

               -- wait before re-evaluating individual lanes for this sub-event
               v.waitCnt := r.waitCnt + '1';

               if allBits(r.waitCnt, '0') then
                  v.laneMetaRd := '1';
               elsif r.waitCnt = toSlv(4, r.waitCnt'length) then
                  v.laneSel     := (others => '0');
                  v.laneTimeout := (others => '0');
                  v.waitCnt     := (others => '0');
                  v.state       := EVAL_LANES_S;
               end if;

            end if;

         ----------------------------------------------------------------------
         -- pop the metadata and internal trigger buffer info FIFOs;
         -- check the trigger counters and make sure they have the same value;
         -- issue resets if necessary
         when DONE_S =>
            trgMisalign := '0';
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
                uOr(r.laneFull)   or trgMisalign) = '1' and r.laneRst = '0' then
               v.laneRst       := '1';
               v.lanePostError := '1';
            end if;

            if r.waitCnt = toSlv(3, r.waitCnt'length) then
               v.state   := IDLE_S;
            elsif r.waitCnt = toSlv(2, r.waitCnt'length) then
               v.laneRst := '0';
            end if;

      end case;
      -------------------------------------------------------------------------


      ----------------------------------------------------------------------------------------------
      -- Outputs
      ----------------------------------------------------------------------------------------------
      for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop

         -- fan-out
         dropBadColTrg(lane) <= r.dropBadColTrg;
         lanePostError(lane) <= r.lanePostError;

          -- only read the valid lanes
         laneMetaRd(lane) <= r.laneMetaRd and (r.laneValid(lane));

         -- enable mapping
         if RST_POLARITY_G = '1' then
            laneRst(lane) <= glblRst or r.laneRst or not(r.laneEnable(lane));
         else
            laneRst(lane) <= glblRst and not(r.laneRst) and(r.laneEnable(lane));
         end if;

      end loop;

      -- AXI-Stream Outputs
      laneRxSlaves <= v.laneRxSlaves;
      asicRxMaster <= r.asicRxMaster;

      -- AXI-Lite Outputs
      writeSlave <= r.writeSlave;
      readSlave  <= r.readSlave;

      -- Reset
      if (RST_ASYNC_G = false and glblRst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (pgpRxClk, glblRst) is
   begin
      if (RST_ASYNC_G and glblRst = RST_POLARITY_G) then
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
         rst      => glblRst,
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

   -- Internal Reset
   U_UsrRst : entity surf.SynchronizerOneShot
      generic map (
         TPD_G         => TPD_G,
         BYPASS_SYNC_G => true,
         PULSE_WIDTH_G => 10)
      port map (
         clk     => pgpRxClk,
         dataIn  => r.usrRst,
         dataOut => usrRst);

   glblRst <= (pgpRxRst or usrRst) when RST_POLARITY_G = '1' else
              (pgpRxRst and not(usrRst));

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

end rtl;
