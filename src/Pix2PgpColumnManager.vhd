-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Column Manager
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

entity Pix2PgpColumnManager is
   generic(
      TPD_G             : time    := 1 ns;
      RST_ASYNC_G       : boolean := false;
      RST_POLARITY_G    : sl      := '1';
      DATAFIFO_PIPE_G   : positive := 2;
      STATUSFIFO_PIPE_G : positive := 2;
      STANDALONE_G      : boolean := false);
   port(
      -- General Interface
      sparseClk : in  sl;
      pgpClk    : in  sl;
      rst       : in  sl := not(RST_POLARITY_G);
      -- Sparse Logic Interface
      tok       : in  sl;
      tokFb     : in  sl;
      ackN      : in  sl;
      wrEn      : in  sl;
      din       : in  slv(SPARSE_DWIDTH_C-1 downto 0);
      -- Arbiter Interface
      statusRd  : in  sl;
      dataRd    : in  sl;
      statusBus : out Pix2PgpStatusBusType;
      dataBus   : out Pix2PgpDataBusType);
end Pix2PgpColumnManager;

architecture rtl of Pix2PgpColumnManager is

   signal statusFifoDout : slv(STATUSFIFO_DWIDTH_C-1 downto 0) := (others => '0');
   signal statusFifoFull : sl := '0';
   signal dataFifoFull   : sl := '0';

   signal statusWrEn     : sl := '0';
   signal statusDin      : slv(STATUSFIFO_DWIDTH_C-1 downto 0) := (others => '0');
   signal dataWrEn       : sl := '0';
   signal dataDin        : slv(SPARSE_DWIDTH_C-1 downto 0) := (others => '0');

   type StateType is (
      IDLE_S,
      MON_TOKFB_S,
      CHK_WRCNT_S);

   type RegType is record
      -- i/o
      tok            : sl;
      tokFb          : sl;
      ackN           : sl;
      wrEn           : sl;
      statusRd       : sl;
      dataRd         : sl;
      din            : slv(SPARSE_DWIDTH_C-1 downto 0);
      statusBus      : Pix2PgpStatusBusType;
      dataBus        : Pix2PgpDataBusType;
      -- internal
      overOcc        : sl;
      statusFifoWrEn : sl;
      statusFifoDin  : slv(STATUSFIFO_DWIDTH_C-1 downto 0);
      ackCnt         : slv(DATALEN_WIDTH_C-1 downto 0);
      wrEnCnt        : slv(DATALEN_WIDTH_C-1 downto 0);
      trgCnt         : slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0);
      state          : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- i/o
      tok            => '0',
      tokFb          => '0',
      ackN           => '0',
      wrEn           => '0',
      statusRd       => '0',
      dataRd         => '0',
      din            => (others => '0'),
      statusBus      => DEFAULT_PIX2PGP_STATUSBUS_C,
      dataBus        => DEFAULT_PIX2PGP_DATABUS_C,
      -- internal
      overOcc        => '0',
      statusFifoWrEn => '0',
      statusFifoDin  => (others => '0'),
      ackCnt         => (others => '0'),
      wrEnCnt        => (others => '0'),
      trgCnt         => (others => '1'),
      state          => IDLE_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Column Manager FSM
   ------------------------------------------------
   comb : process (r, rst, tok, tokFb, ackN, wrEn, din, statusRd, dataRd) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Register inputs
      v.tok      := tok;
      v.tokFb    := tokFb;
      v.ackN     := ackN;
      v.wrEn     := wrEn;
      v.din      := din;
      v.statusRd := statusRd;
      v.dataRd   := dataRd;

      -- over-occupancy detection (received a token while busy)
      if (r.state /= IDLE_S and v.tok = '0' and r.tok = '1') then
         v.overOcc := '1';
      end if;

      -- ackN counter management (falling-edge detection)
      if (r.state /= IDLE_S and v.ackN = '0' and r.ackN = '1') then
         v.ackCnt := r.ackCnt + 1;
      end if;

      -- wrEn counter management (rising-edge detection)
      if (r.state /= IDLE_S and v.wrEn = '1' and r.wrEn = '0') then
         v.wrEnCnt := r.wrEnCnt + 1;
      end if;

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- wait for token; also reset the counters and flags
         when IDLE_S =>
            v.overOcc        := '0';
            v.statusFifoWrEn := '0';
            v.wrEnCnt        := toSlv(0, DATALEN_WIDTH_C);
            v.ackCnt         := toSlv(0, DATALEN_WIDTH_C);

            -- falling-edge detection
            if (v.tok = '0' and r.tok = '1') then
               v.trgCnt := r.trgCnt + 1;
               v.state  := MON_TOKFB_S;
            end if;

         ----------------------------------------------------------------------
         -- wait for token-feedback
         when MON_TOKFB_S =>

            -- rising-edge detection
            if (v.tokFb = '1' and r.tokFb = '0') then
               v.state := CHK_WRCNT_S;
            end if;

         ----------------------------------------------------------------------
         -- check that all data have been written
         when CHK_WRCNT_S =>

            -- done; time to write into the status FIFO and go back to idle
            if (r.ackCnt = r.wrEnCnt) then

               if r.wrEnCnt(0) = '1' then
                  -- wrote odd number of hits? write a dummy word;
                  -- hold for one clock cycle;
                  -- wrEn will switch to input port input by default on next cycle
                  v.wrEn := '1';
               end if;

               v.statusFifoDin(STATUSFIFO_OVEROCC_POS_C) := r.overOcc;
               v.statusFifoDin(STATUSFIFO_TRG_POS_C)     := r.trgCnt;
               v.statusFifoDin(STATUSFIFO_DATALEN_POS_C) := r.wrEnCnt;
               v.statusFifoWrEn := '1';
               v.state          := IDLE_S;
            end if;
      end case;
      -------------------------------------------------------------------------

      -- Reset
      if (RST_ASYNC_G = false and rst = '1') then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (sparseClk, rst) is
   begin
      if (RST_ASYNC_G and rst = '1') then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(sparseClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

   ------------------------------------------------
   -- Status FIFO
   ------------------------------------------------
   -- pipeline the status FIFO input signals to give some freedom in placement
   U_PipelineStatusWrEn : entity surf.Synchronizer
      generic map (
         TPD_G       => TPD_G,
         RST_ASYNC_G => RST_ASYNC_G,
         STAGES_G    => STATUSFIFO_PIPE_G)
      port map (
         clk     => sparseClk,
         rst     => rst,
         dataIn  => r.statusFifoWrEn,
         dataOut => statusWrEn);

   U_PipelineStatusDin : entity surf.SynchronizerVector
      generic map (
         TPD_G       => TPD_G,
         RST_ASYNC_G => RST_ASYNC_G,
         WIDTH_G     => STATUSFIFO_DWIDTH_C,
         STAGES_G    => STATUSFIFO_PIPE_G)
      port map (
         clk     => sparseClk,
         rst     => rst,
         dataIn  => r.statusFifoDin,
         dataOut => statusDin);

   U_StatusFifo : entity pix2pgp.Pix2PgpFifoWrapper
      generic map (
         TPD_G           => TPD_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         GEN_SYNC_FIFO_G => true,
         WR_DATA_WIDTH_G => STATUSFIFO_DWIDTH_C,
         RD_DATA_WIDTH_G => STATUSFIFO_DWIDTH_C,
         ADDR_WIDTH_G    => 8,
         STANDALONE_G    => STANDALONE_G)
      port map (
         -- Resets
         rst   => rst,
         -- Write Interface
         wrClk => sparseClk,
         wrEn  => statusWrEn,
         din   => statusDin,
         full  => statusFifoFull,
         -- Read Interface
         rdClk => pgpClk,
         rdEn  => statusRd,
         empty => statusBus.statusEmpty,
         dout  => statusFifoDout);

   statusBus.overOcc <= statusFifoDout(STATUSFIFO_OVEROCC_POS_C);
   statusBus.trgNum  <= statusFifoDout(STATUSFIFO_TRG_POS_C);
   statusBus.dataLen <= statusFifoDout(STATUSFIFO_DATALEN_POS_C);

   U_syncStatusFull : entity surf.Synchronizer
      generic map (
         TPD_G       => TPD_G,
         RST_ASYNC_G => RST_ASYNC_G,
         STAGES_G    => STATUSFIFO_PIPE_G)
      port map (
         clk     => pgpClk,
         rst     => rst,
         dataIn  => statusFifoFull,
         dataOut => statusBus.statusFull);

   ------------------------------------------------
   -- Data FIFO
   ------------------------------------------------
   -- pipeline the data FIFO input signals to give some freedom in placement
   U_PipelineDataWrEn : entity surf.Synchronizer
      generic map (
         TPD_G       => TPD_G,
         RST_ASYNC_G => RST_ASYNC_G,
         STAGES_G    => DATAFIFO_PIPE_G)
      port map (
         clk     => sparseClk,
         rst     => rst,
         dataIn  => r.wrEn,
         dataOut => dataWrEn);

   U_PipelineDataDin : entity surf.SynchronizerVector
      generic map (
         TPD_G       => TPD_G,
         RST_ASYNC_G => RST_ASYNC_G,
         WIDTH_G     => SPARSE_DWIDTH_C,
         STAGES_G    => DATAFIFO_PIPE_G)
      port map (
         clk     => sparseClk,
         rst     => rst,
         dataIn  => r.din,
         dataOut => dataDin);

   U_DataFifo : entity pix2pgp.Pix2PgpFifoWrapper
      generic map (
         TPD_G           => TPD_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         GEN_SYNC_FIFO_G => true,
         WR_DATA_WIDTH_G => SPARSE_DWIDTH_C,
         RD_DATA_WIDTH_G => DATABUS_DWIDTH_C,
         ADDR_WIDTH_G    => 12,
         STANDALONE_G    => STANDALONE_G)
      port map (
         -- Resets
         rst   => rst,
         -- Write Interface
         wrClk => sparseClk,
         wrEn  => dataWrEn,
         full  => dataFifoFull,
         din   => dataDin,
         -- Read Interface
         rdClk => pgpClk,
         rdEn  => dataRd,
         dout  => dataBus.data);

   U_syncDataFull : entity surf.Synchronizer
      generic map (
         TPD_G       => TPD_G,
         RST_ASYNC_G => RST_ASYNC_G,
         STAGES_G    => STATUSFIFO_PIPE_G)
      port map (
         clk     => pgpClk,
         rst     => rst,
         dataIn  => dataFifoFull,
         dataOut => statusBus.dataFull);

end rtl;
