-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: PIX2PGP Arbiter
--              Column Supervisor signals Arbiter that FIFO statuses are stable
--              Then Arbiter Parses in the data accordingly
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
      FIFO_RD_DELAY_G : positive := 3;
      STANDALONE_G    : boolean  := false);
   port(
      -- General Interface
      pgpClk          : in  sl;
      rst             : in  sl := not(RST_POLARITY_G);
      -- Column Manager Interface
      dataLenSel      : in  slv(DATALEN_WIDTH_C-1 downto 0);
      dataBusSel      : in  Pix2PgpDataBusType;
      dataRd          : out sl;
      colSel          : out slv(BITMAX_COL_MANAGERS_C downto 0);
      -- Column Supervisor Interface
      arbStart        : in  sl;
      statusFifoError : in  sl;
      dataFifoError   : in  sl;
      overOccError    : in  sl;
      alignError      : in  sl;
      colBitmask      : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNum          : in  slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0);
      arbBusy         : out sl;
      -- Gearbox Interface
      arbValid        : out sl;
      arbDout         : out slv(DATABUS_DWIDTH_C-1 downto 0));
end Pix2PgpArbiter;

architecture rtl of Pix2PgpArbiter is

   constant COLDATAFIFO_IS_FWFT_C : natural := 1; -- set to 1 for true, 0 for false

   signal fifoFull  : sl := '0';

   type StateType is (
      IDLE_S,
      ROUND_ROBIN_S,
      INCR_SEL_S,
      PARSE_DATA_S,
      DONE_S);

   type RegType is record
      -- i/o
      dataLenSel      : slv(DATALEN_WIDTH_C-1 downto 0);
      dataBusSel      : Pix2PgpDataBusType;
      dataRd          : sl;
      colSel          : slv(BITMAX_COL_MANAGERS_C downto 0);
      arbStart        : sl;
      statusFifoError : sl;
      dataFifoError   : sl;
      overOccError    : sl;
      alignError      : sl;
      colBitmask      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNum          : slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0);
      arbBusy         : sl;
      arbValid        : sl;
      arbDout         : slv(DATABUS_DWIDTH_C-1 downto 0);
      -- internal
      eventEmpty      : sl;
      headerOnly      : sl;
      dataHeader      : slv(HEADER_DWITDH_C-1 downto 0);
      dataRdCnt       : slv(DATALEN_WIDTH_C-1 downto 0);
      dataRdCycles    : slv(DATALEN_WIDTH_C-1 downto 0);
      busyCnt         : natural range 0 to 4095;
      state           : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- i/o
      dataLenSel      => (others => '0'),
      dataBusSel      => DEFAULT_PIX2PGP_DATABUS_C,
      dataRd          => '0',
      colSel          => (others => '0'),
      arbStart        => '0',
      statusFifoError => '0',
      dataFifoError   => '0',
      overOccError    => '0',
      alignError      => '0',
      colBitmask      => (others => '0'),
      trgNum          => (others => '0'),
      arbBusy         => '0',
      arbValid        => '0',
      arbDout         => (others => '0'),
      -- internal
      eventEmpty      => '0',
      headerOnly      => '0',
      dataHeader      => (others => '0'),
      dataRdCnt       => toSlv(COLDATAFIFO_IS_FWFT_C, DATALEN_WIDTH_C),
      dataRdCycles    => (others => '0'),
      busyCnt         => 0,
      state           => IDLE_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Arbiter FSM
   ------------------------------------------------
   comb : process (r, rst, dataLenSel, dataBusSel, arbStart, statusFifoError,
                   dataFifoError, overOccError, alignError, colBitmask, trgNum) is

      variable v : RegType;

   begin

      -- Latch the current value
      v := r;

      -- Register inputs
      v.dataLenSel      := dataLenSel;
      v.dataBusSel      := dataBusSel;
      v.arbStart        := arbStart;
      v.statusFifoError := statusFifoError;
      v.dataFifoError   := dataFifoError;
      v.overOccError    := overOccError;
      v.alignError      := alignError;
      v.colBitmask      := colBitmask;
      v.trgNum          := trgNum;

      v.eventEmpty      := not(uOr(r.colBitmask));

      if (r.arbBusy = '1') then
         v.busyCnt := r.busyCnt + 1;
      end if;
      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- supervisor signals a start of sequence
         -- raise the busy flag and forward the header as-is
         when IDLE_S =>
            v.arbBusy  := '0';
            v.arbValid := '0';

            if r.arbStart = '1' then
               v.arbBusy     := '1';
               v.arbValid    := '1';
               v.arbDout     := r.dataHeader;

               if r.statusFifoError = '1' or
                  r.dataFifoError   = '1' or
                  r.alignError      = '1' or
                  r.eventEmpty      = '1' then
                  v.state := DONE_S;
               else
                  v.state := ROUND_ROBIN_S;
               end if;

            end if;

         ----------------------------------------------------------------------
         -- check the data length of the selected column
         when ROUND_ROBIN_S =>
            v.arbValid := '0';

            if allBits((r.dataLenSel), '0') then
               v.state := INCR_SEL_S;
            else
               -- TX the dataLength and start reading the data fifo
               v.arbDout(DATABUS_DWIDTH_C-1 downto 10) := (others => '0');
               v.arbDout(9 downto 0)                   := r.dataLenSel;
               -- divide-by-2 (dumb, but asic synth tool will like it)
               v.dataRdCycles(DATALEN_WIDTH_C-1)          := '0';
               v.dataRdCycles(DATALEN_WIDTH_C-2 downto 0) := r.dataLenSel(DATALEN_WIDTH_C-1 downto 1);
               v.dataRdCnt := toSlv(COLDATAFIFO_IS_FWFT_C, DATALEN_WIDTH_C);
               v.arbValid  := '1';
               v.dataRd    := '1';
               v.state     := PARSE_DATA_S;
            end if;

         ----------------------------------------------------------------------
         -- check the data length of the selected column
         when INCR_SEL_S =>
            v.colSel := r.colSel + 1;
            if (conv_integer(unsigned(r.colSel)) < NUM_OF_COL_MANAGERS_C-1) then
               v.state := ROUND_ROBIN_S;
            else
               v.state := DONE_S;
            end if;

         ----------------------------------------------------------------------
         -- parse the data from the selected data bus
         when PARSE_DATA_S =>
            v.arbValid  := '0';
            v.arbDout   := v.dataBusSel.data;
            v.dataRdCnt := r.dataRdCnt + 1;

            -- dataRd control
            if r.dataRdCnt = r.dataRdCycles - 1 then
               v.dataRd := '0';
            end if;

            -- arbValid control
            if r.dataRdCnt >= FIFO_RD_DELAY_G then
               v.arbValid := '1';
            end if;

            if r.dataRdCnt = r.dataRdCycles + FIFO_RD_DELAY_G then
               v.arbValid := '0';
               v.state    := INCR_SEL_S;
            end if;

         ----------------------------------------------------------------------
         -- last state
         when DONE_S =>
            v.arbBusy := '0';
            if r.arbStart = '0' then
               v.state := IDLE_S;
            end if;

      end case;
      -----------------------------------------------------------------------

      -- header mapping
      v.dataHeader(OVEROCC_FLAG_POS_C)     := r.overOccError;
      v.dataHeader(DATA_FULL_FLAG_POS_C)   := r.dataFifoError;
      v.dataHeader(STATUS_FULL_FLAG_POS_C) := r.statusFifoError;
      v.dataHeader(TRG_ALIGN_ERROR_POS_C)  := r.alignError;
      v.dataHeader(TIMEOUT_HEADER_POS_C)   := '0'; -- assigned later on
      v.dataHeader(FLAGS_RESERVED_POS_C)   := (others => '0');
      v.dataHeader(COL_BITMASK_POS_C)      := r.colBitmask;
      v.dataHeader(TRG_CNT_POS_C)          := r.trgNum;

      -- Outputs
      dataRd   <= r.dataRd;
      colSel   <= r.colSel;
      arbDout  <= r.arbDout;
      arbValid <= r.arbValid;

      -- Reset
      if (RST_ASYNC_G = false and rst = '1') then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (pgpClk, rst) is
   begin
      if (RST_ASYNC_G and rst = '1') then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(pgpClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

end rtl;
