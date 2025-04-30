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

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpLaneRx is
   generic(
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1'  -- '1' for active high rst, '0' for active low
   );
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
      WAIT_VALID_S,
      WAIT_HEADER_S,
      PARSE_COL_METADATA_S,
      PARSE_DATA_S,
      ERROR_S);

   type RegType is record
      decError      : sl;
      pgpError      : sl;
      fifoRst       : sl;
      frameMetaWr   : sl;
      toHeader      : sl;
      toMeta        : sl;
      toData        : sl;
      din           : slv(ASIC_DATABUS_DWIDTH_C-1 downto 0);
      frameMetaDin  : slv(LANERX_META_BUFF_WIDTH_C-1 downto 0);
      inPause       : sl;
      trgCntHeader  : slv(TRGCNT_WIDTH_C-1 downto 0);
      activeColCnt  : slv(BITMAX_COL_MANAGERS_C downto 0);
      dataLenCnt    : slv(7 downto 0);
      sAxisMaster   : AxiStreamMasterType;
      rxFifoSlave   : AxiStreamSlaveType;
      state         : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      decError      => '0',
      pgpError      => '0',
      toHeader      => '1',
      toMeta        => '0',
      toData        => '0',
      din           => (others => '0'),
      fifoRst       => not(RST_POLARITY_G),
      frameMetaWr   => '0',
      frameMetaDin  => (others => '0'),
      inPause       => '0',
      trgCntHeader  => (others => '0'),
      activeColCnt  => (others => '0'),
      dataLenCnt    => (others => '0'),
      sAxisMaster   => AXI_STREAM_MASTER_INIT_C,
      rxFifoSlave   => AXI_STREAM_SLAVE_INIT_C,
      state         => WAIT_VALID_S
   );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   signal rxFifoRst     : sl := '0';

   signal sysFifoRst    : sl := not(RST_POLARITY_G);
   signal pgpFifoRst    : sl := not(RST_POLARITY_G);

   signal laneRst       : sl := not(RST_POLARITY_G);
   signal laneRxRstSync : sl := not(RST_POLARITY_G);

   signal sAxisMaster   : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal sAxisSlave    : AxiStreamSlaveType  := AXI_STREAM_SLAVE_INIT_C;

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

   comb : process (r, laneRst, rxFifoMaster, sAxisSlave, discard) is

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
      variable colBitmask : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
      variable trgCnt     : slv(TRGCNT_WIDTH_C-1 downto 0)        := (others => '0');

      -- column metadata
      variable metaTrgCnt  : slv(7 downto 0) := (others => '0');
      variable metaDataLen : slv(7 downto 0) := (others => '0');

   begin

      -- Latch the current value
      v := r;

      -- Register inputs
      v.pgpError       := '0'; -- To-Do: encode this

      -- Defaults
      v.frameMetaWr        := '0';
      v.rxFifoSlave.tReady := '0';
      v.fifoRst            := not(RST_POLARITY_G);

      v.din                := rxFifoMaster.tData(ASIC_DATABUS_DWIDTH_C-1 downto 0);
      v.sAxisMaster.tData(ASIC_DATABUS_DWIDTH_C-1 downto 0) := r.din;


      -- header variables
      overOcc     := r.din(OVEROCC_FLAG_POS_C);
      pause       := r.din(PAUSE_FLAG_POS_C);
      colError    := r.din(COLUMN_ERROR_FLAG_POS_C);
      pauseError  := r.din(PAUSE_ERROR_FLAG_POS_C);
      timeout     := r.din(TIMEOUT_FLAG_POS_C);
      dummy       := toSl(isDummy(r.din));
      colBitmask  := r.din(COL_BITMASK_POS_C);
      trgCnt      := resize(r.din(TRGCNT_POS_C), TRGCNT_WIDTH_C);
      -- column metadata variables
      metaTrgCnt  := r.din(META_TRGCNT_POS_C);
      metaDataLen := r.din(META_DATALEN_POS_C);

      -- flow control check
      if sAxisSlave.tReady = '1' then
         v.sAxisMaster.tValid := '0';
         v.sAxisMaster.tLast  := '0';
         v.sAxisMaster.tUser  := (others => '0');
      end if;

      -- PGP error check
      v.decError := (v.pgpError and not(r.pgpError));

      ---------------------------------------------------------------------------
      case r.state is
      ---------------------------------------------------------------------------
         -- stay here until a valid header comes in
         when WAIT_HEADER_S =>
            if dummy = '1' then
               v.state := WAIT_VALID_S;
            elsif sAxisSlave.tReady = '1' and dummy = '0' then
               v.sAxisMaster.tValid   := '1';
               v.sAxisMaster.tUser(1) := '1'; -- SoF
               v.inPause := pause;

               if uOr(colBitmask) = '0' then
                  v.sAxisMaster.tLast := '1'; -- EoF
               else
                  v.toHeader     := '0';
                  v.toMeta       := '1';
                  v.trgCntHeader := trgCnt;
                  v.activeColCnt := onesCount(colBitmask);
               end if;

               v.state := WAIT_VALID_S;

            end if;

            -- error detected!
            if v.decError = '1' then
               v.state := ERROR_S;
            end if;

         ----------------------------------------------------------------------
         -- parse column metadata
         when PARSE_COL_METADATA_S =>
            if sAxisSlave.tReady = '1' then
               v.sAxisMaster.tValid := '1';
               v.dataLenCnt         := metaDataLen;

               v.toMeta  := '0';
               v.toData  := '1';
               v.state := WAIT_VALID_S;

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
            if sAxisSlave.tReady = '1' then

               v.sAxisMaster.tValid := '1';
               -- still more data for this column remaining
               if r.dataLenCnt > 2 then
                  v.dataLenCnt := r.dataLenCnt - 2;
               else
                  -- data for this column done; what about more columns though?
                  if r.activeColCnt > 1 then
                     v.activeColCnt := r.activeColCnt - 1;
                     v.toMeta  := '1';
                     v.toData  := '0';
                  else
                     -- close data frame if not expecting more data
                     v.sAxisMaster.tLast := not(r.inPause);
                     v.toHeader := '1';
                     v.toData   := '0';
                  end if;
               end if;

               v.state := WAIT_VALID_S;

            end if;

            -- error detected!
            if v.decError = '1' then
               v.state := ERROR_S;
            end if;

         ----------------------------------------------------------------------
         -- the 'central' state; waits for valid signal from FIFO to read it
         -- then depending on the register state, it transitions
         -- to the associated state
         when WAIT_VALID_S =>
            v.rxFifoSlave.tReady := rxFifoMaster.tValid;

            if rxFifoMaster.tValid = '1' then
               if r.toHeader = '1' then
                  v.state := WAIT_HEADER_S;
               elsif r.toMeta = '1' then
                  v.state := PARSE_COL_METADATA_S;
               elsif r.toData = '1' then
                  v.state := PARSE_DATA_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- stay here until reset
         when ERROR_S =>
            v.fifoRst  := RST_POLARITY_G;
            v.decError := '1';

      end case;
      ---------------------------------------------------------------------------

      -- Outputs
      v.frameMetaWr := (v.sAxisMaster.tLast and not(r.sAxisMaster.tLast)) or
                       (v.decError          and not(r.decError));

      v.frameMetaDin(LANERX_META_BUFF_WIDTH_C-1)          := v.decError;
      v.frameMetaDin(LANERX_META_BUFF_WIDTH_C-2 downto 0) := r.trgCntHeader;

      rxFifoSlave <= v.rxFifoSlave;
      sAxisMaster <= r.sAxisMaster;

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
         MASTER_AXI_CONFIG_G => FPGA_RX_AXI_CONFIG_C)
      port map (
         -- Slave Port
         sAxisClk    => pgpClk,
         sAxisRst    => pgpFifoRst,
         sAxisMaster => sAxisMaster,
         sAxisSlave  => sAxisSlave,
         -- Master Port
         mAxisClk    => sysClk,
         mAxisRst    => sysFifoRst,
         mAxisMaster => obAxisMaster,
         mAxisSlave  => obAxisSlave);

   -- AXI-Stream FIFO does not have RST_POLARITY_G
   sysFifoRst <= ite(toBoolean(RST_POLARITY_G), sysRst,  not(sysRst));
   pgpFifoRst <= ite(toBoolean(RST_POLARITY_G), laneRst, not(laneRst));

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

end rtl;
