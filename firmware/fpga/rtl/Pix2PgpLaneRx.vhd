-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp Single-Lane Receiver
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

entity Pix2PgpLaneRx is
   generic(
      TPD_G                  : time     := 1 ns;
      RST_ASYNC_G            : boolean  := false;
      RST_POLARITY_G         : sl       := '1'; -- '1' for active high rst, '0' for active low
      META_FIFO_ADDR_WIDTH_G : positive := 6;
      AXIS_FIFO_ADDR_WIDTH_G : positive := 8);
   port(
      -- General Interface
      laneClk        : in  sl;
      laneRst        : in  sl;
      -- RX FIFO Interface
      pgp4RxMaster   : in  AxiStreamMasterType;
      pgp4RxSlave    : out AxiStreamSlaveType;
      -- StreamRx Interface
      postError      : in  sl;
      dropBadTrg     : in  sl;
      frameMetaRd    : in  sl;
      frameMetaDout  : out slv(LANERX_META_DWIDTH_C-1 downto 0);
      frameMetaValid : out sl;
      laneRxFull     : out sl;
      laneRxOk       : out sl;
      laneRxInError  : out sl;
      -- AXI-Stream to StreamRx
      obAxisMaster   : out AxiStreamMasterType;
      obAxisSlave    : in  AxiStreamSlaveType
   );
end Pix2PgpLaneRx;

architecture rtl of Pix2PgpLaneRx is

   constant LANERX_FIFO_ADDR_WIDTH_C : positive := 5;

   type StateType is (
      WAIT_HEADER_S,
      PARSE_COL_METADATA_S,
      PARSE_DATA_S,
      CLOSE_FRAME_S,
      WAIT_DUMMY_S,
      ERROR_S);

   type RegType is record
      decError       : sl;
      fifoRst        : sl;
      frameMetaWr    : sl;
      din            : slv(ASIC_DATABUS_DWIDTH_C-1 downto 0);
      frameMetaDin   : slv(LANERX_META_DWIDTH_C-1 downto 0);
      inOverOcc      : sl;
      inPause        : sl;
      inPauseError   : sl;
      rxError        : sl;
      laneRxOk       : sl;
      postPauseErr   : sl;
      inFull         : sl;
      inError        : sl;
      laneFull       : sl;
      waitCnt        : slv(2 downto 0);
      pauseErrTrgCnt : slv(TRGCNT_WIDTH_C-1 downto 0);
      trgCntHeader   : slv(TRGCNT_WIDTH_C-1 downto 0);
      activeColCnt   : slv(BITMAX_COL_MANAGERS_C downto 0);
      dummyCnt       : slv(bitSize(EVAL_DUMMY_MAX_C)-1 downto 0);
      frameSizeCnt   : slv(LANERX_FRAME_SIZE_WIDTH_C-1 downto 0);
      dataLenCnt     : slv(7 downto 0);
      axiFifoMaster  : AxiStreamMasterType;
      rxFifoSlave    : AxiStreamSlaveType;
      state          : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      decError       => '0',
      din            => (others => '0'),
      fifoRst        => not(RST_POLARITY_G),
      frameMetaWr    => '0',
      frameMetaDin   => (others => '0'),
      inOverOcc      => '0',
      inPause        => '0',
      inPauseError   => '0',
      rxError        => '0',
      laneRxOk       => '0',
      postPauseErr   => '0',
      inFull         => '0',
      inError        => '0',
      laneFull       => '0',
      waitCnt        => (others => '0'),
      pauseErrTrgCnt => (others => '0'),
      trgCntHeader   => (others => '0'),
      activeColCnt   => (others => '0'),
      dummyCnt       => (others => '0'),
      frameSizeCnt   => (others => '0'),
      dataLenCnt     => (others => '0'),
      axiFifoMaster  => AXI_STREAM_MASTER_INIT_C,
      rxFifoSlave    => AXI_STREAM_SLAVE_INIT_C,
      state          => WAIT_HEADER_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   signal axiFifoRst    : sl := not(RST_POLARITY_G);

   signal axiFifoMaster : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal axiFifoSlave  : AxiStreamSlaveType  := AXI_STREAM_SLAVE_INIT_C;

   signal rxFifoMaster  : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal rxFifoSlave   : AxiStreamSlaveType  := AXI_STREAM_SLAVE_INIT_C;

   signal laneFifoFull  : sl := '0';
   signal frameMetaFull : sl := '0';
   signal axiFifoFull   : sl := '0';

   signal laneFull      : sl := '0';

   signal laneFifoSlave : AxiStreamSlaveType  := AXI_STREAM_SLAVE_INIT_C;

   signal laneFifoAlmFull : sl := '0';
   signal axiFifoAlmFull  : sl := '0';

begin

   -----------------------------
   -- First Buffer Level
   -----------------------------
   U_LaneRxFifo : entity surf.AxiStreamFifoV2
      generic map (
         -- General Configurations
         TPD_G               => TPD_G,
         RST_ASYNC_G         => RST_ASYNC_G,
         -- FIFO configurations
         FIFO_ADDR_WIDTH_G   => LANERX_FIFO_ADDR_WIDTH_C,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => ASIC_DATA_AXI_CONFIG_C,
         MASTER_AXI_CONFIG_G => ASIC_DATA_AXI_CONFIG_C)
      port map (
         -- Slave Port
         sAxisClk    => laneClk,
         sAxisRst    => axiFifoRst,
         sAxisMaster => pgp4RxMaster,
         sAxisSlave  => laneFifoSlave,
         -- Status Port
         fifoFull    => laneFifoFull,
         -- Master Port
         mAxisClk    => laneClk,
         mAxisRst    => axiFifoRst,
         mAxisMaster => rxFifoMaster,
         mAxisSlave  => rxFifoSlave);

   comb : process (r, laneRst, rxFifoMaster, axiFifoSlave, dropBadTrg, laneFull, postError) is

      -- omnipresent
      variable v : RegType;

      -- various data fields encoded in variables; are used in data checks and FSM flow control

      -- header
      variable overOcc    : sl := '0';
      variable pause      : sl := '0';
      variable colErr     : sl := '0';
      variable pauseErr   : sl := '0';
      variable timeout    : sl := '0';
      variable dummy      : sl := '0';
      variable sof        : sl := '0';
      variable eof        : sl := '0';
      variable colBitmask : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
      variable trgCnt     : slv(TRGCNT_WIDTH_C-1 downto 0)        := (others => '0');

      -- column metadata
      variable metaTrgCnt  : slv(7 downto 0) := (others => '0');
      variable metaDataLen : slv(7 downto 0) := (others => '0');

      -- axi flow
      variable tValid : sl := '0';
      variable tLast  : sl := '0';
      variable tReady : sl := '0';

   begin

      -- Latch the current value
      v := r;

      -- Defaults
      v.frameMetaWr := '0';
      v.laneRxOk    := '1';
      v.inError     := '0';
      tValid        := '0';
      tLast         := '0';
      tReady        := '0';

      v.din := rxFifoMaster.tData(ASIC_DATABUS_DWIDTH_C-1 downto 0);
      v.axiFifoMaster.tData(ASIC_DATABUS_DWIDTH_C-1 downto 0) := v.din;

      -- full monitor
      v.laneFull := laneFull;

      -- header variables
      overOcc     := v.din(OVEROCC_FLAG_POS_C);
      pause       := v.din(PAUSE_FLAG_POS_C);
      colErr      := v.din(COLUMN_ERROR_FLAG_POS_C);
      pauseErr    := v.din(PAUSE_ERROR_FLAG_POS_C);
      timeout     := v.din(TIMEOUT_FLAG_POS_C);
      dummy       := toSl(isDummy(v.din));
      colBitmask  := v.din(COL_BITMASK_POS_C);
      trgCnt      := resize(v.din(TRGCNT_POS_C), TRGCNT_WIDTH_C);
      -- column metadata variables
      metaTrgCnt  := v.din(META_TRGCNT_POS_C);
      metaDataLen := v.din(META_DATALEN_POS_C);

      -- flow control
      sof       := ite(EVAL_SOF_C,  ssiGetUserSof(ASIC_DATA_AXI_CONFIG_C,  rxFifoMaster), '1');
      v.rxError := ite(EVAL_EOFE_C, ssiGetUserEofe(ASIC_DATA_AXI_CONFIG_C, rxFifoMaster), '0');

      -- flow control check
      if axiFifoSlave.tReady = '1' then
         v.axiFifoMaster.tValid := '0';
         v.axiFifoMaster.tLast  := '0';
         v.axiFifoMaster.tUser  := (others => '0');
         v.axiFifoMaster.tKeep  := tKeepSet(ASIC_DATABUS_DWIDTH_C);
      end if;

      -- PGP error check
      v.decError := (v.rxError and not(r.rxError));

      -- full-FIFO rising-edge detector; only works some cycles after reset
      if allBits(r.waitCnt, '1') then
         v.inFull := (v.laneFull and not(r.laneFull));
      else
         v.waitCnt := r.waitCnt + 1;
      end if;

      if r.frameMetaWr = '1' then
         v.decError      := '0';
         v.inOverOcc     := '0';
         v.inPause       := '0';
         v.inPauseError  := '0';
         v.frameSizeCnt  := (others => '0');
      end if;

      ---------------------------------------------------------------------------
      case r.state is
      ---------------------------------------------------------------------------
         -- stay here until a valid header comes in
         -- discard dummies; register important flags
         when WAIT_HEADER_S =>

            -- post-error state takes precedence; go look for dummy headers
            if postError = '1' then
               v.state := WAIT_DUMMY_S;

            -- lane full
            elsif r.inFull = '1' then
               v.state := ERROR_S;

            -- decoding error detected
            elsif r.decError = '1' then
               v.state := CLOSE_FRAME_S;

            -- nominal
            elsif axiFifoSlave.tReady = '1' and rxFifoMaster.tValid = '1' then
               tReady := '1';  -- read rxFifo

               -- if just recovering from pause-error, check if this is a subsequent event;
               -- if it is, resume normal operation, if not, wait for next packet
               if dummy = '0' and sof = '1' and r.postPauseErr = '1' then
                  if trgCnt > r.pauseErrTrgCnt then
                     v.postPauseErr   := '0'; -- drop the flag to go to the next if-clause
                     v.pauseErrTrgCnt := (others => '0');
                  else
                     v.state := WAIT_DUMMY_S;
                  end if;
               end if;

               if dummy = '0' and sof = '1' and v.postPauseErr = '0' then
                  ssiSetUserSof(ASIC_DATA_AXI_CONFIG_C, v.axiFifoMaster, sof);
                  tValid         := '1';                -- write to axiFifo
                  v.frameSizeCnt := r.frameSizeCnt + 1; -- increment the frameSize counter
                  v.inOverOcc    := overOcc;
                  v.inPause      := pause and not(pauseErr); -- mask if in pause-error
                  v.inPauseError := pauseErr;
                  v.trgCntHeader := trgCnt;

                  if uOr(colBitmask) = '0' then
                     v.state := CLOSE_FRAME_S;
                  else
                     v.activeColCnt := onesCount(colBitmask);
                     v.state        := PARSE_COL_METADATA_S;
                  end if;
               end if;

            end if;

         ----------------------------------------------------------------------
         -- parse column metadata
         when PARSE_COL_METADATA_S =>

            -- lane full
            if r.inFull = '1' then
               v.state := ERROR_S;

            -- decoding error detected
            elsif r.decError = '1' then
               v.state := CLOSE_FRAME_S;

            elsif axiFifoSlave.tReady = '1' and rxFifoMaster.tValid = '1' then
               tValid         := '1'; -- write to axiFifo
               tReady         := '1'; -- read rxFifo
               v.frameSizeCnt := r.frameSizeCnt + 1; -- increment the frameSize counter
               v.dataLenCnt   := metaDataLen;

               if metaDataLen > 0 then
                  v.state := PARSE_DATA_S;
               else
                  -- data for this column done; what about more columns though?
                  if r.activeColCnt > 1 then
                     v.activeColCnt := r.activeColCnt - 1;
                     v.state := PARSE_COL_METADATA_S;
                  else
                     -- close data frame
                     v.state := CLOSE_FRAME_S;
                  end if;
               end if;

               -- data checks; inhibit data parsing if in error
               -- 1. check if this column has the same trigger number as the header
               -- 2. check if the data length of this column is within the limits
               if (metaTrgCnt /= r.trgCntHeader and dropBadTrg = '1') or
                  (metaDataLen >= powerOfTwo(DATALEN_WIDTH_C)) then
                  v.decError := '1';
                  v.state    := CLOSE_FRAME_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- parse column data
         when PARSE_DATA_S =>

            -- lane full
            if r.inFull = '1' then
               v.state := ERROR_S;

            -- decoding error detected
            elsif r.decError = '1' then
               v.state := CLOSE_FRAME_S;

            elsif axiFifoSlave.tReady = '1' and rxFifoMaster.tValid = '1' then
               tValid         := '1'; -- write to axiFifo
               tReady         := '1'; -- read rxFifo
               v.frameSizeCnt := r.frameSizeCnt + 1; -- increment the frameSize counter

               -- still more data for this column remaining
               if r.dataLenCnt > 2 then
                  v.dataLenCnt := r.dataLenCnt - 2;
               else

                  -- data for this column done; what about more columns though?
                  if r.activeColCnt > 1 then
                     v.activeColCnt := r.activeColCnt - 1;
                     v.state := PARSE_COL_METADATA_S;
                  else
                     -- close data frame
                     v.state := CLOSE_FRAME_S;
                  end if;

               end if;
            end if;

         ------------------------------------------------------------------------
         -- determine whether to issue tLast or not;
         -- also determine whether to write into the metadata FIFO or not
         when CLOSE_FRAME_S =>

            if r.inPauseError = '1' then
               v.postPauseErr   := '1';
               v.pauseErrTrgCnt := r.trgCntHeader;
            end if;

            if axiFifoSlave.tReady = '1' then
               -- close frame (no valid data is sent on this cycle; tKeep is low)
               v.axiFifoMaster.tKeep := (others => '0');
               tLast         := '1';
               tValid        := '1';
               v.frameMetaWr := '1';

               -- go-to dummy wait state by default
               v.state := WAIT_HEADER_S;

               -- override; go-to error state and stay there
               if r.decError = '1' then
                  v.state := ERROR_S;
               end if;

            end if;

         ----------------------------------------------------------------------
         -- check for dummies; after a configurable amount, go-to header eval
         -- don't write dummies to axiFifo;
         -- reset status FIFO fields if closed the frame
         when WAIT_DUMMY_S =>
            v.laneRxOk := '0';

            -- lane full
            if r.inFull = '1' then
               v.state := ERROR_S;

            elsif axiFifoSlave.tReady = '1' and rxFifoMaster.tValid = '1' and postError = '0' then
               tReady := '1';  -- read rxFifo

               if dummy = '1' then
                  v.dummyCnt := r.dummyCnt + 1;
                  if r.dummyCnt = EVAL_DUMMY_MAX_C then
                     v.dummyCnt := (others => '0');
                     v.state    := WAIT_HEADER_S;
                  end if;
               else
                  v.dummyCnt := (others => '0');
               end if;
            end if;

         ------------------------------------------------------------------------
         -- stay here until reset;
         when ERROR_S =>
            v.laneRxOk := '0';
            v.inError  := '1';

      end case;
      ---------------------------------------------------------------------------

      -- Outputs
      v.axiFifoMaster.tValid := tValid;
      v.axiFifoMaster.tLast  := tLast;
      v.rxFifoSlave.tReady   := tReady;

      v.frameMetaDin := laneMetaMap(r.decError,
                                    r.inOverOcc,
                                    r.inPause,
                                    r.inPauseError,
                                    r.frameSizeCnt,
                                    r.trgCntHeader);

      rxFifoSlave   <= v.rxFifoSlave;
      axiFifoMaster <= r.axiFifoMaster;
      laneRxOk      <= r.laneRxOk;
      laneRxInError <= r.inError;

      -- Reset
      if (RST_ASYNC_G = false and laneRst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;


   seq : process (laneClk, laneRst) is
   begin
      if (RST_ASYNC_G and laneRst = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(laneClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

   ----------------------------------------
   -- Metadata Buffer
   ----------------------------------------
   U_frameMetaBuffer : entity surf.Fifo
      generic map (
         TPD_G           => TPD_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         MEMORY_TYPE_G   => "block",
         FWFT_EN_G       => true,
         DATA_WIDTH_G    => LANERX_META_DWIDTH_C,
         ADDR_WIDTH_G    => META_FIFO_ADDR_WIDTH_G)
      port map (
         rst      => laneRst,
         -- Write Ports
         wr_clk   => laneClk,
         wr_en    => r.frameMetaWr,
         din      => r.frameMetaDin,
         full     => frameMetaFull,
         -- Read Ports
         rd_clk   => laneClk,
         rd_en    => frameMetaRd,
         dout     => frameMetaDout,
         valid    => frameMetaValid);

   ------------------
   -- Axi-Stream FIFO
   ------------------
   U_Fifo : entity surf.AxiStreamFifoV2
      generic map (
         -- General Configurations
         TPD_G               => TPD_G,
         RST_ASYNC_G         => RST_ASYNC_G,
         -- FIFO configurations
         FIFO_ADDR_WIDTH_G   => AXIS_FIFO_ADDR_WIDTH_G,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => ASIC_DATA_AXI_CONFIG_C,
         MASTER_AXI_CONFIG_G => PIX2PGP_FPGA_AXI_CONFIG_C)
      port map (
         -- Slave Port
         sAxisClk    => laneClk,
         sAxisRst    => axiFifoRst,
         sAxisMaster => axiFifoMaster,
         sAxisSlave  => axiFifoSlave,
         -- Status Port
         fifoFull    => axiFifoFull,
         -- Master Port
         mAxisClk    => laneClk,
         mAxisRst    => axiFifoRst,
         mAxisMaster => obAxisMaster,
         mAxisSlave  => obAxisSlave);

   -- AXI-Stream FIFO does not have RST_POLARITY_G
   axiFifoRst <= ite(toBoolean(RST_POLARITY_G), laneRst, not(laneRst));

   laneFifoAlmFull <= not(laneFifoSlave.tReady);
   axiFifoAlmFull  <= not(axiFifoSlave.tReady);

   -- all full and almost-full flags; also monitor frame size counter overflow
   laneFull <= laneFifoFull  or laneFifoAlmFull or axiFifoFull or
               frameMetaFull or axiFifoAlmFull  or uAnd(r.frameSizeCnt);

   pgp4RxSlave <= laneFifoSlave;

   laneRxFull <= r.inFull;

end rtl;
