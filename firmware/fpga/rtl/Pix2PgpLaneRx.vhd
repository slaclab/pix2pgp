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
      -- RX FIFO Interface
      pgpValid       : in  sl;
      pgpData        : in  slv(DATABUS_DWIDTH_C-1 downto 0);
      pgpReady       : out sl;
      -- Adapter Interface
      frameDataRd    : in  sl;
      frameDataDout  : out slv(DATABUS_DWIDTH_C-1 downto 0);
      frameDataFull  : out sl;
      frameMetaRd    : in  sl;
      frameMetaDout  : out slv(LANERX_FRAMELEN_BUFF_WIDTH_C-1 downto 0);
      frameMetaValid : out sl
   );
end Pix2PgpLaneRx;

architecture rtl of Pix2PgpLaneRx is

   type StateType is (
      WAIT_HEADER_S,
      PARSE_DATA_S,
      ERROR_S);

   type RegType is record
      protoBufDout   : slv(DATABUS_DWIDTH_C-1 downto 0);
      protoBufValid  : sl;
      isDummy        : sl;
      din            : slv(DATABUS_DWIDTH_C-1 downto 0);
      valid          : sl;
      decError       : sl;
      waitHeader     : sl;
      colMeta        : sl;
      frameMetaWr    : sl;
      frameMetaEmpty : sl;
      frameMetaDin   : slv(LANERX_FRAMELEN_BUFF_WIDTH_C-1 downto 0);
      frameMetaCnt   : slv(LANERX_FRAMELEN_WIDTH_C-1 downto 0);
      errorRstDone   : sl;
      inPause        : sl;
      trgCntHeader   : slv(TRGCNT_WIDTH_C-1 downto 0);
      activeColCnt   : slv(BITMAX_COL_MANAGERS_C downto 0);
      dataLenCnt     : slv(7 downto 0);
      frameDataRst   : sl;
      state          : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      protoBufDout   => (others => '0'),
      protoBufValid  => '0',
      isDummy        => '0',
      din            => (others => '0'),
      valid          => '0',
      decError       => '0',
      waitHeader     => '1',
      colMeta        => '0',
      frameMetaWr    => '0',
      frameMetaEmpty => '0',
      frameMetaDin   => (others => '0'),
      frameMetaCnt   => (others => '0'),
      errorRstDone   => '0',
      inPause        => '0',
      trgCntHeader   => (others => '0'),
      activeColCnt   => (others => '0'),
      dataLenCnt     => (others => '0'),
      frameDataRst   => not(RST_POLARITY_G),
      state          => WAIT_HEADER_S
   );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   signal pgpFull           : sl := '0';
   signal protoBufValid     : sl := '0';
   signal protoBufDout      : slv(DATABUS_DWIDTH_C-1 downto 0) := (others => '0');

   signal frameMetaWr       : sl := '0';
   signal frameMetaDin      : slv(LANERX_FRAMELEN_BUFF_WIDTH_C-1 downto 0) := (others => '0');
   signal frameMetaEmpty    : sl := '0';
   signal frameMetaEmptyDly : sl := '0';
   signal frameDataEmpty    : sl := '0';

   signal frameDataRst      : sl := not(RST_POLARITY_G);
   signal frameDataWr       : sl := '0';
   signal frameDataDin      : slv(DATABUS_DWIDTH_C-1 downto 0) := (others => '0');

   signal dbgTrg            : slv(7 downto 0) := (others => '0');
   signal dbgLen            : slv(7 downto 0) := (others => '0');

begin

   -----------------------------
   -- First Buffer Level
   -----------------------------
   U_protoBuffer : entity surf.Fifo
      generic map (
         TPD_G           => TPD_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         GEN_SYNC_FIFO_G => false, -- false = dual-clock FIFO
         MEMORY_TYPE_G   => "block",
         FWFT_EN_G       => true,
         DATA_WIDTH_G    => DATABUS_DWIDTH_C,
         ADDR_WIDTH_G    => 4)
      port map (
         rst      => sysRst,
         -- Write Ports
         wr_clk   => pgpClk,
         wr_en    => pgpValid,
         din      => pgpData,
         overflow => pgpFull,
         -- Read Ports
         rd_clk   => sysClk,
         rd_en    => '1',
         dout     => protoBufDout,
         valid    => protoBufValid);

   comb : process (r, sysRst, protoBufDout, protoBufValid, pgpFull, frameMetaEmptyDly) is

      -- omnipresent
      variable v : RegType;

      -- various data fields encoded in variables; are used in data checks and FSM flow control

      -- header
      variable overOcc    : sl := '0';
      variable pause      : sl := '0';
      variable colError   : sl := '0';
      variable pauseError : sl := '0';
      variable timeout    : sl := '0';
      variable colBitmask : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
      variable trgCnt     : slv(TRGCNT_WIDTH_C-1 downto 0)        := (others => '0');

      -- column metadata
      variable metaTrgCnt  : slv(7 downto 0) := (others => '0');
      variable metaDataLen : slv(7 downto 0) := (others => '0');

   begin

      -- Latch the current value
      v := r;

      -- Register inputs
      v.protoBufDout   := protoBufDout;
      v.protoBufValid  := protoBufValid;
      v.frameMetaEmpty := frameMetaEmptyDly;

      -- Defaults
      v.frameMetaWr  := '0';
      v.isDummy      := '0';
      v.frameDataRst := not(RST_POLARITY_G);

      -- First layer of dataRx
      v.din   := r.protoBufDout; -- register the data
      v.valid := '0';            -- disable by default; enable one level below

      if r.protoBufValid = '1' then
         if r.decError = '1' and isDummy(r.protoBufDout) then
            -- dummy header; useful when wanting to get out of error state
            v.isDummy := '1';
         elsif r.waitHeader = '0' and r.decError = '0' then
            -- regular data
            v.valid := '1';
         elsif r.waitHeader = '1' and not(isDummy(r.protoBufDout)) then
            -- regular header
            v.valid := '1';
         end if;
      end if;

      -- header variables
      overOcc     := r.din(OVEROCC_FLAG_POS_C);
      pause       := r.din(PAUSE_FLAG_POS_C);
      colError    := r.din(COLUMN_ERROR_FLAG_POS_C);
      pauseError  := r.din(PAUSE_ERROR_FLAG_POS_C);
      timeout     := r.din(TIMEOUT_FLAG_POS_C);
      colBitmask  := r.din(COL_BITMASK_POS_C);
      trgCnt      := resize(r.din(TRG_CNT_POS_C), TRGCNT_WIDTH_C);
      -- column metadata variables
      metaTrgCnt  := r.din(META_TRG_CNT_POS_C);
      metaDataLen := r.din(META_DATALEN_POS_C);

      if r.frameMetaWr = '1' then
         v.frameMetaCnt := (others => '0');
      elsif r.valid = '1' then
         v.frameMetaCnt := r.frameMetaCnt + 1;
      end if;

      ---------------------------------------------------------------------------
      case r.state is
      ---------------------------------------------------------------------------
         -- stay here until a valid header comes in
         when WAIT_HEADER_S =>
            v.waitHeader   := '1';
            v.errorRstDone := '0';
            v.decError     := '0';

            if r.valid = '1' then
               v.inPause := pause;

               if uOr(colBitmask) = '0' then
                  v.frameMetaWr  := '1'; -- close data frame
               else
                  v.waitHeader   := '0';
                  v.trgCntHeader := trgCnt;
                  v.activeColCnt := onesCount(colBitmask);
                  v.colMeta      := '1';
                  v.state        := PARSE_DATA_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- parse column metadata and data
         when PARSE_DATA_S =>
            if r.valid = '1' then

               -- column metadata parsing here
               if r.colMeta = '1' then
                  v.activeColCnt := r.activeColCnt - 1;
                  v.dataLenCnt   := metaDataLen;

                  -- data check; override data parsing if in error
                  if metaTrgCnt /= r.trgCntHeader then
                     --metaDataLen >= slv(leftShift(conv_unsigned(1, 1), DATALEN_WIDTH_C)) then
                     v.decError    := '1';
                     v.frameMetaWr := '1';  -- close data frame
                     v.state       := ERROR_S;
                  end if;

                  v.colMeta := '0'; -- drop the flag

               else
                  -- actual data parsing here

                  -- still more data for this column
                  if r.dataLenCnt > 1 then
                     v.dataLenCnt := r.dataLenCnt - 1;
                  else

                     -- column done; what about the overall event though?
                     if r.activeColCnt > 0 then
                        -- more columns to go...
                        v.colMeta := '1';
                     else
                        -- done!
                        v.frameMetaWr := not(r.inPause); -- close data frame if not a paused frame
                        v.state       := WAIT_HEADER_S;
                     end if;
                  end if;

               end if;

            end if;

         ----------------------------------------------------------------------
         -- 1st stage: wait for data consumer to grab the error from the
         -- frame metadata buffer; -> reset the main data buffer

         -- 2nd stage: wait here until a dummy is detected;
         -- i.e. avoid writing any more garbage to the buffers
         --
         when ERROR_S =>
            if r.frameMetaEmpty = '1' and r.ErrorRstDone = '0' then
               v.frameDataRst := RST_POLARITY_G;
               v.errorRstDone := '1';
            end if;

            if r.isDummy = '1' and r.errorRstDone = '1' then
               v.state := WAIT_HEADER_S;
            end if;

      end case;
      ---------------------------------------------------------------------------

      -- Outputs
      v.frameMetaDin(LANERX_FRAMELEN_BUFF_WIDTH_C-1)          := r.decError;
      v.frameMetaDin(LANERX_FRAMELEN_BUFF_WIDTH_C-2 downto 0) := r.frameMetaCnt;

      pgpReady <= not(pgpFull); -- not registered (on pgp domain)

      dbgTrg <= metaTrgCnt;
      dbgLen <= metaDataLen;

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
   -- Metadata Buffer
   ----------------------------------------
   U_frameMetaBuffer : entity surf.Fifo
      generic map (
         TPD_G           => TPD_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         MEMORY_TYPE_G   => "block",
         FWFT_EN_G       => true,
         DATA_WIDTH_G    => LANERX_FRAMELEN_BUFF_WIDTH_C, -- dataLen plus the error flag
         ADDR_WIDTH_G    => 4)
      port map (
         rst      => sysRst,
         -- Write Ports
         wr_clk   => sysClk,
         wr_en    => frameMetaWr,
         din      => frameMetaDin,
         empty    => frameMetaEmpty,
         -- Read Ports
         rd_clk   => sysClk,
         rd_en    => frameMetaRd,
         dout     => frameMetaDout,
         valid    => frameMetaValid);

   U_PipelineMetaWr : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => LANERX_FIFO_PIPE_C+1) -- plus one! avoid writing zero length to the buff
      port map (
         clk     => sysClk,
         din(0)  => r.frameMetaWr,
         dout(0) => frameMetaWr);

   U_PipelineMetaDin : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => LANERX_FRAMELEN_BUFF_WIDTH_C,
         DELAY_G        => LANERX_FIFO_PIPE_C)
      port map (
         clk  => sysClk,
         din  => r.frameMetaDin,
         dout => frameMetaDin);

   U_PipelineMetaEmpty : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => LANERX_FIFO_PIPE_C)
      port map (
         clk     => sysClk,
         din(0)  => frameMetaEmpty,
         dout(0) => frameMetaEmptyDly);

   ----------------------------------------
   -- Main Data Buffer
   ----------------------------------------
   U_frameDataBuffer : entity surf.Fifo
      generic map (
         TPD_G           => TPD_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         MEMORY_TYPE_G   => "block",
         FWFT_EN_G       => true,
         DATA_WIDTH_G    => DATABUS_DWIDTH_C,
         ADDR_WIDTH_G    => LANERX_FIFO_ADDR_WIDTH_C)
      port map (
         rst      => frameDataRst,
         -- Write Ports
         wr_clk   => sysClk,
         wr_en    => frameDataWr,
         din      => frameDataDin,
         empty    => frameDataEmpty,
         overflow => frameDataFull,
         -- Read Ports
         rd_clk   => sysClk,
         rd_en    => frameDataRd,
         dout     => frameDataDout);

   U_PipelineDataRst : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => LANERX_FIFO_PIPE_C)
      port map (
         clk     => sysClk,
         din(0)  => r.frameDataRst,
         dout(0) => frameDataRst);

   U_PipelineDataWr : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => LANERX_FIFO_PIPE_C)
      port map (
         clk     => sysClk,
         din(0)  => r.valid,
         dout(0) => frameDataWr);

   U_PipelineDataDin : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => DATABUS_DWIDTH_C,
         DELAY_G        => LANERX_FIFO_PIPE_C)
      port map (
         clk  => sysClk,
         din  => r.din,
         dout => frameDataDin);

end rtl;
