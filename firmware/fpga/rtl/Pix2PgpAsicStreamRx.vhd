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

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpAsicStreamRx is
   generic(
      TPD_G                 : time     := 1 ns;
      RST_ASYNC_G           : boolean  := false;
      RST_POLARITY_G        : sl       := '1';  -- '1' for active high rst, '0' for active low
      ASIC_ID_G             : natural  := 0;
      SINGLE_LANE_ID_G      : natural  := 0;
      TIMEOUT_LIMIT_WIDTH_G : positive := 16);
   port(
      -- General Interface
      pgpClk           : in  sl;
      pgpRst           : in  sl := not(RST_POLARITY_G);
      sysClk           : in  sl;
      sysRst           : in  sl := not(RST_POLARITY_G);
      -- ASIC Domain Interface
      asicClk          : in  sl;
      asicRst          : in  sl; -- active-low always
      asicSro          : in  sl;
      asicSroEna       : in  sl;
      -- PGP4Rx Interface
      pgpValid         : in  slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      pgpData          : in  Pix2PgpFpgaRxDataArray;
      pgpReady         : out slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- AXI-Stream Interface
      asicTxMaster     : out AxiStreamMasterType;
      asicTxSlave      : in  AxiStreamSlaveType;
      -- Single Axi Lane for Debugging
      singleLaneMaster : out AxiStreamMasterType;
      singleLaneSlave  : out AxiStreamSlaveType;
      -- AXI-Lite Interface
      axilClk          : in  sl;
      axilRst          : in  sl;
      axilReadMaster   : in  AxiLiteReadMasterType;
      axilReadSlave    : out AxiLiteReadSlaveType;
      axilWriteMaster  : in  AxiLiteWriteMasterType;
      axilWriteSlave   : out AxiLiteWriteSlaveType);
end Pix2PgpAsicStreamRx;

architecture rtl of Pix2PgpAsicStreamRx is

   constant FPGA_TRGCNT_DEFAULT_C   : slv(TRGCNT_WIDTH_C-1 downto 0)        := (others => '1');
   constant TIMEOUT_LIMIT_DEFAULT_C : slv(TIMEOUT_LIMIT_WIDTH_G-1 downto 0) := (others => '1');
   constant LANE_ENABLE_DEFAULT_C   : slv(NUM_OF_SERIALIZERS_C-1 downto 0)  := (others => '1');

   type timeoutArray is array (NUM_OF_SERIALIZERS_C-1 downto 0) of slv(TIMEOUT_LIMIT_WIDTH_G-1 downto 0);

   signal laneTxMasters   : AxiStreamMasterArray(NUM_OF_SERIALIZERS_C-1 downto 0)
                          := (others => AXI_STREAM_MASTER_INIT_C);
   signal laneTxSlaves    : AxiStreamSlaveArray(NUM_OF_SERIALIZERS_C-1 downto 0)
                          := (others => AXI_STREAM_SLAVE_INIT_C);

   signal laneError       : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal laneErrorAck    : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal asicSroSync     : sl := '0';
   signal asicSroEnaSync  : sl := '0';
   signal asicRstSync     : sl := '0';
   signal laneEnableSync  : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '1');

   signal trgBuffWr       : sl := '0';
   signal trgBuffDin      : slv(TRGCNT_WIDTH_C-1 downto 0) := (others => '0');
   signal trgBuffRd       : sl := '0';
   signal trgBuffDout     : slv(TRGCNT_WIDTH_C-1 downto 0) := (others => '0');
   signal trgBuffDoutDly  : slv(TRGCNT_WIDTH_C-1 downto 0) := (others => '0');
   signal trgBuffValid    : sl := '0';
   signal trgBuffValidDly : sl := '0';
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

   signal pgpLaneRst      : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => not(RST_POLARITY_G));
   signal sysLaneRst      : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => not(RST_POLARITY_G));

   type StateType is (
      IDLE_S,
      TX_PREAMBLE_S,
      WAIT_LANES_S,
      SWITCH_MUX_S,
      WAIT_TLAST_S,
      TX_TRAILER_S);

   type RegType is record
      -- Internal
      asicSro      : sl;
      fpgaTrgCnt   : slv(TRGCNT_WIDTH_C-1 downto 0);
      trgBuffWr    : sl;
      trgBuffRd    : sl;
      trgCntBuff   : slv(TRGCNT_WIDTH_C-1 downto 0);
      trgBuffValid : sl;
      armTimeout   : sl;
      laneSel      : slv(BITMAX_SERIALIZERS_C downto 0);
      laneErrorAck : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      waitLaneSel  : sl;
      state        : StateType;
      -- Registers
      fpgaId       : slv(31 downto 0);
      timeoutLimit : slv(TIMEOUT_LIMIT_WIDTH_G-1 downto 0);
      laneEnable   : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- AXI-Stream
      asicTxMaster : AxiStreamMasterType;
      laneTxSlaves : AxiStreamSlaveArray(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- AXI-Lite
      readSlave    : AxiLiteReadSlaveType;
      writeSlave   : AxiLiteWriteSlaveType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- Internal
      asicSro      => '0',
      fpgaTrgCnt   => FPGA_TRGCNT_DEFAULT_C,
      trgBuffWr    => '0',
      trgBuffRd    => '0',
      trgCntBuff   => (others => '0'),
      trgBuffValid => '0',
      armTimeout   => '0',
      laneSel      => (others => '0'),
      laneErrorAck => (others => '0'),
      waitLaneSel  => '0',
      state        => IDLE_S,
      -- Registers
      fpgaId       => FPGA_ID_DEFAULT_C,
      timeoutLimit => TIMEOUT_LIMIT_DEFAULT_C,
      laneEnable   => LANE_ENABLE_DEFAULT_C,
      -- AXI-Stream
      asicTxMaster => AXI_STREAM_MASTER_INIT_C,
      laneTxSlaves => (others => AXI_STREAM_SLAVE_INIT_C),
      -- AXI-Lite
      readSlave    => AXI_LITE_READ_SLAVE_INIT_C,
      writeSlave   => AXI_LITE_WRITE_SLAVE_INIT_C);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   U_SyncSro : entity surf.Synchronizer
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G)
      port map (
         clk     => sysClk,
         dataIn  => asicSro,
         dataOut => asicSroSync);

   U_SyncSroEna : entity surf.Synchronizer
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G)
      port map (
         clk     => sysClk,
         dataIn  => asicSroEna,
         dataOut => asicSroEnaSync);

   U_SyncRst : entity surf.Synchronizer
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G)
      port map (
         clk     => sysClk,
         dataIn  => asicRst,
         dataOut => asicRstSync);

   U_SyncEnable : entity surf.SynchronizerVector
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         WIDTH_G        => NUM_OF_SERIALIZERS_C)
      port map (
         clk     => pgpClk,
         dataIn  => r.laneEnable,
         dataOut => laneEnableSync);

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
         mAxiClk         => sysClk,
         mAxiClkRst      => sysRst,
         mAxiReadMaster  => readMaster,
         mAxiReadSlave   => readSlave,
         mAxiWriteMaster => writeMaster,
         mAxiWriteSlave  => writeSlave);

   comb : process (readMaster, sysRst, pgpRst, writeMaster, asicSroSync, asicSroEnaSync,
                   asicRstSync, trgBuffDoutDly, trgBuffValidDly, asicTxSlave,
                   laneTimeout, laneError, laneTxMasters, laneEnableSync, r) is

      variable v      : RegType;
      variable axilEp : AxiLiteEndpointType;

      -- internal variables
      variable preamble      : slv(FPGA_PREAMPLE_LEN_C-1 downto 0)  := (others => '0');
      variable header        : slv(FPGA_HEADER_LEN_C-1 downto 0)    := (others => '0');
      variable laneValid     : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
      variable allLanesReady : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
      variable laneIdx       : natural := 0;

   begin
      -- Latch the current value
      v := r;

      -- Defaults
      v.trgBuffWr := '0';
      v.trgBuffRd := '0';

      -- flow control check
      if asicTxSlave.tReady = '1' then
         v.asicTxMaster.tValid := '0';
      end if;

      -- default flags
      v.asicTxMaster.tLast := '0';
      v.asicTxMaster.tUser := (others => '0');
      v.asicTxMaster.tData := (others => '0');
      v.asicTxMaster.tKeep := (others => '0');

      for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop
         v.laneTxSlaves(lane).tReady := '0'; -- disable by default
      end loop;

      ----------------------------------------------------------------------------------------------
      -- AXI-Lite Transactions
      ----------------------------------------------------------------------------------------------

      -- Determine the transaction type
      axiSlaveWaitTxn(axilEp, writeMaster, readMaster, v.writeSlave, v.readSlave);

      axiSlaveRegister (axilEp, x"400", 0, v.fpgaId);
      axiSlaveRegister (axilEp, x"404", 0, v.timeoutLimit);
      axiSlaveRegister (axilEp, x"408", 0, v.laneEnable);

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

      -- global lane status loop
      for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop
         laneValid(lane) := laneTxMasters(lane).tValid;

         if r.laneEnable(lane) = '1' then
            allLanesReady(lane) := laneError(lane) or laneTimeout(lane) or laneValid(lane);
         else
            allLanesReady(lane) := '1';
         end if;
      end loop;

      preamble := fpgaPreambleMap(PIX2PGP_ID_C, ASIC_TYPE_C, toSlv(ASIC_ID_G, 32), r.fpgaId);
      header   := fpgaHeaderMap(laneError, laneTimeout, laneValid);

      laneIdx := conv_integer(unsigned(r.laneSel));
      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- wait for a word to be written into the sro/trigger buffer
         when IDLE_S =>
            v.armTimeout   := '0';
            v.laneSel      := (others => '0');
            v.laneErrorAck := (others => '0');

            -- new trigger in queue; register and pop the value
            if trgBuffValidDly = '1' and toBoolean(uOr(r.laneEnable)) then
               v.trgCntBuff := trgBuffDoutDly;
               v.trgBuffRd  := '1';
               v.armTimeout := '1';
               v.state := TX_PREAMBLE_S;
            end if;

         ----------------------------------------------------------------------
         -- transmit the pix2pgp preamble via axi
         when TX_PREAMBLE_S =>
            if v.asicTxMaster.tValid = '0' then
               v.asicTxMaster.tKeep    := tKeepSet(FPGA_PREAMPLE_LEN_C);
               v.asicTxMaster.tUser(1) := '1'; -- SoF
               v.asicTxMaster.tValid   := '1';
               v.asicTxMaster.tData(FPGA_PREAMPLE_LEN_C-1 downto 0) := preamble;
               v.state := WAIT_LANES_S;
            end if;

         ----------------------------------------------------------------------
         -- wait for lanes to present data
         when WAIT_LANES_S =>
            if allBits(allLanesReady, '1') then
               v.asicTxMaster.tKeep  := tKeepSet(FPGA_HEADER_LEN_C);
               v.asicTxMaster.tValid := '1';
               v.asicTxMaster.tData(FPGA_HEADER_LEN_C-1 downto 0) := header;
               v.armTimeout := '0';
               v.state := SWITCH_MUX_S;
            end if;

         ----------------------------------------------------------------------
         -- check if the current lane has any valid data
         when SWITCH_MUX_S =>
            if laneValid(laneIdx) = '0' then

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
         when WAIT_TLAST_S =>
            v.asicTxMaster.tData(FPGA_DATABUS_DWIDTH_C-1 downto 0)
                  := laneTxMasters(laneIdx).tData(FPGA_DATABUS_DWIDTH_C-1 downto 0);
            v.asicTxMaster.tKeep           := laneTxMasters(laneIdx).tKeep;
            v.asicTxMaster.tValid          := laneTxMasters(laneIdx).tValid;
            v.laneTxSlaves(laneIdx).tReady := asicTxSlave.tReady;

            if laneTxMasters(laneIdx).tLast = '1' and
               v.asicTxMaster.tValid        = '1' and
               asicTxSlave.tReady           = '1' then

               v.state := SWITCH_MUX_S;

               -- that was it; transmit trailer
               if laneIdx = NUM_OF_SERIALIZERS_C-1 then
                  v.state := TX_TRAILER_S;
               else
                  v.laneSel := r.laneSel + 1;
               end if;

            end if;

         ----------------------------------------------------------------------
         -- transmit trailer;
         -- also acknowledge any errors and reset the timeout watchdog
         when TX_TRAILER_S =>
            if v.asicTxMaster.tValid = '0' then
               v.asicTxMaster.tKeep  := tKeepSet(FPGA_TRAILER_LEN_C);
               v.asicTxMaster.tData(FPGA_TRAILER_LEN_C-1 downto 0) := resize(PIX2PGP_ID_C, FPGA_TRAILER_LEN_C);
               v.asicTxMaster.tValid := '1';
               v.asicTxMaster.tLast  := '1';
               v.laneErrorAck        := laneError;
               v.state               := IDLE_S;
            end if;

      end case;
      -----------------------------------------------------------------------


      ----------------------------------------------------------------------------------------------
      -- Outputs
      ----------------------------------------------------------------------------------------------

      for lane in 0 to NUM_OF_SERIALIZERS_C-1 loop
         timeoutLimit(lane) <= r.timeoutLimit;
         armTimeout(lane)   <= r.armTimeout and not(laneValid(lane));

         -- enable mapping
         if RST_POLARITY_G = '1' then
            sysLaneRst(lane) <= sysRst or  not(r.laneEnable(lane));
            pgpLaneRst(lane) <= pgpRst or  not(laneEnableSync(lane));
         else
            sysLaneRst(lane) <= sysRst and    (r.laneEnable(lane));
            pgpLaneRst(lane) <= pgpRst and    (laneEnableSync(lane));
         end if;

      end loop;

      laneErrorAck <= r.laneErrorAck;

      -- AXI-Stream Outputs
      laneTxSlaves <= v.laneTxSlaves;
      asicTxMaster <= r.asicTxMaster;

      -- AXI-Lite Outputs
      writeSlave <= r.writeSlave;
      readSlave  <= r.readSlave;

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
         rst      => sysRst,
         -- Write Ports
         wr_clk   => sysClk,
         wr_en    => trgBuffWr,
         din      => trgBuffDin,
         -- Read Ports
         rd_clk   => sysClk,
         rd_en    => trgBuffRd,
         dout     => trgBuffDout,
         valid    => trgBuffValid);

   U_PipelineTriggerBufferWr : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => 2)
      port map (
         clk     => sysClk,
         din(0)  => r.trgBuffWr,
         dout(0) => trgBuffWr);

   U_PipelineTriggerBufferDin : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => TRGCNT_WIDTH_C,
         DELAY_G        => 2)
      port map (
         clk  => sysClk,
         din  => r.fpgaTrgCnt,
         dout => trgBuffDin);

   U_PipelineTriggerBufferRd : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => 2)
      port map (
         clk     => sysClk,
         din(0)  => r.trgBuffRd,
         dout(0) => trgBuffRd);

   U_PipelineTriggerBufferDout : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => TRGCNT_WIDTH_C,
         DELAY_G        => 2)
      port map (
         clk  => sysClk,
         din  => trgBuffDout,
         dout => trgBuffDoutDly);

   U_PipelineTriggerBufferValid : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => 2)
      port map (
         clk     => sysClk,
         din(0)  => trgBuffValid,
         dout(0) => trgBuffValidDly);

   -----------------
   -- Lane Receivers
   -----------------
   GEN_LANE: for lane in 0 to NUM_OF_SERIALIZERS_C-1 generate

      U_Lane: entity pix2pgp.Pix2PgpLaneRxWrapper
         generic map(
            TPD_G          => TPD_G,
            RST_ASYNC_G    => RST_ASYNC_G,
            RST_POLARITY_G => RST_POLARITY_G)
         port map(
            -- General Interface
            pgpClk         => pgpClk,
            pgpRst         => pgpLaneRst(lane),
            sysClk         => sysClk,
            sysRst         => sysLaneRst(lane),
            -- RX FIFO Interface
            pgpValid       => pgpValid(lane),
            pgpData        => pgpData(lane).data,
            pgpReady       => pgpReady(lane),
            -- ASIC Rx Interface
            laneError      => laneError(lane),
            laneErrorAck   => laneErrorAck(lane),
            laneTxMaster   => laneTxMasters(lane),
            laneTxSlave    => laneTxSlaves(lane));

      -- Watchdog (on a per-lane basis)
      U_Watchdog : entity pix2pgp.Pix2PgpWatchdog
         generic map(
            TPD_G          => TPD_G,
            RST_ASYNC_G    => RST_ASYNC_G,
            RST_POLARITY_G => RST_POLARITY_G,
            CNT_WIDTH_G    => TIMEOUT_LIMIT_WIDTH_G)
         port map(
            -- General Interface
            clk     => sysClk,
            rst     => sysRst,
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
            clk  => sysClk,
            din  => timeoutLimit(lane),
            dout => timeoutLimitDly(lane));

      U_PipelineArmTimeout : entity surf.SlvDelay
         generic map (
            TPD_G          => TPD_G,
            RST_POLARITY_G => RST_POLARITY_G,
            WIDTH_G        => NUM_OF_SERIALIZERS_C,
            DELAY_G        => 2)
         port map (
            clk  => sysClk,
            din  => armTimeout,
            dout => armTimeoutDly);

      U_PipelineTimeout : entity surf.SlvDelay
         generic map (
            TPD_G          => TPD_G,
            RST_POLARITY_G => RST_POLARITY_G,
            WIDTH_G        => NUM_OF_SERIALIZERS_C,
            DELAY_G        => 2)
         port map (
            clk  => sysClk,
            din  => timeout,
            dout => laneTimeout);

   end generate GEN_LANE;

   singleLaneMaster <= laneTxMasters(SINGLE_LANE_ID_G);
   singleLaneSlave  <= laneTxSlaves(SINGLE_LANE_ID_G);

end rtl;
