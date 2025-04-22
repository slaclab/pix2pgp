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
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1';  -- '1' for active high rst, '0' for active low
      ASIC_ID_G      : natural := 0);
   port(
      -- General Interface
      pgpClk          : in  sl;
      pgpRst          : in  sl := not(RST_POLARITY_G);
      sysClk          : in  sl;
      sysRst          : in  sl := not(RST_POLARITY_G);
      -- ASIC Domain Interface
      asicClk         : in  sl;
      asicRst         : in  sl; -- active-low always
      asicSro         : in  sl;
      asicSroEna      : in  sl;
      -- PGP4Rx Interface
      pgpValid        : in  slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      pgpData         : in  Pix2PgpFpgaRxDataArray;
      pgpReady        : out slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- AXI-Stream Interface
      asicTxMaster    : out AxiStreamMasterType;
      asicTxSlave     : in  AxiStreamSlaveType;
      -- AXI-Lite Interface
      axilClk         : in  sl;
      axilRst         : in  sl;
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType);
end Pix2PgpAsicStreamRx;

architecture rtl of Pix2PgpAsicStreamRx is

   constant FPGA_TRGCNT_DEFAULT_C : slv(TRGCNT_WIDTH_C-1 downto 0) := (others => '1');

   signal frameDataRd     : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal frameDataDout   : Pix2PgpFpgaRxDataArray := (others => DEFAULT_PIX2PGP_DATABUS_C);
   signal frameDataFull   : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal frameMetaRd     : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal frameMetaDout   : Pix2PgpFpgaRxMetaArray := (others => DEFAULT_PIX2PGP_FPGARX_METABUS_C);
   signal frameMetaValid  : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal laneTxMasters   : AxiStreamMasterArray(NUM_OF_SERIALIZERS_C-1 downto 0)
                          := (others => AXI_STREAM_MASTER_INIT_C);
   signal laneTxSlaves    : AxiStreamSlaveArray(NUM_OF_SERIALIZERS_C-1 downto 0)
                          := (others => AXI_STREAM_SLAVE_INIT_C);

   signal laneError       : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');
   signal laneErrorAck    : slv(NUM_OF_SERIALIZERS_C-1 downto 0) := (others => '0');

   signal asicSroSync     : sl := '0';
   signal asicSroEnaSync  : sl := '0';
   signal asicRstSync     : sl := '0';

   signal trgBuffWr       : sl := '0';
   signal trgBuffDin      : slv(TRGCNT_WIDTH_C-1 downto 0) := (others => '0');
   signal trgBuffRd       : sl := '0';
   signal trgBuffDout     : slv(TRGCNT_WIDTH_C-1 downto 0) := (others => '0');
   signal trgBuffDoutDly  : slv(TRGCNT_WIDTH_C-1 downto 0) := (others => '0');
   signal trgBuffValid    : sl := '0';
   signal trgBuffValidDly : sl := '0';

   signal readMaster      : AxiLiteReadMasterType;
   signal readSlave       : AxiLiteReadSlaveType;
   signal writeMaster     : AxiLiteWriteMasterType;
   signal writeSlave      : AxiLiteWriteSlaveType;

   type StateType is (
      IDLE_S,
      TX_PREAMBLE_S,
      TX_HEADER_S,
      PARSE_DATA_S);

   type RegType is record
      -- Internal
      asicSro      : sl;
      fpgaTrgCnt   : slv(TRGCNT_WIDTH_C-1 downto 0);
      trgBuffWr    : sl;
      trgBuffRd    : sl;
      trgCntBuff   : slv(TRGCNT_WIDTH_C-1 downto 0);
      trgBuffValid : sl;
      asicTxMaster : AxiStreamMasterType;
      state        : StateType;
      -- Registers
      fpgaId       : slv(31 downto 0);
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
      asicTxMaster => AXI_STREAM_MASTER_INIT_C,
      state        => IDLE_S,
      -- Registers
      fpgaId       => FPGA_ID_DEFAULT_C,
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

   comb : process (readMaster, sysRst, writeMaster, asicSroSync, asicSroEnaSync,
                   asicRstSync, trgBuffDoutDly, trgBuffValidDly, asicTxSlave, r) is

      variable v      : RegType;
      variable axilEp : AxiLiteEndpointType;

      -- preamble
      variable preamble : slv(FPGA_PREAMPLE_LEN_C-1 downto 0) := (others => '0');

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
      v.asicTxMaster.tLast  := '0';
      v.asicTxMaster.tUser  := (others => '0');
      v.asicTxMaster.tKeep  := (others => '1');

      ----------------------------------------------------------------------------------------------
      -- AXI-Lite Transactions
      ----------------------------------------------------------------------------------------------

      -- Determine the transaction type
      axiSlaveWaitTxn(axilEp, writeMaster, readMaster, v.writeSlave, v.readSlave);

      axiSlaveRegister (axilEp, x"400", 0, v.fpgaId);

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

      preamble := preambleSet(PIX2PGP_ID_C, ASIC_TYPE_C, toSlv(ASIC_ID_G, 32), r.fpgaId);

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- wait for a word to be written into the sro/trigger buffer
         when IDLE_S =>

            -- new trigger in queue; register and pop the value
            if trgBuffValidDly = '1' then
               v.trgCntBuff := trgBuffDoutDly;
               v.trgBuffRd  := '1';
               v.state      := TX_PREAMBLE_S;
            end if;

         ----------------------------------------------------------------------
         -- transmit the pix2pgp preamble via axi
         when TX_PREAMBLE_S =>
            if v.asicTxMaster.tValid = '0' then
               v.asicTxMaster.tKeep    := tKeepPreambleSet(FPGA_PREAMPLE_LEN_C);
               v.asicTxMaster.tUser(1) := '1'; -- SoF
               v.asicTxMaster.tValid   := '1';
               v.asicTxMaster.tData(FPGA_PREAMPLE_LEN_C-1 downto 0) := preamble;
               v.state := TX_HEADER_S;
            end if;

         ----------------------------------------------------------------------
         -- wait for lanes to present data
         when TX_HEADER_S =>
            v.state := PARSE_DATA_S;

         ----------------------------------------------------------------------
         -- arbitrate through lanes
         when PARSE_DATA_S =>
            v.state := IDLE_S;

      end case;
      -----------------------------------------------------------------------


      ----------------------------------------------------------------------------------------------
      -- Outputs
      ----------------------------------------------------------------------------------------------

      -- AXI-Stream Output
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

      U_Lane: entity pix2pgp.Pix2PgpLaneRx
         generic map(
            TPD_G          => TPD_G,
            RST_ASYNC_G    => RST_ASYNC_G,
            RST_POLARITY_G => RST_POLARITY_G)
         port map(
            -- General Interface
            pgpClk         => pgpClk,
            pgpRst         => pgpRst,
            sysClk         => sysClk,
            sysRst         => sysRst,
            -- RX FIFO Interface
            pgpValid       => pgpValid(lane),
            pgpData        => pgpData(lane).data,
            pgpReady       => pgpReady(lane),
            -- Adapter Interface
            frameDataRd    => frameDataRd(lane),
            frameDataDout  => frameDataDout(lane).data,
            frameDataFull  => frameDataFull(lane),
            frameMetaRd    => frameMetaRd(lane),
            frameMetaDout  => frameMetaDout(lane).metaData,
            frameMetaValid => frameMetaValid(lane));

      U_Adapter: entity pix2pgp.Pix2PgpLaneAdapter
         generic map(
            TPD_G          => TPD_G,
            RST_ASYNC_G    => RST_ASYNC_G,
            RST_POLARITY_G => RST_POLARITY_G)
         port map(
            -- General Interface
            sysClk         => sysClk,
            sysRst         => sysRst,
            -- Lane Interface
            frameDataRd    => frameDataRd(lane),
            frameDataDout  => frameDataDout(lane).data,
            frameDataFull  => frameDataFull(lane),
            frameMetaRd    => frameMetaRd(lane),
            frameMetaDout  => frameMetaDout(lane).metaData,
            frameMetaValid => frameMetaValid(lane),
            -- ASIC Rx Interface
            laneError      => laneError(lane),
            laneErrorAck   => laneErrorAck(lane),
            laneTxMaster   => laneTxMasters(lane),
            laneTxSlave    => laneTxSlaves(lane));

   end generate GEN_LANE;

end rtl;
