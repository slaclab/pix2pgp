-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: PIX2PGP Arbiter
--              Column Supervisor signals Arbiter that FIFO statuses are stable
--              Then Arbiter parses in the data accordingly
--
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

entity Pix2PgpArbiter is
   generic(
      TPD_G           : time     := 1 ns;
      RST_ASYNC_G     : boolean  := false;
      RST_POLARITY_G  : sl       := '1');
   port(
      -- General Interface
      pgpClk        : in  sl;
      pgpRst        : in  sl := not(RST_POLARITY_G);
      -- Column Manager Interface
      dataLenSel    : in  slv(DATALEN_WIDTH_C-1 downto 0);
      trgCntSel     : in  slv(TRGCNT_WIDTH_C-1 downto 0);
      trgCntGlbl    : in  slv(TRGCNT_WIDTH_C-1 downto 0);
      dataBusSel    : in  Pix2PgpDataBusType;
      dataRd        : out sl;
      colSel        : out slv(BITMAX_COL_MANAGERS_C downto 0);
      -- Column Supervisor Interface
      arbStart      : in  sl;
      colFifoError  : in  sl;
      overOccError  : in  sl;
      colPauseError : in  sl;
      timeoutError  : in  sl;
      colPause      : in  sl;
      colBitmask    : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      arbBusy       : out sl;
      -- Pgp4TxLite Interface
      pgpTxMaster   : out AxiStreamMasterType;
      pgpTxSlave    : in  AxiStreamSlaveType);
end Pix2PgpArbiter;

architecture rtl of Pix2PgpArbiter is

   -- reset via the variables
   signal sAxisMaster : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal sAxisSlave  : AxiStreamSlaveType  := AXI_STREAM_SLAVE_INIT_C;

   -- axi-stream gearbox configuration
   constant SLAVE_AXI_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C         => false,
      TDATA_BYTES_C      => DATABUS_DWIDTH_C/8,
      TDEST_BITS_C       => 4,
      TID_BITS_C         => 0,
      TKEEP_MODE_C       => TKEEP_NORMAL_C,
      TUSER_BITS_C       => 4,
      TUSER_MODE_C       => TUSER_NORMAL_C);

   constant MASTER_AXI_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C         => false,
      TDATA_BYTES_C      => PGP_DWIDTH_C/8,
      TDEST_BITS_C       => 4,
      TID_BITS_C         => 0,
      TKEEP_MODE_C       => TKEEP_NORMAL_C,
      TUSER_BITS_C       => 4,
      TUSER_MODE_C       => TUSER_NORMAL_C);

   type StateType is (
      IDLE_S,
      PARSE_HEADER_S,
      CHECK_BITMASK_S,
      PARSE_DATA_S,
      TX_DUMMY_S);

   type RegType is record
      -- inputs
      colPause     : sl;
      arbStart     : sl;
      colBitmask   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgCntGlbl   : slv(TRGCNT_WIDTH_C-1 downto 0);
      -- outputs
      dataRd       : sl;
      colSel       : slv(BITMAX_COL_MANAGERS_C downto 0);
      arbBusy      : sl;
      -- internal
      eventEmpty   : sl;
      dummyHeader  : sl;
      reverseRead  : sl;
      txData       : slv(DATABUS_DWIDTH_C-1 downto 0);
      wordCnt      : slv(2 downto 0);
      dataHeader   : slv(HEADER_DWITDH_C-1 downto 0);
      dataRdCnt    : slv(DATALEN_WIDTH_C-1 downto 0);
      dataRdCycles : slv(DATALEN_WIDTH_C-1 downto 0);
      state        : StateType;
      sAxisMaster  : AxiStreamMasterType;
      sAxisSlave   : AxiStreamSlaveType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- inputs
      colPause      => '0',
      arbStart      => '0',
      colBitmask    => (others => '0'),
      trgCntGlbl    => (others => '0'),
      -- outputs
      dataRd        => '0',
      colSel        => (others => '0'),
      arbBusy       => '0',
      -- internal
      eventEmpty    => '0',
      dummyHeader   => '0',
      reverseRead   => '0',
      txData        => (others => '0'),
      wordCnt       => (others => '0'),
      dataHeader    => (others => '0'),
      dataRdCnt     => toSlv(0, DATALEN_WIDTH_C),
      dataRdCycles  => (others => '0'),
      state         => IDLE_S,
      sAxisMaster   => AXI_STREAM_MASTER_INIT_C,
      sAxisSlave    => AXI_STREAM_SLAVE_INIT_C);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Arbiter FSM
   ------------------------------------------------
   comb : process (r, pgpRst, dataLenSel, dataBusSel, arbStart, colFifoError,
                   overOccError, colBitmask, colPause, colPauseError, sAxisSlave,
                   trgCntGlbl, trgCntSel, timeoutError) is

      variable v : RegType;

   begin

      -- Latch the current value
      v := r;

      -- inputs
      v.eventEmpty := not(uOr(colBitmask));
      v.sAxisSlave := sAxisSlave;
      v.arbStart   := arbStart;

      -- defaults
      v.dataRd := '0';

      -- flow control check
      if sAxisSlave.tReady = '1' then
         v.sAxisMaster.tValid := '0';
      end if;

      -- default flags
      v.sAxisMaster.tLast  := '0';
      v.sAxisMaster.tUser  := (others => '0');
      v.sAxisMaster.tKeep  := (others => '1');

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- supervisor signals a start of sequence
         -- raise the busy flag and forward the header as-is
         when IDLE_S =>
            v.arbBusy     := '0';
            v.dummyHeader := '0';
            v.colSel      := colSelReset(v.colSel'length, r.reverseRead);

            if r.arbStart = '1' then
               v.arbBusy := '1';
               v.state   := PARSE_HEADER_S;
            end if;

         ----------------------------------------------------------------------
         -- parse the header to the gearbox;
         -- determine what to do next
         when PARSE_HEADER_S =>
            if v.sAxisMaster.tValid = '0' then
               v.sAxisMaster.tUser(1) := '1'; -- SoF
               v.sAxisMaster.tValid   := '1';
               v.txData               := v.dataHeader;

               v.state := CHECK_BITMASK_S;

               -- if empty, go-to DONE state
               if v.eventEmpty = '1' then
                  v.dummyHeader := '1';
                  v.state       := TX_DUMMY_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- check the bitmask value of the selected column
         -- if non-zero, write the length and start reading immediately
         when CHECK_BITMASK_S =>
            if colBitmask(conv_integer(unsigned(r.colSel))) = '0' then

               v.colSel := colSelSwitch(r.colSel, r.reverseRead);

               if colSelDone(r.colSel, r.reverseRead) then
                  v.reverseRead := not(r.reverseRead);
                  v.dummyHeader := '1';
                  v.state       := TX_DUMMY_S;
               end if;

            else
               if v.sAxisMaster.tValid = '0' then
                  --
                  v.txData(DATABUS_DWIDTH_C-1 downto 8) := resize(trgCntSel,  32);
                  v.txData(7 downto 0)                  := resize(dataLenSel, 8);
                  v.sAxisMaster.tValid                  := '1';
                  --

                  v.dataRdCnt := toSlv(0, DATALEN_WIDTH_C);

                  -- have to divide the dataLen/hitLen by 2 (one FIFO word yields two hits)
                  -- if odd, add 1 for a 'true' div-by-2
                  if dataLenSel(0) = '1' then
                     v.dataRdCycles := rightShift(dataLenSel, 1) + 1;
                  else
                     v.dataRdCycles := rightShift(dataLenSel, 1);
                  end if;

                  v.state  := PARSE_DATA_S;
               end if;
            end if;

         ------------------------------------------------------------------------
         -- parse the data from the selected data bus
         when PARSE_DATA_S =>
            if v.sAxisMaster.tValid = '0' and r.dataRdCnt /= r.dataRdCycles then
               --
               v.txData             := dataBusSel.data;
               v.sAxisMaster.tValid := '1';
               --
               v.dataRdCnt := r.dataRdCnt + 1;
               v.dataRd    := '1';
            end if;

            -- Done with column
            if r.dataRdCnt = r.dataRdCycles then
               --
               v.dataRd := '0';
               v.colSel := colSelSwitch(r.colSel, r.reverseRead);
               v.state  := CHECK_BITMASK_S;
               --
               -- Check if last column
               if colSelDone(r.colSel, r.reverseRead) then
                  v.reverseRead := not(r.reverseRead);
                  v.dummyHeader := '1';
                  v.state       := TX_DUMMY_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- stuffs the gearbox with dummy headers
         -- essentially flushes out the last words written into the gearbox
         when TX_DUMMY_S =>
            v.sAxisMaster.tUser(1) := '0';
            if v.sAxisMaster.tValid = '0' then
               v.txData             := v.dataHeader;
               v.sAxisMaster.tValid := '1';

               if allBits(r.wordCnt, '1') then
                  v.sAxisMaster.tLast := '1';
                  v.state             := IDLE_S;
               end if;
            end if;

      end case;
      -----------------------------------------------------------------------

      -- keeps track of the words written into the gearbox;
      -- important for the final state after done TXing all data
      if sAxisSlave.tReady = '1' then
         v.wordCnt := r.wordCnt + 1;
      end if;

      -- header mapping and overriding
      -- override header elements if in dummy-header-TX mode
      --
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
         v.colBitmask(col) := colBitmask(col) and not(v.dummyHeader);
      end loop;
      --
      for i in 0 to TRGCNT_WIDTH_C-1 loop
         v.trgCntGlbl(i) := trgCntGlbl(i) and not(v.dummyHeader);
      end loop;
      --
      --
      v.dataHeader(OVEROCC_FLAG_POS_C)      := overOccError  and not(v.dummyHeader);
      v.dataHeader(PAUSE_FLAG_POS_C)        := colPause      and not(v.dummyHeader);
      v.dataHeader(COLUMN_ERROR_FLAG_POS_C) := colFifoError  and not(v.dummyHeader);
      v.dataHeader(PAUSE_ERROR_FLAG_POS_C)  := colPauseError and not(v.dummyHeader);
      v.dataHeader(TIMEOUT_FLAG_POS_C)      := timeoutError  and not(v.dummyHeader);
      v.dataHeader(DUMMY_HEADER_POS_C)      := v.dummyHeader;
      v.dataHeader(REVERSE_READ_POS_C)      := v.reverseRead and not(v.dummyHeader);
      v.dataHeader(FLAGS_RESERVED_POS_C)    := (others => '0');
      v.dataHeader(COL_BITMASK_POS_C)       := v.colBitmask;
      v.dataHeader(TRG_CNT_POS_C)           := resize(v.trgCntGlbl, 8);

      --
      v.sAxisMaster.tData(DATABUS_DWIDTH_C-1 downto 0) := v.txData;
      --

      -- Outputs
      arbBusy     <= v.arbBusy;
      dataRd      <= v.dataRd;
      colSel      <= v.colSel;
      sAxisMaster <= r.sAxisMaster;

      -- Reset
      if (RST_ASYNC_G = false and pgpRst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (pgpClk, pgpRst) is
   begin
      if (RST_ASYNC_G and pgpRst = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(pgpClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

   -----------------------------------------
   -- Axi-Stream Gearbox (40:64)
   -----------------------------------------
   U_Gearbox : entity surf.AxiStreamGearbox
      generic map(
         -- General Configurations
         TPD_G               => TPD_G,
         RST_POLARITY_G      => RST_POLARITY_G,
         RST_ASYNC_G         => RST_ASYNC_G,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => SLAVE_AXI_CONFIG_C,
         MASTER_AXI_CONFIG_G => MASTER_AXI_CONFIG_C)
      port map(
         -- Clock and reset
         axisClk     => pgpClk,
         axisRst     => pgpRst,
         -- Slave Port
         sAxisMaster => sAxisMaster,
         sSideBand   => (others => '0'),
         sAxisSlave  => sAxisSlave,
         -- Master Port
         mAxisMaster => pgpTxMaster,
         mSideBand   => open,
         mAxisSlave  => pgpTxSlave);

end rtl;
