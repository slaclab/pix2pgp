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
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1'); -- '1' for active high rst, '0' for active low
   port(
      -- General Interface
      pgpClk         : in  sl;
      pgpRst         : in  sl := not(RST_POLARITY_G);
      sysClk         : in  sl;
      sysRst         : in  sl := not(RST_POLARITY_G);
      discard        : in  sl;
      -- RX FIFO Interface
      pgp4RxMaster   : in  AxiStreamMasterType;
      pgp4RxSlave    : out AxiStreamSlaveType;
      -- Filter Interface
      laneRxRst      : in  sl;
      frameMetaRd    : in  sl;
      frameMetaDout  : out slv(LANERX_META_BUFF_WIDTH_C-1 downto 0);
      frameMetaValid : out sl;
      -- AXI-Stream to Filter
      obAxisMaster   : out AxiStreamMasterType;
      obAxisSlave    : in  AxiStreamSlaveType
   );
end Pix2PgpLaneRx;

architecture rtl of Pix2PgpLaneRx is

   type StateType is (
      WAIT_HEADER_S,
      PARSE_COL_METADATA_S,
      PARSE_DATA_S,
      WAIT_DUMMY_S,
      ERROR_S);

   type RegType is record
      decError      : sl;
      fifoRst       : sl;
      frameMetaWr   : sl;
      din           : slv(ASIC_DATABUS_DWIDTH_C-1 downto 0);
      frameMetaDin  : slv(LANERX_META_BUFF_WIDTH_C-1 downto 0);
      inPause       : sl;
      rxError       : sl;
      trgCntHeader  : slv(TRGCNT_WIDTH_C-1 downto 0);
      activeColCnt  : slv(BITMAX_COL_MANAGERS_C downto 0);
      dummyCnt      : slv(bitSize(DUMMY_CNT_MAX_C)-1 downto 0);
      frameSizeCnt  : slv(LANERX_FRAME_SIZE_WIDTH_C-1 downto 0);
      dataLenCnt    : slv(7 downto 0);
      axiFifoMaster : AxiStreamMasterType;
      rxFifoSlave   : AxiStreamSlaveType;
      state         : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      decError      => '0',
      din           => (others => '0'),
      fifoRst       => not(RST_POLARITY_G),
      frameMetaWr   => '0',
      frameMetaDin  => (others => '0'),
      inPause       => '0',
      rxError       => '0',
      trgCntHeader  => (others => '0'),
      activeColCnt  => (others => '0'),
      dummyCnt      => (others => '0'),
      frameSizeCnt  => (others => '0'),
      dataLenCnt    => (others => '0'),
      axiFifoMaster => AXI_STREAM_MASTER_INIT_C,
      rxFifoSlave   => AXI_STREAM_SLAVE_INIT_C,
      state         => WAIT_HEADER_S
   );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   signal rxFifoRst     : sl := '0';

   signal sysFifoRst    : sl := not(RST_POLARITY_G);
   signal pgpFifoRst    : sl := not(RST_POLARITY_G);

   signal laneRst       : sl := not(RST_POLARITY_G);
   signal laneRxRstSync : sl := not(RST_POLARITY_G);

   signal axiFifoMaster : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal axiFifoSlave  : AxiStreamSlaveType  := AXI_STREAM_SLAVE_INIT_C;

   signal rxFifoMaster  : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal rxFifoSlave   : AxiStreamSlaveType  := AXI_STREAM_SLAVE_INIT_C;

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
         sAxisClk    => pgpClk,
         sAxisRst    => rxFifoRst,
         sAxisMaster => pgp4RxMaster,
         sAxisSlave  => pgp4RxSlave,
         -- Master Port
         mAxisClk    => pgpClk,
         mAxisRst    => rxFifoRst,
         mAxisMaster => rxFifoMaster,
         mAxisSlave  => rxFifoSlave);

   U_SynclaneRxRst : entity surf.Synchronizer
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G)
      port map (
         clk     => pgpClk,
         dataIn  => laneRxRst,
         dataOut => laneRxRstSync);

   comb : process (r, laneRst, rxFifoMaster, axiFifoSlave, discard) is

      -- omnipresent
      variable v : RegType;

      -- various data fields encoded in variables; are used in data checks and FSM flow control

      -- header
      variable overOcc    : sl := '0';
      variable pause      : sl := '0';
      variable colError   : sl := '0';
      variable pauseError : sl := '0';
      variable timeout    : sl := '0';
      variable dummy      : sl := '0';
      variable sof        : sl := '0';
      variable eof        : sl := '0';
      variable colBitmask : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
      variable trgCnt     : slv(TRGCNT_WIDTH_C-1 downto 0)        := (others => '0');

      -- column metadata
      variable metaTrgCnt  : slv(7 downto 0) := (others => '0');
      variable metaDataLen : slv(7 downto 0) := (others => '0');

   begin

      -- Latch the current value
      v := r;

      -- Defaults
      v.frameMetaWr        := '0';
      v.rxFifoSlave.tReady := '0';
      v.fifoRst            := not(RST_POLARITY_G);

      v.din := rxFifoMaster.tData(ASIC_DATABUS_DWIDTH_C-1 downto 0);
      v.axiFifoMaster.tData(ASIC_DATABUS_DWIDTH_C-1 downto 0) := v.din;

      -- header variables
      overOcc     := v.din(OVEROCC_FLAG_POS_C);
      pause       := v.din(PAUSE_FLAG_POS_C);
      colError    := v.din(COLUMN_ERROR_FLAG_POS_C);
      pauseError  := v.din(PAUSE_ERROR_FLAG_POS_C);
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
      end if;

      -- PGP error check
      v.decError := (v.rxError and not(r.rxError));

      -- Reset counter
      if r.frameMetaWr = '1' then
         v.frameSizeCnt := (others => '0');
      end if;

      ---------------------------------------------------------------------------
      case r.state is
      ---------------------------------------------------------------------------
         -- stay here until a valid header comes in
         -- discard dummies
         when WAIT_HEADER_S =>
            if axiFifoSlave.tReady = '1' and rxFifoMaster.tValid = '1' then
               v.rxFifoSlave.tReady := '1';  -- read rxFifo

               if dummy = '0' and sof = '1' then
                  ssiSetUserSof(ASIC_DATA_AXI_CONFIG_C, v.axiFifoMaster, sof);
                  v.axiFifoMaster.tValid := '1'; -- write to axiFifo
                  v.frameSizeCnt         := r.frameSizeCnt + 1; -- increment the frameSize counter
                  v.inPause              := pause;
                  v.trgCntHeader         := trgCnt;

                  if uOr(colBitmask) = '0' then
                     v.axiFifoMaster.tLast := '1'; -- EoF
                  else
                     v.activeColCnt := onesCount(colBitmask);
                     v.state        := PARSE_COL_METADATA_S;
                  end if;
               end if;
            end if;

            -- error detected!
            if v.decError = '1' then
               v.state := ERROR_S;
            end if;

         ----------------------------------------------------------------------
         -- parse column metadata
         when PARSE_COL_METADATA_S =>
            if axiFifoSlave.tReady = '1' and rxFifoMaster.tValid = '1' then
               v.axiFifoMaster.tValid := '1'; -- write to axiFifo
               v.rxFifoSlave.tReady   := '1'; -- read rxFifo
               v.frameSizeCnt         := r.frameSizeCnt + 1; -- increment the frameSize counter
               v.dataLenCnt           := metaDataLen;

               if metaDataLen > 0 then
                  v.state := PARSE_DATA_S;
               else
                  -- data for this column done; what about more columns though?
                  if r.activeColCnt > 1 then
                     v.activeColCnt := r.activeColCnt - 1;
                     v.state := PARSE_COL_METADATA_S;
                  else
                     -- close data frame if not expecting more data
                     v.axiFifoMaster.tLast := not(r.inPause);
                     v.state := WAIT_DUMMY_S;
                  end if;
               end if;

               -- data checks; inhibit data parsing if in error
               -- 1. check if this column has the same trigger number as the header
               -- 2. check if the data length of this column is within the limits
               if (metaTrgCnt /= r.trgCntHeader and discard = '1') or
                  (metaDataLen >= powerOfTwo(DATALEN_WIDTH_C)) then
                  v.decError := '1';
                  v.state    := ERROR_S;
               end if;
            end if;

            -- error detected!
            if v.decError = '1' then
               v.state := ERROR_S;
            end if;

         ----------------------------------------------------------------------
         -- parse column data
         when PARSE_DATA_S =>
            if axiFifoSlave.tReady = '1' and rxFifoMaster.tValid = '1' then
               v.axiFifoMaster.tValid := '1'; -- write to axiFifo
               v.rxFifoSlave.tReady   := '1'; -- read rxFifo
               v.frameSizeCnt         := r.frameSizeCnt + 1; -- increment the frameSize counter

               -- still more data for this column remaining
               if r.dataLenCnt > 2 then
                  v.dataLenCnt := r.dataLenCnt - 2;
               else

                  -- data for this column done; what about more columns though?
                  if r.activeColCnt > 1 then
                     v.activeColCnt := r.activeColCnt - 1;
                     v.state := PARSE_COL_METADATA_S;
                  else
                     -- close data frame if not expecting more data
                     v.axiFifoMaster.tLast := not(r.inPause);
                     v.state := WAIT_DUMMY_S;
                  end if;

               end if;
            end if;

            -- error detected!
            if v.decError = '1' then
               v.state := ERROR_S;
            end if;

         ----------------------------------------------------------------------
         -- check for dummies; after a configurable amount, go-to header eval
         -- don't write dummies to axiFifo
         when WAIT_DUMMY_S =>
            if axiFifoSlave.tReady = '1' and rxFifoMaster.tValid = '1' then
               v.rxFifoSlave.tReady := '1';  -- read rxFifo

               if dummy = '1' then
                  v.dummyCnt := r.dummyCnt + 1;
                  if r.dummyCnt = DUMMY_CNT_MAX_C then
                     v.dummyCnt := (others => '0');
                     v.state    := WAIT_HEADER_S;
                  end if;
               end if;
            end if;

         ------------------------------------------------------------------------
         -- stay here until reset
         when ERROR_S =>
            v.fifoRst  := RST_POLARITY_G;
            v.decError := '1';

      end case;
      ---------------------------------------------------------------------------

      -- Outputs
      v.frameMetaWr := (r.axiFifoMaster.tLast and axiFifoSlave.tReady) or
                       (v.decError and not(r.decError));

      v.frameMetaDin(LANE_DEC_ERROR_POS_C) := v.decError;
      v.frameMetaDin(LANE_SIZE_POS_C)      := r.frameSizeCnt;
      v.frameMetaDin(LANE_TRGCNT_POS_C)    := r.trgCntHeader;

      rxFifoSlave   <= v.rxFifoSlave;
      axiFifoMaster <= r.axiFifoMaster;

      -- Reset
      if (RST_ASYNC_G = false and laneRst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   -- internal resets
   laneRst  <= (pgpRst or laneRxRstSync) when RST_POLARITY_G = '1' else
               (pgpRst and not(laneRxRstSync));

   rxFifoRst <= (pgpRst or r.fifoRst) when RST_POLARITY_G = '1' else
                (pgpRst and not(r.fifoRst));

   seq : process (pgpClk, laneRst) is
   begin
      if (RST_ASYNC_G and laneRst = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(pgpClk) then
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
         GEN_SYNC_FIFO_G => false, -- false = clock-domain-crossing FIFO
         FWFT_EN_G       => true,
         DATA_WIDTH_G    => LANERX_META_BUFF_WIDTH_C, -- dataLen plus the error flag
         ADDR_WIDTH_G    => 4)
      port map (
         rst      => pgpFifoRst,
         -- Write Ports
         wr_clk   => pgpClk,
         wr_en    => r.frameMetaWr,
         din      => r.frameMetaDin,
         -- Read Ports
         rd_clk   => sysClk,
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
         GEN_SYNC_FIFO_G     => false,
         FIFO_ADDR_WIDTH_G   => AXIS_FIFO_WIDTH_C,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => ASIC_DATA_AXI_CONFIG_C,
         MASTER_AXI_CONFIG_G => ASIC_DATA_AXI_CONFIG_C)
      port map (
         -- Slave Port
         sAxisClk    => pgpClk,
         sAxisRst    => pgpFifoRst,
         sAxisMaster => axiFifoMaster,
         sAxisSlave  => axiFifoSlave,
         -- Master Port
         mAxisClk    => sysClk,
         mAxisRst    => sysFifoRst,
         mAxisMaster => obAxisMaster,
         mAxisSlave  => obAxisSlave);

   -- AXI-Stream FIFO does not have RST_POLARITY_G
   sysFifoRst <= ite(toBoolean(RST_POLARITY_G), sysRst,  not(sysRst));
   pgpFifoRst <= ite(toBoolean(RST_POLARITY_G), laneRst, not(laneRst));

end rtl;
