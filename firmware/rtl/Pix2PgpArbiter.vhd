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
      FIFO_RD_DELAY_G : positive := 1;
      DOUT_PIPE_G     : positive := 1;
      DATAFIFO_FWFT_G : boolean  := true);
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
      arbReady        : in  sl := '1';
      arbValid        : out sl;
      arbDout         : out slv(DATABUS_DWIDTH_C-1 downto 0));
end Pix2PgpArbiter;

architecture rtl of Pix2PgpArbiter is

   function toInt (inVar : sl) return integer is
   begin
      if (inVar = '1') then
         return 1;
      else
         return 0;
      end if;
   end function toInt;

   constant DATARD_CNT_INIT_C : integer := toInt(toSl(DATAFIFO_FWFT_G));

   signal fifoFull     : sl := '0';
   signal arbValidComb : sl := '0';
   signal arbDoutComb  : slv(DATABUS_DWIDTH_C-1 downto 0) := (others => '0');

   type StateType is (
      IDLE_S,
      CHECK_BITMASK_S,
      PARSE_DATA_S,
      DONE_S);

   type RegType is record
      -- outputs
      dataRd       : sl;
      colSel       : slv(BITMAX_COL_MANAGERS_C downto 0);
      arbBusy      : sl;
      arbValid     : sl;
      arbDout      : slv(DATABUS_DWIDTH_C-1 downto 0);
      -- internal
      eventEmpty   : sl;
      headerOnly   : sl;
      dataHeader   : slv(HEADER_DWITDH_C-1 downto 0);
      dataRdCnt    : slv(DATALEN_WIDTH_C-1 downto 0);
      dataRdCycles : slv(DATALEN_WIDTH_C-1 downto 0);
      state        : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- outputs
      dataRd       => '0',
      colSel       => (others => '0'),
      arbBusy      => '0',
      arbValid     => '0',
      arbDout      => (others => '0'),
      -- internal
      eventEmpty   => '0',
      headerOnly   => '0',
      dataHeader   => (others => '0'),
      dataRdCnt    => toSlv(DATARD_CNT_INIT_C, DATALEN_WIDTH_C),
      dataRdCycles => (others => '0'),
      state        => IDLE_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Arbiter FSM
   ------------------------------------------------
   comb : process (r, rst, dataLenSel, dataBusSel, arbStart, statusFifoError,
                   dataFifoError, overOccError, alignError, colBitmask, trgNum,
                   arbReady) is

      variable v : RegType;

   begin

      -- Latch the current value
      v := r;

      v.eventEmpty := not(uOr(colBitmask));

      -- flow control check
      v.dataRd := '0';
      if (arbReady = '1') then
         v.arbValid := '0';
      end if;


      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- supervisor signals a start of sequence
         -- raise the busy flag and forward the header as-is
         when IDLE_S =>
            v.arbBusy  := '0';
            v.arbValid := '0';

            if arbStart = '1' and v.arbValid = '0' then
               v.arbBusy  := '1';
               v.arbValid := '1';
               v.arbDout  := r.dataHeader;

               if statusFifoError = '1' or
                  dataFifoError   = '1' or
                  alignError      = '1' or
                  v.eventEmpty    = '1' then
                  v.state := DONE_S;
               else
                  v.state := CHECK_BITMASK_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- check the bitmask value of the selected column
         -- if non-zero, write the length and start reading immediately
         when CHECK_BITMASK_S =>

            if colBitmask(conv_integer(unsigned(r.colSel))) = '0' then
               v.colSel := r.colSel + 1;
               if (conv_integer(unsigned(r.colSel)) = NUM_OF_COL_MANAGERS_C-1) then
                  v.state := DONE_S;
               end if;

            else
               if (v.arbValid = '0') then
                  v.dataRdCnt := toSlv(DATARD_CNT_INIT_C, DATALEN_WIDTH_C);
                  v.arbValid  := '1';

                  -- TX the dataLength and start reading the data fifo
                  v.arbDout(DATABUS_DWIDTH_C-1 downto 10) := (others => '0');
                  v.arbDout(9 downto 0)                   := dataLenSel;

                  -- divide-by-2 (dumb, but asic synth tool will like it)
                  v.dataRdCycles(DATALEN_WIDTH_C-1)          := '0';
                  v.dataRdCycles(DATALEN_WIDTH_C-2 downto 0) := dataLenSel(DATALEN_WIDTH_C-1 downto 1);

                  -- probably smaller footprint than '<'
                  -- override the previous assertion to cover the one-hit corner case
                  if dataLenSel = conv_std_logic_vector(1, dataLenSel'length) then
                     v.dataRdCycles := toSlv(1, DATALEN_WIDTH_C);
                  end if;

                  v.state := PARSE_DATA_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- parse the data from the selected data bus
         when PARSE_DATA_S =>
            v.arbDout := dataBusSel.data;

            if v.arbValid = '0' then
               if r.dataRdCnt /= r.dataRdCycles + FIFO_RD_DELAY_G then
                  v.arbValid  := '1';
                  v.dataRd    := '1';
                  v.dataRdCnt := r.dataRdCnt + 1;
               else
                  -- Done with column
                  v.colSel := r.colSel + 1;
                  v.state  := CHECK_BITMASK_S;
                  -- Check if last column
                  if (conv_integer(unsigned(r.colSel)) = NUM_OF_COL_MANAGERS_C-1) then
                     v.state := DONE_S;
                  end if;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- last state
         when DONE_S =>
            v.arbBusy := '0';
            v.colSel  := (others => '0');
            if arbStart = '0' then
               v.state := IDLE_S;
            end if;

      end case;
      -----------------------------------------------------------------------

      -- header mapping
      v.dataHeader(OVEROCC_FLAG_POS_C)     := overOccError;
      v.dataHeader(DATA_FULL_FLAG_POS_C)   := dataFifoError;
      v.dataHeader(STATUS_FULL_FLAG_POS_C) := statusFifoError;
      v.dataHeader(TRG_ALIGN_ERROR_POS_C)  := alignError;
      v.dataHeader(TIMEOUT_HEADER_POS_C)   := '0'; -- assigned later on
      v.dataHeader(FLAGS_RESERVED_POS_C)   := (others => '0');
      v.dataHeader(COL_BITMASK_POS_C)      := colBitmask;
      v.dataHeader(TRG_CNT_POS_C)          := trgNum;

      -- Outputs
      arbBusy      <= v.arbBusy;
      dataRd       <= v.dataRd;
      colSel       <= v.colSel;
      arbValidComb <= v.arbValid;
      arbDoutComb  <= v.arbDout;

      -- Reset
      if (RST_ASYNC_G = false and rst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (pgpClk, rst) is
   begin
      if (RST_ASYNC_G and rst = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(pgpClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

   -- pipeline the data output to give some freedom in placement
   U_PipelineValid : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         DELAY_G        => DOUT_PIPE_G)
      port map (
         clk     => pgpClk,
         din(0)  => arbValidComb,
         dout(0) => arbValid);

   U_PipelineDout : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => DATABUS_DWIDTH_C,
         DELAY_G        => DOUT_PIPE_G)
      port map (
         clk  => pgpClk,
         din  => arbDoutComb,
         dout => arbDout);

end rtl;
