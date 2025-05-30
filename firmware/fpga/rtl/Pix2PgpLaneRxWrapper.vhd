-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Wrapper for Pix2Pgp Single-Lane Receiver
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

entity Pix2PgpLaneRxWrapper is
   generic(
      TPD_G                  : time     := 1 ns;
      RST_ASYNC_G            : boolean  := false;
      RST_POLARITY_G         : sl       := '1';  -- '1' for active high rst, '0' for active low
      PIPE_STAGES_G          : natural  := 1;
      META_FIFO_ADDR_WIDTH_G : positive := 6;
      AXIS_FIFO_ADDR_WIDTH_G : positive := 8);
   port(
      -- General Interface
      laneClk        : in  sl;
      laneRst        : in  sl := not(RST_POLARITY_G);
      -- RX FIFO Interface
      pgp4RxMaster   : in  AxiStreamMasterType;
      pgp4RxSlave    : out AxiStreamSlaveType;
      -- ASIC Rx Interface
      dropBadColTrg  : in  sl;
      lanePostError  : in  sl;
      laneStatus     : out Pix2PgpLaneStatusType;
      laneMetaRd     : in  sl;
      laneRxMaster   : out AxiStreamMasterType;
      laneRxSlave    : in  AxiStreamSlaveType);
end Pix2PgpLaneRxWrapper;

architecture rtl of Pix2PgpLaneRxWrapper is

   signal frameMetaRd    : sl := '0';
   signal frameMetaDout  : slv(LANERX_META_DWIDTH_C-1 downto 0) := (others => '0');
   signal frameMetaValid : sl := '0';
   signal laneRxFull     : sl := '0';
   signal laneRxRst      : sl := '0';
   signal postError      : sl := '0';
   signal dropBadTrg     : sl := '0';
   signal laneRxOk       : sl := '0';
   signal laneRxInError  : sl := '0';
   signal obAxiMaster    : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal obAxiSlave     : AxiStreamSlaveType  := AXI_STREAM_SLAVE_INIT_C;

begin

   U_Lane: entity pix2pgp.Pix2PgpLaneRx
      generic map(
         TPD_G                  => TPD_G,
         RST_ASYNC_G            => RST_ASYNC_G,
         RST_POLARITY_G         => RST_POLARITY_G,
         META_FIFO_ADDR_WIDTH_G => META_FIFO_ADDR_WIDTH_G,
         AXIS_FIFO_ADDR_WIDTH_G => AXIS_FIFO_ADDR_WIDTH_G)
      port map(
         -- General Interface
         laneClk        => laneClk,
         laneRst        => laneRxRst,
         -- RX FIFO Interface
         pgp4RxMaster   => pgp4RxMaster,
         pgp4RxSlave    => pgp4RxSlave,
         -- StreamRx Interface
         postError      => postError,
         dropBadTrg     => dropBadTrg,
         frameMetaRd    => frameMetaRd,
         frameMetaDout  => frameMetaDout,
         frameMetaValid => frameMetaValid,
         laneRxFull     => laneRxFull,
         laneRxOk       => laneRxOk,
         laneRxInError  => laneRxInError,
         -- AXI-Stream to StreamRx
         obAxisMaster   => obAxiMaster,
         obAxisSlave    => obAxiSlave);

   U_PipelineLaneRxReset : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => laneRst,
         dout(0) => laneRxRst);

   U_PipelineLanePostError : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => lanePostError,
         dout(0) => postError);

   U_PipelineDrop : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => dropBadColTrg,
         dout(0) => dropBadTrg);

   U_PipelineLaneMetaRd : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => laneMetaRd,
         dout(0) => frameMetaRd);

   U_PipelinelaneRxInError : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => laneRxInError,
         dout(0) => laneStatus.inError);

   U_PipelineLaneMetaValid : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => frameMetaValid,
         dout(0) => laneStatus.valid);

   U_PipelineLaneRxFull : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => laneRxFull,
         dout(0) => laneStatus.overflow);

   U_PipelineLaneOverOcc : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => frameMetaDout(LANE_OVEROCC_POS_C),
         dout(0) => laneStatus.overOcc);

   U_PipelineLanePause : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => frameMetaDout(LANE_PAUSE_POS_C),
         dout(0) => laneStatus.pause);

   U_PipelineLanePauseError : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => frameMetaDout(LANE_PAUSE_ERROR_POS_C),
         dout(0) => laneStatus.pauseError);

   U_PipelineTrgCnt : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => TRGCNT_WIDTH_C,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk  => laneClk,
         din  => frameMetaDout(LANE_TRGCNT_POS_C),
         dout => laneStatus.trgCnt);

   U_PipelineFrameSize : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => LANERX_FRAME_SIZE_WIDTH_C,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk  => laneClk,
         din  => frameMetaDout(LANE_SIZE_POS_C),
         dout => laneStatus.frameSize);

   U_PipelineDecError : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => frameMetaDout(LANE_DEC_ERROR_POS_C),
         dout(0) => laneStatus.decError);

   GEN_PIPE: if PIPE_STAGES_G > 0 generate

      U_Pipe : entity surf.AxiStreamPipeline
         generic map (
            TPD_G          => TPD_G,
            RST_ASYNC_G    => RST_ASYNC_G,
            RST_POLARITY_G => RST_POLARITY_G,
            PIPE_STAGES_G  => PIPE_STAGES_G)
         port map (
            -- Clock and Reset
            axisClk     => laneClk,
            axisRst     => laneRst,
            -- Slave Port
            sAxisMaster => obAxiMaster,
            sAxisSlave  => obAxiSlave,
            -- Master Port
            mAxisMaster => laneRxMaster,
            mAxisSlave  => laneRxSlave);

   end generate GEN_PIPE;

   GEN_NO_PIPE: if PIPE_STAGES_G <= 0 generate

      obAxiSlave   <= laneRxSlave;
      laneRxMaster <= obAxiMaster;

   end generate GEN_NO_PIPE;

end rtl;
