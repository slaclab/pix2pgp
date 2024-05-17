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
      STANDALONE_G    : boolean := false);
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
      arbiterStart    : in  sl;
      statusFifoError : in  sl;
      dataFifoError   : in  sl;
      overOccError    : in  sl;
      alignError      : in  sl;
      colBitmask      : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNum          : in  slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0);
      arbiterBusy     : out sl;
      -- Gearbox Interface
      arbRdEn         : in  sl;
      arbEmpty        : out sl;
      arbDout         : out slv(ARB_GEARBOX_INPUT_WIDTH_G-1 downto 0));
end Pix2PgpArbiter;

architecture rtl of Pix2PgpArbiter is

   constant STANDALONE_FIFO_WR_DELAY_C : natural := 3;
   --constant VENDOR_FIFO_WR_DELAY_C     : natural := ????;

   signal fifoFull  : sl := '0';
   signal dataRdDly : sl := '0';

   type StateType is (
      IDLE_S,
      TX_HEADER_S,
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
      arbiterStart    : sl;
      statusFifoError : sl;
      dataFifoError   : sl;
      overOccError    : sl;
      alignError      : sl;
      colBitmask      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgNum          : slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0);
      arbiterBusy     : sl;
      -- internal
      eventEmpty      : sl;
      headerOnly      : sl;
      dataHeader      : slv(HEADER_DWITDH_C-1 downto 0);
      headerSel       : sl;
      dataRdCnt       : slv(DATALEN_WIDTH_C-1 downto 0);
      fifoDin         : slv(ARB_GEARBOX_INPUT_WIDTH_G-1 downto 0);
      fifoValid       : sl;
      fifoDinArb      : slv(ARB_GEARBOX_INPUT_WIDTH_G-1 downto 0);
      fifoValidArb    : sl;
      busyCnt         : natural range 0 to 4095;
      state           : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      -- i/o
      dataLenSel      => (others => '0'),
      dataBusSel      => DEFAULT_PIX2PGP_DATABUS_C,
      dataRd          => '0',
      colSel          => (others => '0'),
      arbiterStart    => '0',
      statusFifoError => '0',
      dataFifoError   => '0',
      overOccError    => '0',
      alignError      => '0',
      colBitmask      => (others => '0'),
      trgNum          => (others => '0'),
      arbiterBusy     => '0',
      -- internal
      eventEmpty      => '0',
      headerOnly      => '0',
      dataHeader      => (others => '0'),
      headerSel       => '0',
      dataRdCnt       => (others => '0'),
      fifoDin         => (others => '0'),
      fifoValid       => '0',
      fifoDinArb      => (others => '0'),
      fifoValidArb    => '0',
      busyCnt         => 0,
      state           => IDLE_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   ------------------------------------------------
   -- Arbiter FSM
   ------------------------------------------------
   comb : process (r, rst, dataLenSel, dataBusSel, arbiterStart, statusFifoError,
                   dataFifoError, overOccError, alignError, colBitmask, trgNum, dataRdDly) is

      variable v : RegType;

   begin

      -- Latch the current value
      v := r;

      -- Register inputs
      v.dataLenSel      := dataLenSel;
      v.dataBusSel      := dataBusSel;
      v.arbiterStart    := arbiterStart;
      v.statusFifoError := statusFifoError;
      v.dataFifoError   := dataFifoError;
      v.overOccError    := overOccError;
      v.alignError      := alignError;
      v.colBitmask      := colBitmask;
      v.trgNum          := trgNum;

      v.eventEmpty      := not(uOr(r.colBitmask));

      if (r.arbiterBusy = '1') then
         v.busyCnt := r.busyCnt + 1;
      end if;
      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- supervisor signals a start of sequence
         -- raise the busy flag
         when IDLE_S =>
            v.fifoValid   := '0';
            v.headerSel   := '0';
            v.arbiterBusy := '0';

            if r.arbiterStart = '1' then
               v.arbiterBusy := '1';
               v.state       := TX_HEADER_S;
            end if;

         ----------------------------------------------------------------------
         -- check the error flags first (overocc is ignored by the Arbiter)
         when TX_HEADER_S =>

            -- Header demux
            case r.headerSel is
            when '0'    => v.fifoDin := r.dataHeader(39 downto 20); v.fifoValid := '1';
            when '1'    => v.fifoDin := r.dataHeader(19 downto  0); v.fifoValid := '1';
            when others => v.fifoDin := (others => '0'); v.fifoValid := '0';
            end case;

            v.headerSel := not r.headerSel;

            if (r.headerSel = '1') then -- maxed-out; time to move on.
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
            v.fifoValid := '0';
            v.headerSel := '0';
            if allBits((r.dataLenSel), '0') then
               v.state := INCR_SEL_S;
            else
               -- TX the dataLength and start reading the data fifo
               v.fifoDin(ARB_GEARBOX_INPUT_WIDTH_G-1 downto 10) := (others => '0');
               v.fifoDin(9 downto 0)                            := r.dataLenSel;
               v.dataRdCnt := (others => '0');
               v.fifoValid := '1';
               v.dataRd    := '1';
               v.state     := PARSE_DATA_S;
            end if;

         ----------------------------------------------------------------------
         -- check the data length of the selected column
         when INCR_SEL_S =>
            v.colSel := r.colSel + 1;
            if (conv_integer(unsigned(r.colSel)) <= NUM_OF_COL_MANAGERS_C-1) then
               v.state := ROUND_ROBIN_S;
            else
               v.state := DONE_S;
            end if;

         ----------------------------------------------------------------------
         -- parse the data from the selected data bus
         when PARSE_DATA_S =>
            v.fifoValid := '0';
            v.fifoDin   := v.dataBusSel.data;
            v.dataRdCnt := r.dataRdCnt + 1;

            -- dataRd control
            if r.dataRdCnt = r.dataLenSel - 1 then
               v.dataRd := '0';
            end if;

            -- fifoValid control
            if r.dataRdCnt >= STANDALONE_FIFO_WR_DELAY_C then
               v.fifoValid := '1';
            end if;

            if r.dataRdCnt = r.dataLenSel + STANDALONE_FIFO_WR_DELAY_C then
               v.fifoValid := '0';
               v.dataRdCnt := (others => '0');
               v.state     := INCR_SEL_S;
            end if;

         ----------------------------------------------------------------------
         -- last state
         when DONE_S =>
            v.arbiterBusy := '0';
            if r.arbiterStart = '0' then
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
      dataRd <= r.dataRd;
      colSel <= r.colSel;

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

   STANDALONE_DELAY_GEN : if (STANDALONE_G = true) generate
      -- delay the FIFO write wrt data FIFO rd by 2 cycles if using native blockRAM (sim)
      U_DelayWrFifo : entity surf.Synchronizer
         generic map (
            TPD_G          => TPD_G,
            RST_POLARITY_G => RST_POLARITY_G,
            RST_ASYNC_G    => true,
            STAGES_G       => STANDALONE_FIFO_WR_DELAY_C)
         port map (
            clk     => pgpClk,
            rst     => rst,
            dataIn  => r.dataRd,
            dataOut => dataRdDly);
   end generate STANDALONE_DELAY_GEN;

   ASIC_FLOW_GEN : if (STANDALONE_G = false) generate

      --U_DelayWrFifo : entity surf.Synchronizer
      --   generic map (
      --      TPD_G          => TPD_G,
      --      RST_POLARITY_G => RST_POLARITY_G,
      --      RST_ASYNC_G    => true,
      --      STAGES_G       => VENDOR_FIFO_WR_DELAY_C)
      --   port map (
      --      clk     => pgpClk,
      --      rst     => rst,
      --      dataIn  => r.dataRd,
      --      dataOut => dataRdDly);

      -- vendor proprietary fifo placeholder
      -- remove this once you place the vendor FIFO
      assert (STANDALONE_G = false)
      report "[ERROR]: No vendor proprietary FIFO implemented yet!"
      severity failure;

   end generate ASIC_FLOW_GEN;

   ------------------------------------------------
   -- Data FIFO (does not have to be deep)
   ------------------------------------------------
   U_DataFifo : entity pix2pgp.Pix2PgpFifoWrapper
      generic map (
         TPD_G           => TPD_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         GEN_SYNC_FIFO_G => false,
         DATA_WIDTH_G    => ARB_GEARBOX_INPUT_WIDTH_G,
         ADDR_WIDTH_G    => 4,
         STANDALONE_G    => STANDALONE_G)
      port map (
         -- Resets
         rst   => rst,
         -- Write Interface
         wrClk => pgpClk,
         wrEn  => r.fifoValid,
         full  => fifoFull,
         din   => r.fifoDin,
         -- Read Interface
         rdClk => pgpClk,
         empty => arbEmpty,
         rdEn  => arbRdEn,
         dout  => arbDout);

end rtl;
