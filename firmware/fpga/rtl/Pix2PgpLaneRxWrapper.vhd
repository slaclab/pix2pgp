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
      META_FIFO_ADDR_WIDTH_G : positive := 4;
      AXIS_FIFO_ADDR_WIDTH_G : positive := 10);
   port(
      -- General Interface
      laneClk        : in  sl;
      laneRst        : in  sl := not(RST_POLARITY_G);
      -- RX FIFO Interface
      pgp4RxMaster   : in  AxiStreamMasterType;
      pgp4RxSlave    : out AxiStreamSlaveType;
      -- ASIC Rx Interface
      discBadColTrg  : in  sl;
      lanePostError  : in  sl;
      laneTrgCnt     : out slv(TRGCNT_WIDTH_C-1 downto 0);
      laneFrameSize  : out slv(LANERX_FRAME_SIZE_WIDTH_C-1 downto 0);
      laneDecError   : out sl;
      laneFull       : out sl;
      laneReady      : out sl;
      lanePauseError : out sl;
      laneMetaValid  : out sl;
      laneMetaRd     : in  sl;
      laneRxMaster   : out AxiStreamMasterType;
      laneRxSlave    : in  AxiStreamSlaveType);
end Pix2PgpLaneRxWrapper;

architecture rtl of Pix2PgpLaneRxWrapper is

   signal frameMetaRd    : sl := '0';
   signal frameMetaDout  : slv(LANERX_META_DWIDTH_C-1 downto 0) := (others => '0');
   signal frameMetaValid : sl := '0';
   signal laneRxFull     : sl := '0';
   signal pauseError     : sl := '0';
   signal laneRxRst      : sl := '0';
   signal postError      : sl := '0';
   signal discard        : sl := '0';
   signal laneRxReady    : sl := '0';
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
         discard        => discard,
         frameMetaRd    => frameMetaRd,
         frameMetaDout  => frameMetaDout,
         frameMetaValid => frameMetaValid,
         laneRxFull     => laneRxFull,
         laneRxReady    => laneRxReady,
         pauseError     => pauseError,
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

   U_PipelineDiscard : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => discBadColTrg,
         dout(0) => discard);

   U_PipelineLaneRxFull : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => laneRxFull,
         dout(0) => laneFull);

   U_PipelineLanePauseError : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => pauseError,
         dout(0) => lanePauseError);

   U_PipelineLaneMetaValid : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => frameMetaValid,
         dout(0) => laneMetaValid);

   U_PipelineLaneMetaRd : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => laneMetaRd,
         dout(0) => frameMetaRd);

   U_PipelineTrgCnt : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => TRGCNT_WIDTH_C,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk  => laneClk,
         din  => frameMetaDout(LANE_TRGCNT_POS_C),
         dout => laneTrgCnt);

   U_PipelineFrameSize : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => LANERX_FRAME_SIZE_WIDTH_C,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk  => laneClk,
         din  => frameMetaDout(LANE_SIZE_POS_C),
         dout => laneFrameSize);

   U_PipelineDecError : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => frameMetaDout(LANE_DEC_ERROR_POS_C),
         dout(0) => laneDecError);

   U_PipelineLaneRxReady : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => PIPE_STAGES_G)
      port map (
         clk     => laneClk,
         din(0)  => laneRxReady,
         dout(0) => laneReady);

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
