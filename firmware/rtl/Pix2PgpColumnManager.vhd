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
      TPD_G             : time     := 1 ns;
      RST_ASYNC_G       : boolean  := false;
      RST_POLARITY_G    : sl       := '1';
      DATAFIFO_PIPE_G   : positive := 1;
      STATUSFIFO_PIPE_G : positive := 1;
      DATA_DEPTH_G      : integer  := 32;
      DATA_AF_LVL_G     : integer  := 30;
      STATUS_DEPTH_G    : integer  := 32;
      STATUS_AF_LVL_G   : integer  := 30;
      GHDL_SIM_G        : boolean  := false;
      SYNTHESIZE_G      : boolean  := false);
   port(
      -- General Interface
      sparseClk : in  sl;
      pgpClk    : in  sl;
      rst       : in  sl := not(RST_POLARITY_G);
      enable    : in  sl;
      -- Sparse Logic Interface
      din       : in  slv(SPARSE_DWIDTH_C-1 downto 0);
      wrEn      : in  sl;
      tok       : in  sl;
      tokFb     : in  sl;
      ackN      : in  sl;
      pause     : out sl;
      -- Arbiter Interface
      statusRd  : in  sl;
      dataRd    : in  sl;
      statusBus : out Pix2PgpStatusBusType;
      dataBus   : out Pix2PgpDataBusType);
end Pix2PgpColumnManager;

architecture rtl of Pix2PgpColumnManager is

   signal statusFifoDout     : slv(STATUSFIFO_DWIDTH_C-1 downto 0) := (others => '0');
   signal dataFifoEmpty      : sl := '0';
   signal statusFifoEmpty    : sl := '0';
   signal dataFifoEmptyDly   : sl := '0';
   signal statusFifoEmptyDly : sl := '0';
   signal statusFifoFull     : sl := '0';
   signal dataFifoFull       : sl := '0';

   signal statusWrEn         : sl := '0';
   signal statusDin          : slv(STATUSFIFO_DWIDTH_C-1 downto 0) := (others => '0');
   signal dataWrEn           : sl := '0';
   signal dataDin            : slv(SPARSE_DWIDTH_C-1 downto 0) := (others => '0');
   signal aFullData          : sl := '0';

   type StateType is (
      IDLE_S,
      MON_TOKFB_S,
      CHK_WRCNT_S,
      WREN_STATUS_S,
      PAUSE_S);

   type RegType is record
      -- i/o
      tok           : sl;
      tokFb         : sl;
      ackN          : sl;
      statusRd      : sl;
      dataRd        : sl;
      pause         : sl;
      din           : slv(SPARSE_DWIDTH_C-1 downto 0);
      statusBus     : Pix2PgpStatusBusType;
      dataBus       : Pix2PgpDataBusType;
      -- internal
      overOcc       : sl;
      statusWr      : sl;
      dataWr        : sl;
      aFullData     : sl;
      statusFifoDin : slv(STATUSFIFO_DWIDTH_C-1 downto 0);
      ackCnt        : slv(DATALEN_WIDTH_C-1 downto 0);
      wrEnCnt       : slv(DATALEN_WIDTH_C-1 downto 0);
      trgCnt        : slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0);
      state         : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- i/o
      tok           => '0',
      tokFb         => '0',
      ackN          => '0',
      statusRd      => '0',
      dataRd        => '0',
      pause         => '0',
      din           => (others => '0'),
      statusBus     => DEFAULT_PIX2PGP_STATUSBUS_C,
      dataBus       => DEFAULT_PIX2PGP_DATABUS_C,
      -- internal
      overOcc       => '0',
      statusWr      => '0',
      dataWr        => '0',
      aFullData     => '0',
      statusFifoDin => (others => '0'),
      ackCnt        => (others => '0'),
      wrEnCnt       => (others => '0'),
      trgCnt        => (others => '1'),
      state         => IDLE_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Column Manager FSM
   ------------------------------------------------
   comb : process (r, rst, tok, tokFb, ackN, wrEn, din, statusRd,
                   dataRd, dataFifoEmptyDly, statusFifoEmptyDly, aFullData) is
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Register inputs
      v.tok       := tok;
      v.tokFb     := tokFb;
      v.ackN      := ackN;
      v.dataWr    := wrEn;
      v.din       := din;
      v.statusRd  := statusRd;
      v.dataRd    := dataRd;
      v.aFullData := aFullData;

      -- Strobes
      v.statusWr := '0';

      -- over-occupancy detection (received a token while busy)
      if (r.state /= IDLE_S and v.tok = '0' and r.tok = '1') then
         v.overOcc := '1';
      end if;

      -- ackN counter management (falling-edge detection)
      if (r.state /= IDLE_S and v.ackN = '0' and r.ackN = '1') then
         v.ackCnt := r.ackCnt + 1;
      end if;

      -- wrEn counter management
      if (r.state /= IDLE_S and r.dataWr = '1') then
         v.wrEnCnt := r.wrEnCnt + 1;
      end if;

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- wait for token; also reset the counters and flags
         when IDLE_S =>
            v.overOcc := '0';
            v.pause   := '0';
            v.wrEnCnt := toSlv(0, DATALEN_WIDTH_C);
            v.ackCnt  := toSlv(0, DATALEN_WIDTH_C);

            -- falling-edge detection
            if (v.tok = '0' and r.tok = '1') then
               v.trgCnt := r.trgCnt + 1;
               v.state  := MON_TOKFB_S;
            end if;

         ----------------------------------------------------------------------
         -- wait for token-feedback
         when MON_TOKFB_S =>
            v.pause := '0';

            -- almost-full always takes precedence
            if (r.aFullData = '1') then
               v.pause := '1';
               v.state := WREN_STATUS_S;
            -- rising-edge detection
            elsif (v.tokFb = '1' and r.tokFb = '0') then
               v.state := CHK_WRCNT_S;
            end if;

         ----------------------------------------------------------------------
         -- check that all data have been written
         when CHK_WRCNT_S =>

            -- done; time to write into the status FIFO and go back to idle
            if (r.wrEnCnt >= r.ackCnt) then
               v.state := WREN_STATUS_S;
            end if;

         ----------------------------------------------------------------------
         -- write into the status FIFO
         when WREN_STATUS_S =>

            if r.wrEnCnt(0) = '1' then
               -- wrote odd number of hits? write a dummy word;
               -- hold for one clock cycle;
               -- wrEn will switch to input port by default on next cycle
               v.dataWr := '1';
            end if;

            v.statusFifoDin(STATUSFIFO_OVEROCC_POS_C) := r.overOcc;
            v.statusFifoDin(STATUSFIFO_PAUSE_POS_C)   := r.pause;
            v.statusFifoDin(STATUSFIFO_TRG_POS_C)     := r.trgCnt;
            v.statusFifoDin(STATUSFIFO_DATALEN_POS_C) := r.wrEnCnt;
            v.statusWr := '1';
            v.state    := IDLE_S;

            if (r.pause = '1') then
               v.state := PAUSE_S;
            end if;

         ----------------------------------------------------------------------
         -- pause case
         when PAUSE_S =>
            v.wrEnCnt := toSlv(0, DATALEN_WIDTH_C);
            v.ackCnt  := toSlv(0, DATALEN_WIDTH_C);

            -- if both FIFOs are empty, resume with the event
            if (statusFifoEmptyDly = '1' and dataFifoEmptyDly = '1') then
               v.state := MON_TOKFB_S;
            end if;

      end case;
      -------------------------------------------------------------------------

      -- Outputs
      pause <= v.pause;

      -- Reset
      if (RST_ASYNC_G = false and rst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (sparseClk, rst, enable) is
   begin
      if ((RST_ASYNC_G and rst = RST_POLARITY_G)
      or  enable = '0') then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(sparseClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

   ------------------------------------------------
   -- Status FIFO
   ------------------------------------------------
   -- pipeline the status FIFO i/o signals to give some freedom in placement
   U_PipelineStatusWrEn : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => STATUSFIFO_PIPE_G)
      port map (
         clk     => sparseClk,
         din(0)  => r.statusWr,
         dout(0) => statusWrEn);

   U_PipelineStatusDin : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => STATUSFIFO_DWIDTH_C,
         DELAY_G        => STATUSFIFO_PIPE_G)
      port map (
         clk  => sparseClk,
         din  => r.statusFifoDin,
         dout => statusDin);

   U_PipelineStatusEmpty : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => STATUSFIFO_PIPE_G)
      port map (
         clk     => sparseClk,
         din(0)  => statusFifoEmpty,
         dout(0) => statusFifoEmptyDly);

   U_StatusFifo : entity pix2pgp.Pix2PgpFifoWrapper
      generic map (
         TPD_G           => TPD_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         GEN_SYNC_FIFO_G => true,
         FWFT_EN_G       => true,
         WR_DATA_WIDTH_G => STATUSFIFO_DWIDTH_C,
         RD_DATA_WIDTH_G => STATUSFIFO_DWIDTH_C,
         DWARE_DEPTH_G   => STATUS_DEPTH_G,
         DWARE_AF_LVL_G  => STATUS_AF_LVL_G,
         ADDR_WIDTH_G    => 4,
         GHDL_SIM_G      => GHDL_SIM_G,
         SYNTHESIZE_G    => SYNTHESIZE_G)
      port map (
         -- Resets
         rst     => rst,
         enable  => enable,
         -- Write Interface
         wrClk   => sparseClk,
         wrEn    => statusWrEn,
         din     => statusDin,
         fullWr  => open,
         emptyWr => statusFifoEmpty,
         -- Read Interface
         rdClk   => pgpClk,
         rdEn    => statusRd,
         emptyRd => statusBus.columnEmpty,
         fullRd  => statusFifoFull,
         dout    => statusFifoDout);

   ------------------------------------------------
   -- Data FIFO
   ------------------------------------------------
   -- pipeline the data FIFO input signals to give some freedom in placement
   U_PipelineDataWrEn : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => DATAFIFO_PIPE_G)
      port map (
         clk     => sparseClk,
         din(0)  => r.dataWr,
         dout(0) => dataWrEn);

   U_PipelineDataDin : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => SPARSE_DWIDTH_C,
         DELAY_G        => DATAFIFO_PIPE_G)
      port map (
         clk  => sparseClk,
         din  => r.din,
         dout => dataDin);

   U_PipelineDataEmpty : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => STATUSFIFO_PIPE_G)
      port map (
         clk     => sparseClk,
         din(0)  => dataFifoEmpty,
         dout(0) => dataFifoEmptyDly);

   U_DataFifo : entity pix2pgp.Pix2PgpFifoWrapper
      generic map (
         TPD_G           => TPD_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         GEN_SYNC_FIFO_G => true,
         FWFT_EN_G       => true,
         WR_DATA_WIDTH_G => SPARSE_DWIDTH_C,
         RD_DATA_WIDTH_G => DATABUS_DWIDTH_C,
         DWARE_DEPTH_G   => DATA_DEPTH_G,
         DWARE_AF_LVL_G  => DATA_AF_LVL_G,
         ADDR_WIDTH_G    => 4,
         GHDL_SIM_G      => GHDL_SIM_G,
         SYNTHESIZE_G    => SYNTHESIZE_G)
      port map (
         -- Resets
         rst     => rst,
         enable  => enable,
         -- Write Interface
         wrClk   => sparseClk,
         wrEn    => dataWrEn,
         din     => dataDin,
         fullWr  => open,
         aFullWr => aFullData,
         emptyWr => dataFifoEmpty,
         -- Read Interface
         rdClk   => pgpClk,
         rdEn    => dataRd,
         emptyRd => open,
         fullRd  => dataFifoFull,
         dout    => dataBus.data);

   -- status bus assignments
   statusBus.overOcc    <= statusFifoDout(STATUSFIFO_OVEROCC_POS_C);
   statusBus.pause      <= statusFifoDout(STATUSFIFO_PAUSE_POS_C);
   statusBus.trgNum     <= statusFifoDout(STATUSFIFO_TRG_POS_C);
   statusBus.dataLen    <= statusFifoDout(STATUSFIFO_DATALEN_POS_C);
   statusBus.columnFull <= statusFifoFull or dataFifoFull;

end rtl;
