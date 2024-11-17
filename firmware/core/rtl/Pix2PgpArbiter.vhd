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

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpArbiter is
   generic(
      TPD_G           : time     := 1 ns;
      RST_ASYNC_G     : boolean  := false;
      RST_POLARITY_G  : sl       := '1';
      DOUT_PIPE_G     : positive := 1;
      DATAFIFO_FWFT_G : boolean  := true);
   port(
      -- General Interface
      pgpClk        : in  sl;
      pgpRst        : in  sl := not(RST_POLARITY_G);
      -- Column Manager Interface
      dataLenSel    : in  slv(DATALEN_WIDTH_C-1 downto 0);
      dataBusSel    : in  Pix2PgpDataBusType;
      dataRd        : out sl;
      colSel        : out slv(BITMAX_COL_MANAGERS_C downto 0);
      -- Column Supervisor Interface
      arbStart      : in  sl;
      colFifoError  : in  sl;
      overOccError  : in  sl;
      colPauseError : in  sl;
      colPause      : in  sl;
      colEmpty      : in  sl;
      colBitmask    : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNum        : in  slv(TRG_WIDTH_C-1 downto 0);
      arbBusy       : out sl;
      -- Pgp4TxLite Interface
      txReady       : in   sl;
      txValid       : out  sl;
      txData        : out  slv(PGP_DWIDTH_C-1 downto 0);
      txSof         : out  sl;
      txEof         : out  sl);
      ---- Pgp Adapter Interface
      --pgpReady      : in  sl := '1';
      --pgpValid      : out sl;
      --pgpData       : out slv(PGP_DWIDTH_C-1 downto 0));
end Pix2PgpArbiter;

architecture rtl of Pix2PgpArbiter is

   -- stolen from numberic_std
   function rightShift (inSlv: slv; count: natural) return slv is
      constant inSlvLen: integer := inSlv'LENGTH-1;
      alias xarg: slv(inSlvLen downto 0) is inSlv;
      variable result: slv(inSlvLen downto 0) := (others => '0');
   begin
      if count <= inSlvLen then
         result(inSlvLen-count downto 0) := xarg(inSlvLen downto count);
      end if;
      return result;
   end rightShift;

   -- col-select done
   function colSelDone (inColSel: slv; inReverseRead: sl) return boolean is
      variable result: boolean := false;
   begin
      if inReverseRead = '1' and allBits(inColSel, '0') then
         result := true;
      elsif inReverseRead = '0' and conv_integer(unsigned(inColSel)) = NUM_OF_COL_MANAGERS_C-1 then
         result := true;
      end if;
      return result;
   end colSelDone;

   -- col-select reset (set to max col value or zero)
   function colSelReset (inColSelLen: integer; inReverseRead: sl) return slv is
      variable result: slv(inColSelLen-1 downto 0) := (others => '0');
   begin
      if inReverseRead = '1' then
         result := conv_std_logic_vector(NUM_OF_COL_MANAGERS_C-1, result'length);
      else
         result := (others => '0');
      end if;
      return result;
   end colSelReset;

   -- col-select switch (incr or decr)
   function colSelSwitch (inColSel: slv; inReverseRead: sl) return slv is
      constant inColSelLen: integer := inColSel'LENGTH-1;
      variable result: slv(inColSelLen downto 0) := (others => '0');
   begin
      if inReverseRead = '1' then
         result := inColSel - 1;
      else
         result := inColSel + 1;
      end if;
      return result;
   end colSelSwitch;

   signal gboxReady   : sl := '0';
   signal gboxValid   : sl := '0';
   signal gboxDin     : slv(DATABUS_DWIDTH_C-1 downto 0) := (others => '0');

   signal gboxTxValid : sl := '0';

   type StateType is (
      IDLE_S,
      CHECK_BITMASK_S,
      PARSE_DATA_S,
      TX_DUMMY_S,
      DONE_S);

   type RegType is record
      -- inputs
      txReady      : sl;
      gboxReady    : sl;
      colPause     : sl;
      txValid      : sl;
      colBitmask   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNum       : slv(TRG_WIDTH_C-1 downto 0);
      -- outputs
      dataRd       : sl;
      colSel       : slv(BITMAX_COL_MANAGERS_C downto 0);
      arbBusy      : sl;
      gboxValid    : sl;
      gboxDin      : slv(DATABUS_DWIDTH_C-1 downto 0);
      txSof        : sl;
      txEof        : sl;
      -- internal
      eventEmpty   : sl;
      headerOnly   : sl;
      dummyHeader  : sl;
      reverseRead  : sl;
      wordCnt      : slv(2 downto 0);
      waitCnt      : slv(1 downto 0);
      dataHeader   : slv(HEADER_DWITDH_C-1 downto 0);
      dataRdCnt    : slv(DATALEN_WIDTH_C-1 downto 0);
      dataRdCycles : slv(DATALEN_WIDTH_C-1 downto 0);
      state        : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- inputs
      gboxReady     => '0',
      txReady       => '0',
      colPause      => '0',
      txValid       => '0',
      colBitmask    => (others => '0'),
      trgNum        => (others => '0'),
      -- outputs
      dataRd        => '0',
      colSel        => (others => '0'),
      arbBusy       => '0',
      gboxValid     => '0',
      gboxDin       => (others => '0'),
      txSof         => '1',
      txEof         => '0',
      -- internal
      eventEmpty    => '0',
      headerOnly    => '0',
      dummyHeader   => '0',
      reverseRead   => '0',
      wordCnt       => (others => '0'),
      waitCnt       => (others => '0'),
      dataHeader    => (others => '0'),
      dataRdCnt     => toSlv(0, DATALEN_WIDTH_C),
      dataRdCycles  => (others => '0'),
      state         => IDLE_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Arbiter FSM
   ------------------------------------------------
   comb : process (r, pgpRst, dataLenSel, dataBusSel, arbStart, colFifoError,
                   overOccError, colBitmask, trgNum, colPause, colPauseError,
                   txReady, gboxReady, colEmpty, gboxTxValid) is

      variable v : RegType;

   begin

      -- Latch the current value
      v := r;

      -- inputs
      v.eventEmpty := not(uOr(colBitmask));
      v.gboxReady  := gboxReady;
      v.txReady    := txReady;
      v.txValid    := gboxTxValid;

      -- defaults
      v.dataRd := '0';

      -- flow control check
      if gboxReady = '1' then
         v.gboxValid := '0';
      end if;

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- supervisor signals a start of sequence
         -- raise the busy flag and forward the header as-is
         when IDLE_S =>
            v.txSof   := '1';
            v.txEof   := '0';
            v.arbBusy := '0';
            v.colSel  := colSelReset(v.colSel'length, r.reverseRead);

            if arbStart = '1' and v.gboxValid = '0' then
               v.gboxDin   := v.dataHeader;
               v.arbBusy   := '1';
               v.gboxValid := '1';
               v.state     := CHECK_BITMASK_S;

               -- if empty, go-to DONE state
               if v.eventEmpty = '1' then
                  v.state := DONE_S;
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
                  v.state       := DONE_S;
               end if;

            else
               if v.gboxValid = '0' then
                  v.dataRdCnt := toSlv(0, DATALEN_WIDTH_C);

                  -- TX the dataLength and start reading the data fifo
                  v.gboxDin(DATABUS_DWIDTH_C-1 downto DATALEN_WIDTH_C) := (others => '0');
                  v.gboxDin(DATALEN_WIDTH_C-1  downto 0)               := dataLenSel;
                  v.gboxValid := '1';

                  -- have to divide the dataLen/hitLen by 2 (one FIFO word yields two hits)
                  -- if odd, add 1 for a 'true' div-by-2
                  if dataLenSel(0) = '1' then
                     v.dataRdCycles := rightShift(dataLenSel, 1) + 1;
                  else
                     v.dataRdCycles := rightShift(dataLenSel, 1);
                  end if;

                  v.state := PARSE_DATA_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- parse the data from the selected data bus
         when PARSE_DATA_S =>
            if v.gboxValid = '0' then
               v.gboxDin   := dataBusSel.data;
               v.dataRdCnt := r.dataRdCnt + 1;
               v.dataRd    := '1';
               v.gboxValid := '1';
            end if;

            if r.dataRdCnt = r.dataRdCycles then
               -- Done with column
               v.gboxDin   := (others => '0');
               v.dataRd    := '0';
               v.gboxValid := '0';
               v.colSel    := colSelSwitch(r.colSel, r.reverseRead);
               v.state     := CHECK_BITMASK_S;
               -- Check if last column
               if colSelDone(r.colSel, r.reverseRead) then
                  v.reverseRead := not(r.reverseRead);
                  v.state       := DONE_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- check if gearbox has stale data
         when DONE_S =>
            v.dummyHeader := '1';
            v.gboxValid   := '0';
            v.gboxDin     := (others => '0');

            if r.dummyHeader = '1' then
               --if allBits(r.wordCnt, '1') then
               --   -- corner-case where one more word needs to be TX'd
               --   if v.gboxValid = '0' then
               --      v.gboxDin   := v.dataHeader;
               --      v.gboxValid := '1';
               --   end if;
               if not(allBits(r.wordCnt, '0')) then
                  -- regular case where some words need to flushed out
                  v.state := TX_DUMMY_S;
               else
                  v.txEof := '1'; -- raise the EoF flag
                  -- wait for the gearbox to stop TXing
                  if v.txValid = '0' and v.txReady = '0' then
                     v.dummyHeader := '0';
                     v.state       := IDLE_S;
                  end if;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- stuffs the gearbox with dummy headers
         -- essentially flushes out the last words written into the gearbox
         when TX_DUMMY_S =>
            if v.gboxValid = '0' then
               v.gboxDin   := v.dataHeader;
               v.gboxValid := '1';
            end if;

            if allBits(r.wordCnt, '1') then
               v.state := DONE_S;
            end if;
      end case;
      -----------------------------------------------------------------------

      -----------------------------------------------------------------------
      -- SOF delimiter handling
      if v.txSof = '1' then
         if v.txReady = '1' and v.txValid = '1' then
            v.txSof := '0'; -- time to drop the flag
         end if;
      end if;
      -----------------------------------------------------------------------

      -- keeps track of the words written into the gearbox;
      -- important for the final state after done TXing all data
      if v.gboxValid = '1' and v.gboxReady = '1' then
         v.wordCnt := r.wordCnt + 1;
      end if;

      -- header mapping and overriding
      -- override header elements if in dummy-header-TX mode
      --
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
         v.colBitmask(col) := colBitmask(col) and not(v.dummyHeader);
      end loop;
      --
      for trgBit in 0 to TRG_WIDTH_C-1 loop
         v.trgNum(trgBit) := trgNum(trgBit) and not(v.dummyHeader);
      end loop;
      --
      v.dataHeader(OVEROCC_FLAG_POS_C)     := overOccError  and not(v.dummyHeader);
      v.dataHeader(PAUSE_FLAG_POS_C)       := colPause      and not(v.dummyHeader);
      v.dataHeader(COLUMN_FULL_FLAG_POS_C) := colFifoError  and not(v.dummyHeader);
      v.dataHeader(PAUSE_ERROR_FLAG_POS_C) := colPauseError and not(v.dummyHeader);
      v.dataHeader(DUMMY_HEADER_POS_C)     := v.dummyHeader;
      v.dataHeader(REVERSE_READ_POS_C)     := v.reverseRead and not(v.dummyHeader);
      v.dataHeader(FLAGS_RESERVED_POS_C)   := (others => '0');
      v.dataHeader(COL_BITMASK_POS_C)      := v.colBitmask;
      v.dataHeader(TRG_CNT_POS_C)          := v.trgNum;

      -- Outputs
      arbBusy   <= v.arbBusy;
      dataRd    <= v.dataRd;
      colSel    <= v.colSel;
      gboxValid <= v.gboxValid;
      gboxDin   <= v.gboxDin;
      txValid   <= v.txValid;
      txSof     <= v.txSof;
      txEof     <= v.txEof;

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
   -- Gearbox (40:64)
   -----------------------------------------
   U_Gearbox : entity surf.Gearbox
      generic map (
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         RST_POLARITY_G => RST_POLARITY_G,
         SLAVE_WIDTH_G  => DATABUS_DWIDTH_C,
         MASTER_WIDTH_G => PGP_DWIDTH_C)
      port map (
         -- Clock and Reset
         clk            => pgpClk,
         rst            => pgpRst,
         -- Slave Interface
         slaveValid     => gboxValid,
         slaveData      => gboxDin,
         slaveReady     => gboxReady,
         slaveBitOrder  => '0',
         -- Master Interface
         masterBitOrder => '0',
         masterReady    => txReady,
         masterValid    => gboxTxValid,
         masterData     => txData);

end rtl;
