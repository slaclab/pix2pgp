-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp LaneRx Filter; checks for decoding errors and discards
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

entity Pix2PgpLaneRxFilter is
   generic(
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1';   -- '1' for active high rst, '0' for active low
      PIPE_STAGES_G  : natural := 1);
   port(
      -- General Interface
      sysClk         : in  sl;
      sysRst         : in  sl := not(RST_POLARITY_G);
      -- Lane Interface
      laneRxRst      : out sl;
      frameMetaRd    : out sl;
      frameMetaDout  : in  slv(LANERX_META_DWIDTH_C-1 downto 0);
      frameMetaValid : in  sl;
      laneFull       : in  sl;
      -- AXI-Stream from Lane
      ibAxisMaster   : in  AxiStreamMasterType;
      ibAxisSlave    : out AxiStreamSlaveType;
      -- ASIC Rx Interface
      laneTrgCnt     : out slv(TRGCNT_WIDTH_C-1 downto 0);
      laneFrameSize  : out slv(LANERX_FRAME_SIZE_WIDTH_C-1 downto 0);
      laneError      : out sl;
      lanePauseError : out sl;
      laneMetaValid  : out sl;
      laneMetaRd     : in  sl;
      laneRxMaster   : out AxiStreamMasterType;
      laneRxSlave    : in  AxiStreamSlaveType);
end Pix2PgpLaneRxFilter;

architecture rtl of Pix2PgpLaneRxFilter is

   -- how much to stretch laneRxRst
   constant LANE_RX_RST_WIDTH_C : natural := 10;

   type RegType is record
      errorFlag    : sl;
      inError      : sl;
      frameMetaRd  : sl;
      checking     : sl;
      valid        : sl;
      frameMetaWr  : sl;
      frameMetaDin : slv(LANERX_META_DWIDTH_C-1 downto 0);
      waitCnt      : slv(1 downto 0);
      sAxisMaster  : AxiStreamMasterType;
      ibAxisSlave  : AxiStreamSlaveType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      errorFlag    => '0',
      inError      => '0',
      frameMetaRd  => '0',
      checking     => '0',
      valid        => '0',
      frameMetaWr  => '0',
      frameMetaDin => (others => '0'),
      waitCnt      => (others => '0'),
      sAxisMaster  => AXI_STREAM_MASTER_INIT_C,
      ibAxisSlave  => AXI_STREAM_SLAVE_INIT_C);

   signal r   : RegType;
   signal rin : RegType;

   signal sAxisMaster  : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal sAxisSlave   : AxiStreamSlaveType  := AXI_STREAM_SLAVE_INIT_C;

   signal obAxisMaster : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal obAxisSlave  : AxiStreamSlaveType  := AXI_STREAM_SLAVE_INIT_C;

   signal metaDout     : slv(LANERX_META_DWIDTH_C-1 downto 0) := (others => '0');
   signal metaFull     : sl := '0';
   signal metaRdEn     : sl := '0';
   signal metaValid    : sl := '0';

   signal laneErrorDly : sl := '0';
   signal metaFullDly  : sl := '0';

   signal sysFifoRst   : sl := '0';

   signal axiFull      : sl := '0';
   signal axiFullDly   : sl := '0';

   signal laneFullDly  : sl := '0';

begin

   comb : process (r, frameMetaDout, sysRst, frameMetaValid, ibAxisMaster, sAxisSlave) is
      variable v        : RegType;
      variable axisTrg  : slv(TRGCNT_WIDTH_C-1 downto 0);
      variable trg      : slv(TRGCNT_WIDTH_C-1 downto 0);
      variable size     : slv(LANERX_FRAME_SIZE_WIDTH_C-1 downto 0);
      variable decErr   : sl;
      variable pauseErr : sl;
   begin

      -- Latch the current value
      v := r;

      axisTrg  := resize(ibAxisMaster.tData(TRGCNT_POS_C), TRGCNT_WIDTH_C);
      decErr   := frameMetaDout(LANE_DEC_ERROR_POS_C);
      pauseErr := frameMetaDout(LANE_PAUSE_ERROR_POS_C);
      trg      := frameMetaDout(LANE_TRGCNT_POS_C);
      size     := frameMetaDout(LANE_SIZE_POS_C);

      -- defaults
      v.frameMetaRd := '0';
      v.frameMetaWr := '0';

      -- refuse to receive the AXI-Stream by default
      v.ibAxisSlave.tReady := '0';
      v.sAxisMaster        := AXI_STREAM_MASTER_INIT_C;

      -- ready to accept data
      if r.valid = '1' then
         v.ibAxisSlave.tReady := sAxisSlave.tReady;
         v.sAxisMaster        := ibAxisMaster;
      end if;

      -- get the metadata first...
      if frameMetaValid = '1' and v.valid = '0' and r.checking = '0' and r.inError = '0' then
         v.errorFlag := decErr;
         v.checking  := '1';
      end if;

      -- checking trigger counter against inbound AXI stream valid and checking errorFlag
      if r.errorFlag = '0' and r.checking = '1' and r.inError = '0' then
         v.frameMetaRd := '1'; -- pop the metadata word
         v.checking    := '0'; -- drop the flag
         v.valid       := '1'; -- safe to pipe in the data

         -- write the metadata to the next buffer
         v.frameMetaDin(LANE_DEC_ERROR_POS_C)   := decErr;
         v.frameMetaDin(LANE_PAUSE_ERROR_POS_C) := pauseErr;
         v.frameMetaDin(LANE_SIZE_POS_C)        := size;
         v.frameMetaDin(LANE_TRGCNT_POS_C)      := trg;
         v.frameMetaWr := '1';

      elsif r.errorFlag = '1' and r.checking = '1' and r.inError = '0' then
         v.inError := '1'; -- can only be cleared by an upstream reset
      end if;

      if r.valid = '1' and ibAxisMaster.tLast = '1' and ibAxisMaster.tValid = '1' then
         v.valid   := '0'; -- last word received; force the slave to non-ready again
         v.waitCnt := r.waitCnt + 1; -- start the wait counter
      end if;

      -- always wait before re-evaluating FIFO (to avoid double-reading)
      if uOr(r.waitCnt) = '1' then
         v.waitCnt := r.waitCnt + 1;
         if allBits(r.waitCnt, '1') then
            v.waitCnt  := (others => '0');
            v.checking := '0';
         end if;
      end if;

      -- Outputs
      sAxisMaster <= v.sAxisMaster;
      ibAxisSlave <= v.ibAxisSlave;
      frameMetaRd <= r.frameMetaRd;

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

   U_StretchRst : entity surf.SynchronizerOneShot
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         PULSE_WIDTH_G  => LANE_RX_RST_WIDTH_C)
      port map (
         clk     => sysClk,
         dataIn  => sysRst,
         dataOut => laneRxRst);

   ------------------
   -- Axi-Stream FIFO
   ------------------
   U_Fifo : entity surf.AxiStreamFifoV2
      generic map (
         -- General Configurations
         TPD_G               => TPD_G,
         RST_ASYNC_G         => RST_ASYNC_G,
         -- FIFO configurations
         FIFO_ADDR_WIDTH_G   => AXIS_FIFO_ADDR_WIDTH_C,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => ASIC_DATA_AXI_CONFIG_C,
         MASTER_AXI_CONFIG_G => FPGA_RX_AXI_CONFIG_C)
      port map (
         -- Slave Port
         sAxisClk    => sysClk,
         sAxisRst    => sysFifoRst,
         sAxisMaster => sAxisMaster,
         sAxisSlave  => sAxisSlave,
         -- Status Port
         fifoFull    => axiFull,
         -- Master Port
         mAxisClk    => sysClk,
         mAxisRst    => sysFifoRst,
         mAxisMaster => obAxisMaster,
         mAxisSlave  => obAxisSlave);

   sysFifoRst <= ite(toBoolean(RST_POLARITY_G), sysRst,  not(sysRst));

   U_PipelineAxiFull : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => sysClk,
         din(0)  => axiFull,
         dout(0) => axiFullDly);

   ----------------------------------------
   -- Metadata Buffer
   ----------------------------------------
   U_laneMetaBuffer : entity surf.Fifo
      generic map (
         TPD_G           => TPD_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         MEMORY_TYPE_G   => "block",
         FWFT_EN_G       => true,
         DATA_WIDTH_G    => LANERX_META_DWIDTH_C,
         ADDR_WIDTH_G    => LANERX_META_ADDR_WIDTH_C)
      port map (
         rst      => sysRst,
         -- Write Ports
         wr_clk   => sysClk,
         wr_en    => r.frameMetaWr,
         din      => r.frameMetaDin,
         full     => metaFull,
         -- Read Ports
         rd_clk   => sysClk,
         rd_en    => metaRdEn,
         dout     => metaDout,
         valid    => metaValid);

   U_PipelineRd : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => sysClk,
         din(0)  => laneMetaRd,
         dout(0) => metaRdEn);

   U_PipelineValid : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => sysClk,
         din(0)  => metaValid,
         dout(0) => laneMetaValid);

   U_PipelineError : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => sysClk,
         din(0)  => metaDout(LANE_DEC_ERROR_POS_C),
         dout(0) => laneErrorDly);


   U_PipelinePauseError : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => sysClk,
         din(0)  => metaDout(LANE_PAUSE_ERROR_POS_C),
         dout(0) => lanePauseError);

   U_PipelineMetaFull : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => sysClk,
         din(0)  => metaFull,
         dout(0) => metaFullDly);

   U_PipelineSize : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => LANERX_FRAME_SIZE_WIDTH_C,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk  => sysClk,
         din  => metaDout(LANE_SIZE_POS_C),
         dout => laneFrameSize);

   U_PipelineTrgCnt : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => TRGCNT_WIDTH_C,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk  => sysClk,
         din  => metaDout(LANE_TRGCNT_POS_C),
         dout => laneTrgCnt);

   U_PipelineLaneFull : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => sysClk,
         din(0)  => laneFull,
         dout(0) => laneFullDly);

   laneError <= laneErrorDly or metaFullDly or axiFullDly or laneFullDly;

   -----------------------------------------
   -- Reverses on a per-word basis
   -----------------------------------------
   GEN_PIPE: if PIPE_STAGES_G > 0 generate

      U_Pipe : entity surf.AxiStreamPipeline
         generic map (
            TPD_G          => TPD_G,
            RST_ASYNC_G    => RST_ASYNC_G,
            RST_POLARITY_G => RST_POLARITY_G,
            PIPE_STAGES_G  => PIPE_STAGES_G)
         port map (
            -- Clock and Reset
            axisClk     => sysClk,
            axisRst     => sysRst,
            -- Slave Port
            sAxisMaster => obAxisMaster,
            sAxisSlave  => obAxisSlave,
            -- Master Port
            mAxisMaster => laneRxMaster,
            mAxisSlave  => laneRxSlave);

   end generate GEN_PIPE;

   GEN_NO_PIPE: if PIPE_STAGES_G <= 0 generate

      obAxisSlave  <= laneRxSlave;
      laneRxMaster <= obAxisMaster;

   end generate GEN_NO_PIPE;

end rtl;
