-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: PIX2PGP Arbiter
--              Column Supervisor signals Arbiter that FIFO statuses are stable
--              Then Arbiter Parses in the data accordingly
--
-- Important!   Note the wordCnt functionality and its relationship with
--              the adapter logic
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
      pgpClk       : in  sl;
      pgpRst       : in  sl := not(RST_POLARITY_G);
      -- Column Manager Interface
      dataLenSel   : in  slv(DATALEN_WIDTH_C-1 downto 0);
      dataBusSel   : in  Pix2PgpDataBusType;
      dataRd       : out sl;
      colSel       : out slv(BITMAX_COL_MANAGERS_C downto 0);
      -- Column Supervisor Interface
      arbStart     : in  sl;
      colFifoError : in  sl;
      overOccError : in  sl;
      alignError   : in  sl;
      colPause     : in  sl;
      colEmpty     : in  sl;
      colBitmask   : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNum       : in  slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0);
      arbBusy      : out sl;
      -- Pgp Adapter Interface
      pgpReady     : in  sl := '1';
      pgpValid     : out sl;
      pgpData      : out slv(PGP_DWIDTH_C-1 downto 0));
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

   signal arbReady : sl := '0';
   signal arbValid : sl := '0';
   signal arbDout  : slv(DATABUS_DWIDTH_C-1 downto 0) := (others => '0');

   type StateType is (
      IDLE_S,
      CHECK_BITMASK_S,
      PARSE_DATA_S,
      TX_DUMMY_S);

   type RegType is record
      -- inputs
      pgpReady     : sl;
      arbReady     : sl;
      colFifoError : sl;
      overOccError : sl;
      alignError   : sl;
      colPause     : sl;
      colBitmask   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNum       : slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0);
      -- outputs
      dataRd       : sl;
      colSel       : slv(BITMAX_COL_MANAGERS_C downto 0);
      arbBusy      : sl;
      arbValid     : sl;
      arbDout      : slv(DATABUS_DWIDTH_C-1 downto 0);
      -- internal
      eventEmpty   : sl;
      headerOnly   : sl;
      dummyHeader  : sl;
      wordCnt      : slv(2 downto 0);
      waitCnt      : slv(1 downto 0);
      dataHeader   : slv(HEADER_DWITDH_C-1 downto 0);
      dataRdCnt    : slv(DATALEN_WIDTH_C-1 downto 0);
      dataRdCycles : slv(DATALEN_WIDTH_C-1 downto 0);
      state        : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- inputs
      pgpReady     => '1',
      arbReady     => '1',
      colFifoError => '0',
      overOccError => '0',
      alignError   => '0',
      colPause     => '0',
      colBitmask   => (others => '0'),
      trgNum       => (others => '0'),
      -- outputs
      dataRd       => '0',
      colSel       => (others => '0'),
      arbBusy      => '0',
      arbValid     => '0',
      arbDout      => (others => '0'),
      -- internal
      eventEmpty   => '0',
      headerOnly   => '0',
      dummyHeader  => '0',
      wordCnt      => (others => '0'),
      waitCnt      => (others => '0'),
      dataHeader   => (others => '0'),
      dataRdCnt    => toSlv(0, DATALEN_WIDTH_C),
      dataRdCycles => (others => '0'),
      state        => IDLE_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Arbiter FSM
   ------------------------------------------------
   comb : process (r, pgpRst, dataLenSel, dataBusSel, arbStart, colFifoError,
                   overOccError, alignError, colBitmask, trgNum, colPause,
                   pgpReady, arbReady, colEmpty) is

      variable v : RegType;

   begin

      -- Latch the current value
      v := r;

      v.eventEmpty := not(uOr(colBitmask));
      v.pgpReady   := pgpReady;

      -- flow control check
      v.dataRd := '0';
      if (arbReady = '1') then
         v.arbValid := '0';
      end if;

      -- keeps track of the words written into the gearbox;
      -- important for the final state after done TXing the data
      if (r.arbValid = '1' and r.arbReady = '1') then
         v.wordCnt := r.wordCnt + 1;
      end if;

      -- override header elements if in dummy-header-TX mode
      --
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
         v.colBitmask(col) := colBitmask(col) and not(r.dummyHeader);
      end loop;
      --
      for trgBit in 0 to STATUSFIFO_TRG_WIDTH_C-1 loop
         v.trgNum(trgBit)  := trgNum(trgBit)  and not(r.dummyHeader);
      end loop;
      --
      v.overOccError := overOccError and not(r.dummyHeader);
      v.colPause     := colPause     and not(r.dummyHeader);
      v.colFifoError := colFifoError and not(r.dummyHeader);
      v.alignError   := alignError   and not(r.dummyHeader);

      -- header is always TX'd default; being overriden otherwise
      v.arbDout := v.dataHeader;

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- supervisor signals a start of sequence
         -- raise the busy flag and forward the header as-is
         when IDLE_S =>
            v.arbBusy     := '0';
            v.arbValid    := '0';
            v.colSel      := (others => '0');

            if arbStart = '1' and r.dummyHeader = '0' and v.arbValid = '0' and pgpReady = '1' then
               v.arbBusy  := '1';
               v.arbValid := '1';
               v.state    := CHECK_BITMASK_S;

               -- if empty, just stay here
               if v.eventEmpty = '1' then
                  v.state := IDLE_S;
               end if;
            end if;

            -- no activity in the columns, plus still data in the gearbox;
            -- start flushing gearbox on next cycle
            if not(allBits(r.wordCnt, '0')) and colEmpty = '1' then
               v.dummyHeader := '1';
            end if;

            if r.dummyHeader = '1' then
               v.arbBusy := '1';
               v.state   := TX_DUMMY_S;
            end if;

         ----------------------------------------------------------------------
         -- check the bitmask value of the selected column
         -- if non-zero, write the length and start reading immediately
         when CHECK_BITMASK_S =>
            if colBitmask(conv_integer(unsigned(r.colSel))) = '0' then
               v.colSel := r.colSel + 1;
               if (conv_integer(unsigned(r.colSel)) = NUM_OF_COL_MANAGERS_C-1) then
                  v.arbBusy := '0';
                  v.state   := IDLE_S;
               end if;

            else
               if (v.arbValid = '0' and pgpReady = '1') then
                  v.dataRdCnt := toSlv(0, DATALEN_WIDTH_C);
                  v.arbValid  := '1';

                  -- TX the dataLength and start reading the data fifo
                  v.arbDout(DATABUS_DWIDTH_C-1 downto 10) := (others => '0');
                  v.arbDout(9 downto 0)                   := dataLenSel;

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
            v.arbDout := dataBusSel.data;

            if v.arbValid = '0' and pgpReady = '1' then
               v.dataRdCnt := r.dataRdCnt + 1;
               v.dataRd    := '1';
               v.arbValid  := '1';

               if r.dataRdCnt = r.dataRdCycles then
                  -- Done with column
                  v.dataRd   := '0';
                  v.arbValid := '0';
                  v.colSel   := r.colSel + 1;
                  v.state    := CHECK_BITMASK_S;
                  -- Check if last column
                  if (conv_integer(unsigned(r.colSel)) = NUM_OF_COL_MANAGERS_C-1) then
                     v.arbBusy := '0';
                     v.state   := IDLE_S;
                  end if;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- stuffs the gearbox with dummy headers
         -- essentially flushes out the last words written into the gearbox
         when TX_DUMMY_S =>
            if (v.arbValid = '0' and pgpReady = '1') then
               v.arbValid := '1';
               -- seize the process one count before overflow -> rolls-over to 0
               --if allBits(r.wordCnt(r.wordCnt'length-1 downto 1), '1') then
               if allBits(r.wordCnt, '1') then
                  v.arbValid    := '0';
                  v.arbBusy     := '0';
                  v.dummyHeader := '0';
                  v.state       := IDLE_S;
               end if;
            end if;

      end case;
      -----------------------------------------------------------------------

      -- header mapping
      v.dataHeader(OVEROCC_FLAG_POS_C)     := v.overOccError;
      v.dataHeader(PAUSE_FLAG_POS_C)       := v.colPause;
      v.dataHeader(COLUMN_FULL_FLAG_POS_C) := v.colFifoError;
      v.dataHeader(TRG_ALIGN_ERROR_POS_C)  := v.alignError;
      v.dataHeader(DUMMY_HEADER_POS_C)     := v.dummyHeader;
      v.dataHeader(FLAGS_RESERVED_POS_C)   := (others => '0');
      v.dataHeader(COL_BITMASK_POS_C)      := v.colBitmask;
      v.dataHeader(TRG_CNT_POS_C)          := v.trgNum;

      -- Outputs
      arbBusy  <= v.arbBusy;
      dataRd   <= v.dataRd;
      colSel   <= v.colSel;
      arbValid <= r.arbValid;
      arbDout  <= r.arbDout;

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
         slaveValid     => arbValid,
         slaveData      => arbDout,
         slaveReady     => arbReady,
         slaveBitOrder  => '0',
         -- Master Interface
         masterBitOrder => '0',
         masterReady    => '1', -- flow is controlled by adapter's FIFO progFull (pgpReady)
         masterValid    => pgpValid,
         masterData     => pgpData);

end rtl;
