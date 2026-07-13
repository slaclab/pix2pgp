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
use pix2pgp.Pix2PgpAsicPkg.all;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpLaneRx is
   generic(
      TPD_G                  : time     := 1 ns;
      RST_ASYNC_G            : boolean  := false;
      RST_POLARITY_G         : sl       := '1'; -- '1' for active high rst, '0' for active low
      META_FIFO_ADDR_WIDTH_G : positive := 6;
      LANE_FIFO_ADDR_WIDTH_G : positive := 8);
   port(
      -- General Interface
      laneClk        : in  sl;
      laneRst        : in  sl;
      config         : in  Pix2PgpStreamRxConfigType;
      monState       : out slv(STATE_MON_WIDTH_C-1 downto 0);
      monDin         : out slv(PIX2PGP_DATABUS_DWIDTH_C-1 downto 0);
      -- RX FIFO Interface
      pgp4RxMaster   : in  AxiStreamMasterType;
      pgp4RxSlave    : out AxiStreamSlaveType;
      -- Supervisor Interface
      frameMetaRd    : in  sl;
      frameMetaDout  : out slv(LANERX_META_DWIDTH_C-1 downto 0);
      frameMetaValid : out sl;
      laneRxFull     : out sl;
      -- AXI-Stream to StreamRx
      obAxisMaster   : out AxiStreamMasterType;
      obAxisSlave    : in  AxiStreamSlaveType
   );
end Pix2PgpLaneRx;

architecture rtl of Pix2PgpLaneRx is

   -- first buffer level does not have to be as deep
   constant LANERX_FIFO_ADDR_WIDTH_C : positive := LANE_FIFO_ADDR_WIDTH_G - 2;

   type StateType is (
      WAIT_HEADER_S,
      EVAL_HEADER_S,
      PARSE_COL_METADATA_S,
      PARSE_DATA_S,
      CLOSE_FRAME_S,
      WR_ERROR_S,
      ERROR_S);

   type RegType is record
      decError      : sl;
      fifoRst       : sl;
      frameMetaWr   : sl;
      din           : slv(PIX2PGP_DATABUS_DWIDTH_C-1 downto 0);
      frameMetaDin  : slv(LANERX_META_DWIDTH_C-1 downto 0);
      inOverOcc     : sl;
      inPause       : sl;
      inPauseError  : sl;
      rxError       : sl;
      inFull        : sl;
      laneFull      : sl;
      dummy         : sl;
      validHeader   : sl;
      headerCnt     : slv(bitSize(HEADER_WIDTH_MULT_C)-1 downto 0);
      headerData    : slv(HEADER_DWIDTH_C-1 downto 0);
      waitCnt       : slv(2 downto 0);
      trgCntHeader  : slv(TRGCNT_WIDTH_C-1 downto 0);
      activeColCnt  : slv(BITMAX_COL_MANAGERS_C-1 downto 0);
      eventHitmask  : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      frameSizeCnt  : slv(LANERX_FRAME_SIZE_WIDTH_C-1 downto 0);
      dataLenCnt    : slv(7 downto 0);
      axiFifoMaster : AxiStreamMasterType;
      rxFifoSlave   : AxiStreamSlaveType;
      monState      : slv(STATE_MON_WIDTH_C-1 downto 0);
      state         : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      decError      => '0',
      din           => (others => '0'),
      fifoRst       => not(RST_POLARITY_G),
      frameMetaWr   => '0',
      frameMetaDin  => (others => '0'),
      inOverOcc     => '0',
      inPause       => '0',
      inPauseError  => '0',
      rxError       => '0',
      inFull        => '0',
      laneFull      => '0',
      dummy         => '0',
      validHeader   => '0',
      headerCnt     => (others => '0'),
      headerData    => (others => '0'),
      waitCnt       => (others => '0'),
      trgCntHeader  => (others => '0'),
      activeColCnt  => (others => '0'),
      eventHitmask  => (others => '0'),
      frameSizeCnt  => (others => '0'),
      dataLenCnt    => (others => '0'),
      axiFifoMaster => AXI_STREAM_MASTER_INIT_C,
      rxFifoSlave   => AXI_STREAM_SLAVE_INIT_C,
      monState      => (others => '0'),
      state         => WAIT_HEADER_S);

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

   -------------------------------------------------------------------------------------------------
   -------------------------------------------------------------------------------------------------
   comb : process (r, laneRst, rxFifoMaster, axiFifoSlave, config, laneFull) is

      -- omnipresent
      variable v : RegType;

      -- various data fields encoded in variables; are used in data checks and FSM flow control

      -- header
      variable overOcc    : sl := '0';
      variable pause      : sl := '0';
      variable colErr     : sl := '0';
      variable pauseErr   : sl := '0';
      variable timeout    : sl := '0';
      variable sof        : sl := '0';
      variable eof        : sl := '0';
      variable colHitmask : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
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
      tValid        := '0';
      tLast         := '0';
      tReady        := '0';
      overOcc       := '0';
      pause         := '0';
      colErr        := '0';
      pauseErr      := '0';
      timeout       := '0';
      v.dummy       := '0';
      colHitmask    := (others => '0');
      trgCnt        := (others => '0');
      metaTrgCnt    := (others => '0');
      metaDataLen   := (others => '0');

      v.din := rxFifoMaster.tData(PIX2PGP_DATABUS_DWIDTH_C-1 downto 0);
      v.axiFifoMaster.tData(PIX2PGP_DATABUS_DWIDTH_C-1 downto 0) := v.din;

      -- full monitor
      v.laneFull := laneFull;

      -- dummy and metadata
      if rxFifoMaster.tValid = '1' then
         v.dummy     := toSl(isDummy(v.din));
         metaTrgCnt  := v.din(META_TRGCNT_POS_C);
         metaDataLen := v.din(META_DATALEN_POS_C);
      end if;

      -- flow control
      sof       := ite(EVAL_SOF_C,  ssiGetUserSof(ASIC_DATA_AXI_CONFIG_C,  rxFifoMaster), '1');
      v.rxError := ite(EVAL_EOFE_C, ssiGetUserEofe(ASIC_DATA_AXI_CONFIG_C, rxFifoMaster), '0');

      -- flow control check
      if axiFifoSlave.tReady = '1' then
         v.axiFifoMaster.tValid := '0';
         v.axiFifoMaster.tLast  := '0';
         v.axiFifoMaster.tUser  := (others => '0');
         v.axiFifoMaster.tKeep  := tKeepSet(PIX2PGP_DATABUS_DWIDTH_C);
      end if;

      -- PGP error check
      if r.decError = '1' then
         v.decError := '1';
      else
         v.decError := (v.rxError and not(r.rxError));
      end if;

      -- full-FIFO rising-edge detector; only works some cycles after reset
      if r.inFull = '1' then
         v.inFull := '1';
      elsif allBits(r.waitCnt, '1') and r.inFull = '0' then
         v.inFull := (v.laneFull and not(r.laneFull));
      else
         v.waitCnt := r.waitCnt + 1;
      end if;

      if r.frameMetaWr = '1' then
         v.inOverOcc    := '0';
         v.inPause      := '0';
         v.inPauseError := '0';
         v.decError     := '0';
         v.eventHitmask := (others => '0');
         v.frameSizeCnt := (others => '0');
      end if;

      ---------------------------------------------------------------------------
      case r.state is
      ---------------------------------------------------------------------------
         -- stay here until a valid header comes in
         -- discard dummies; register important flags
         when WAIT_HEADER_S =>

            -- Accumulate header data
            v.headerData((conv_integer(unsigned(r.headerCnt))+1)*PIX2PGP_DATABUS_DWIDTH_C-1 downto
                          conv_integer(unsigned(r.headerCnt))*PIX2PGP_DATABUS_DWIDTH_C) := v.din;

            -- lane full or decoding error detected
            if r.inFull = '1' or r.decError = '1' then
               v.state := WR_ERROR_S;

            -- nominal
            elsif axiFifoSlave.tReady = '1' and rxFifoMaster.tValid = '1' then
               tReady := '1';  -- read rxFifo

               -- SoF evaluation; needs to be high to parse any data
               if v.dummy = '0' and r.headerCnt = 0 and sof = '1' then
                  ssiSetUserSof(ASIC_DATA_AXI_CONFIG_C, v.axiFifoMaster, sof);
                  v.validHeader := '1';
               end if;

               if v.validHeader = '1' then
                  tValid         := '1';                -- write to axiFifo
                  v.frameSizeCnt := r.frameSizeCnt + 1; -- increment the frameSize counter
                  v.headerCnt    := r.headerCnt + 1;    -- increment header cnt

                  -- done parsing the header; grab the flags and proceed
                  if r.headerCnt = HEADER_WIDTH_MULT_C-1 then
                     v.headerCnt := (others => '0');
                     v.state := EVAL_HEADER_S;
                  end if;

               end if;

            end if;

            ----------------------------------------------------------------------
            -- evaluate header information
            when EVAL_HEADER_S =>
               overOcc    := r.headerData(OVEROCC_FLAG_POS_C);
               pause      := r.headerData(PAUSE_FLAG_POS_C);
               colErr     := r.headerData(COLUMN_ERROR_FLAG_POS_C);
               pauseErr   := r.headerData(PAUSE_ERROR_FLAG_POS_C);
               timeout    := r.headerData(TIMEOUT_FLAG_POS_C);
               colHitmask := r.headerData(COL_HITMASK_POS_C);
               trgCnt     := resize(r.headerData(TRGCNT_POS_C), TRGCNT_WIDTH_C);

               v.inOverOcc    := overOcc;
               v.inPause      := pause and not(pauseErr); -- mask if in pause-error
               v.inPauseError := pauseErr;
               v.trgCntHeader := trgCnt;
               v.eventHitmask := colHitmask;
               v.validHeader  := '0'; -- reset the flag

               if uOr(colHitmask) = '0' then
                  v.state := CLOSE_FRAME_S;
               else
                  v.activeColCnt := onesCount(colHitmask);
                  v.state        := PARSE_COL_METADATA_S;
               end if;

         ----------------------------------------------------------------------
         -- parse column metadata
         when PARSE_COL_METADATA_S =>

            -- lane full or decoding error detected
            if r.inFull = '1' or r.decError = '1' then
               v.state := WR_ERROR_S;

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
               --    1a. ...and make sure it is not pause-error
               -- 2. check if the data length of this column is within the limits
               if (metaTrgCnt /= r.trgCntHeader and r.inPauseError = '0') or
                  (metaDataLen >= powerOfTwo(DATALEN_WIDTH_C)) then
                  v.decError := '1';
                  v.state    := WR_ERROR_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- parse column data
         when PARSE_DATA_S =>

            -- lane full or decoding error detected
            if r.inFull = '1' or r.decError = '1' then
               v.state := WR_ERROR_S;

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

            -- lane full or decoding error detected
            if r.inFull = '1' or r.decError = '1' then
               v.state := WR_ERROR_S;

            elsif axiFifoSlave.tReady = '1' then
               -- close frame (no valid data is sent on this cycle; tKeep is low)
               v.axiFifoMaster.tKeep := (others => '0');
               tLast         := '1';
               tValid        := '1';
               v.frameMetaWr := '1';

               -- go-to header waiting state by default
               v.state := WAIT_HEADER_S;

            end if;

         ------------------------------------------------------------------------
         -- write the decoding error word into the FIFO
         when WR_ERROR_S =>
            v.frameMetaWr := '1';
            v.validHeader := '0';
            v.state       := ERROR_S;

         ------------------------------------------------------------------------
         -- stay here until reset; error flags that got us here will still be up
         when ERROR_S =>
            v.state := ERROR_S;

      end case;
      ---------------------------------------------------------------------------

      -- Outputs
      v.axiFifoMaster.tValid := tValid;
      v.axiFifoMaster.tLast  := tLast;
      v.rxFifoSlave.tReady   := tReady;

      v.frameMetaDin := laneMetaMap(r.inOverOcc,
                                    r.inPause,
                                    r.inPauseError,
                                    r.decError,
                                    r.frameSizeCnt,
                                    r.eventHitmask,
                                    r.trgCntHeader);

      rxFifoSlave   <= v.rxFifoSlave;
      axiFifoMaster <= r.axiFifoMaster;

      laneRxFull  <= r.inFull;

      -- monitoring
      case r.state is
      when WAIT_HEADER_S        => v.monState := toSlv(0, STATE_MON_WIDTH_C);
      when PARSE_COL_METADATA_S => v.monState := toSlv(1, STATE_MON_WIDTH_C);
      when PARSE_DATA_S         => v.monState := toSlv(2, STATE_MON_WIDTH_C);
      when CLOSE_FRAME_S        => v.monState := toSlv(3, STATE_MON_WIDTH_C);
      when WR_ERROR_S           => v.monState := toSlv(4, STATE_MON_WIDTH_C);
      when ERROR_S              => v.monState := toSlv(5, STATE_MON_WIDTH_C);
      when others               => v.monState := toSlv(7, STATE_MON_WIDTH_C);
      end case;

      monState <= r.monState;
      monDin   <= r.din;

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
   -------------------------------------------------------------------------------------------------
   -------------------------------------------------------------------------------------------------

   ----------------------------------------
   -- Metadata Buffer
   ----------------------------------------
   U_frameMetaBuffer : entity surf.Fifo
      generic map (
         TPD_G           => TPD_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         GEN_SYNC_FIFO_G => true,
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
         FIFO_ADDR_WIDTH_G   => LANE_FIFO_ADDR_WIDTH_G,
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

   -- all full and almost-full flags
   laneFull <= laneFifoFull  or laneFifoAlmFull or axiFifoFull or
               frameMetaFull or axiFifoAlmFull;

   pgp4RxSlave <= laneFifoSlave;

end rtl;
