-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: PIX2PGP Arbiter
--              Column Supervisor signals Arbiter that FIFO statuses are stable
--              Then Arbiter parses in the data accordingly
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
use surf.SsiPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpAsicPkg.all;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpArbiter is
   generic(
      TPD_G             : time      := 1 ns;
      RST_ASYNC_G       : boolean   := false;
      RST_POLARITY_G    : std_logic := '1';
      PIPELINE_STATUS_G : boolean   := false;
      PIPELINE_DATA_G   : boolean   := false);
   port(
      -- General Interface
      pgpClk        : in  sl;
      pgpRst        : in  sl;
      arbBusy       : out sl;
      -- Column Manager Interface
      statusBus     : in  Pix2PgpStatusBusArray;
      dataBus       : in  Pix2PgpDataBusArray;
      dataRd        : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- Column Supervisor Interface
      arbStart      : in  sl;
      colFifoError  : in  sl;
      overOccError  : in  sl;
      colPauseError : in  sl;
      timeoutError  : in  sl;
      colPause      : in  sl;
      trgCntGlbl    : in  slv(TRGCNT_WIDTH_C-1 downto 0);
      colHitmask    : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colTimeout    : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- Pgp4TxLite Interface
      pgpTxMaster   : out AxiStreamMasterType;
      pgpTxSlave    : in  AxiStreamSlaveType);
end Pix2PgpArbiter;

architecture rtl of Pix2PgpArbiter is

   type StateType is (
      IDLE_S,
      PARSE_HEADER_S,
      CHECK_HITMASK_S,
      PARSE_DATA_S,
      TX_DUMMY_S);

   type RegType is record
      -- inputs
      colPause     : sl;
      arbStart     : sl;
      colHitmask   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colTimeout   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      trgCntGlbl   : slv(TRGCNT_WIDTH_C-1 downto 0);
      dataBus      : Pix2PgpDataBusArray;
      statusBus    : Pix2PgpStatusBusArray;
      -- outputs
      dataRd       : sl;
      colSel       : slv(BITMAX_COL_MANAGERS_C-1 downto 0);
      arbBusy      : sl;
      -- internal
      eventEmpty   : sl;
      dummyHeader  : sl;
      waitColSel   : sl;
      txData       : slv(ASIC_DATABUS_DWIDTH_C-1 downto 0);
      dummyCnt     : slv(2 downto 0);
      dataHeader   : slv(HEADER_DWIDTH_C-1 downto 0);
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
      colHitmask    => (others => '0'),
      colTimeout    => (others => '0'),
      trgCntGlbl    => (others => '0'),
      dataBus       => (others => DEFAULT_PIX2PGP_DATABUS_C),
      statusBus     => (others => DEFAULT_PIX2PGP_STATUSBUS_C),
      -- outputs
      dataRd        => '0',
      colSel        => (others => '0'),
      arbBusy       => '0',
      -- internal
      eventEmpty    => '0',
      dummyHeader   => '0',
      waitColSel    => '0',
      txData        => (others => '0'),
      dummyCnt      => (others => '0'),
      dataHeader    => (others => '0'),
      dataRdCnt     => toSlv(0, DATALEN_WIDTH_C),
      dataRdCycles  => (others => '0'),
      state         => IDLE_S,
      sAxisMaster   => AXI_STREAM_MASTER_INIT_C,
      sAxisSlave    => AXI_STREAM_SLAVE_INIT_C);

   signal r   : RegType;
   signal rin : RegType;

   -- reset via the variables
   signal sAxisMaster : AxiStreamMasterType;
   signal sAxisSlave  : AxiStreamSlaveType;

begin

   ------------------------------------------------
   -- Arbiter FSM
   ------------------------------------------------
   comb : process (r, pgpRst, dataBus, statusBus, arbStart, colFifoError,
                   overOccError, colHitmask, colPause, colPauseError, sAxisSlave,
                   trgCntGlbl, timeoutError, colTimeout) is

      variable v : RegType;
      -- temp variables for status bus
      variable pauseSel    : sl;
      variable overOccSel  : sl;
      variable timeoutSel  : sl;
      variable flagsSel    : slv(7 downto 0);
      variable dataLenSel  : slv(DATALEN_WIDTH_C-1 downto 0);
      variable trgCntSel   : slv(TRGCNT_WIDTH_C-1 downto 0);
      -- temp variables for data bus
      variable dataBusSel  : slv(ASIC_DATABUS_DWIDTH_C-1 downto 0);

   begin

      -- Latch the current value
      v := r;

      -- inputs
      v.eventEmpty := not(uOr(colHitmask));
      v.sAxisSlave := sAxisSlave;
      v.arbStart   := arbStart;
      v.statusBus  := statusBus;
      v.dataBus    := dataBus;
      v.colTimeout := colTimeout;

      -- defaults
      v.dataRd := '0';

      -- flow control check
      if sAxisSlave.tReady = '1' then

         -- SparkPix-S -> ASIC_TYPE_C=1; emulate AXI behavior of SparkPix-S
         if ASIC_TYPE_C > 1 then
            v.sAxisMaster.tUser := (others => '0');
            v.sAxisMaster.tLast := '0';
         end if;

         -- always present
         v.sAxisMaster.tValid := '0';

      end if;

      -- default flags
      if ASIC_TYPE_C = 1 then
         -- SparkPix-S -> ASIC_TYPE_C=1; emulate AXI behavior of SparkPix-S
         v.sAxisMaster.tUser := (others => '0');
         v.sAxisMaster.tLast := '0';
      end if;

      -- always present
      v.sAxisMaster.tKeep  := (others => '1');

      -- status Mux
      if PIPELINE_STATUS_G then
         overOccSel   := r.statusBus(conv_integer(unsigned(r.colSel))).overOcc;
         pauseSel     := r.statusBus(conv_integer(unsigned(r.colSel))).pause;
         dataLenSel   := r.statusBus(conv_integer(unsigned(r.colSel))).dataLen;
         trgCntSel    := r.statusBus(conv_integer(unsigned(r.colSel))).trgCnt;
         timeoutSel   := r.colTimeout(conv_integer(unsigned(r.colSel)));
      else
         overOccSel   := v.statusBus(conv_integer(unsigned(r.colSel))).overOcc;
         pauseSel     := v.statusBus(conv_integer(unsigned(r.colSel))).pause;
         dataLenSel   := v.statusBus(conv_integer(unsigned(r.colSel))).dataLen;
         trgCntSel    := v.statusBus(conv_integer(unsigned(r.colSel))).trgCnt;
         timeoutSel   := v.colTimeout(conv_integer(unsigned(r.colSel)));
      end if;

      -- group the flags
      flagsSel := resize(timeoutSel & overOccSel & pauseSel, 8);

      -- data Mux
      dataBusSel := v.dataBus(conv_integer(unsigned(r.colSel))).data;

      -------------------------------------------------------------------------
      case r.state is
      -------------------------------------------------------------------------
         -- supervisor signals a start of sequence
         -- raise the busy flag and forward the header as-is
         when IDLE_S =>
            v.arbBusy     := '0';
            v.dummyHeader := '0';
            v.dummyCnt    := (others => '0');
            v.colSel      := (others => '0');

            if r.arbStart = '1' then
               v.arbBusy := '1';
               v.state   := PARSE_HEADER_S;
            end if;

         ----------------------------------------------------------------------
         -- parse the header to the gearbox;
         -- determine what to do next
         when PARSE_HEADER_S =>
            if v.sAxisMaster.tValid = '0' then
               ssiSetUserSof(ASIC_DATA_AXI_CONFIG_C, v.sAxisMaster, '1');
               v.sAxisMaster.tValid   := '1';
               v.txData               := v.dataHeader;

               v.state := CHECK_HITMASK_S;

               -- if empty, go-to state where dummy headers are TX'd
               if v.eventEmpty = '1' then
                  v.state := TX_DUMMY_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- check the hitmask value of the selected column
         -- if non-zero, write the column metadata and start reading immediately
         when CHECK_HITMASK_S =>
            if colHitmask(conv_integer(unsigned(r.colSel))) = '0' then

               if conv_integer(unsigned(r.colSel)) = NUM_OF_COL_MANAGERS_C-1 then
                  v.state  := TX_DUMMY_S;
               else
                  v.colSel := r.colSel + 1;
               end if;

            else
               v.waitColSel := '1'; -- wait one cycle for mux/demuxes to stabilize

               if r.waitColSel = '1' then
                  if v.sAxisMaster.tValid = '0' then
                     -- column metadata mapping in pkg (changes with ASIC type)
                     v.txData             := colMetaMap(flagsSel, r.colSel, trgCntSel, dataLenSel);
                     v.sAxisMaster.tValid := '1';
                     --
                     v.dataRdCnt := toSlv(0, DATALEN_WIDTH_C);

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
            end if;

         ------------------------------------------------------------------------
         -- parse the data from the selected data bus
         when PARSE_DATA_S =>
            v.waitColSel := '0'; -- reset the flag

            if v.sAxisMaster.tValid = '0' and r.dataRdCnt /= r.dataRdCycles then
               --
               v.txData             := dataBusSel;
               v.sAxisMaster.tValid := '1';
               --
               v.dataRdCnt := r.dataRdCnt + 1;
               v.dataRd    := '1';
            end if;

            -- Done with column
            if r.dataRdCnt = r.dataRdCycles then
               --
               v.dataRd := '0';
               v.state  := CHECK_HITMASK_S;
               --
               -- Check if last column
               if conv_integer(unsigned(r.colSel)) = NUM_OF_COL_MANAGERS_C-1 then
                  v.state  := TX_DUMMY_S;
               else
                  v.colSel := r.colSel + 1;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- stuffs the gearbox with dummy headers
         -- essentially flushes out the last words written into the gearbox
         when TX_DUMMY_S =>
            v.dummyHeader := '1';

            if r.dummyHeader = '1' then
               if v.sAxisMaster.tValid = '0' then
                  v.txData             := v.dataHeader;
                  v.sAxisMaster.tValid := '1';

                  if sAxisSlave.tReady = '1' then
                     v.dummyCnt := r.dummyCnt + 1;
                  end if;

                  if r.dummyCnt = toSlv(TX_DUMMY_MAX_C, r.dummyCnt'length) then
                     v.sAxisMaster.tValid := '1';

                     -- SparkPix-S -> ASIC_TYPE_C=1; emulate AXI behavior of SparkPix-S
                     if ASIC_TYPE_C = 1 then
                        v.sAxisMaster.tValid := '0';
                     end if;

                     v.sAxisMaster.tLast := '1';
                     v.state             := IDLE_S;
                  end if;
               end if;
            end if;

      end case;
      -----------------------------------------------------------------------

      -- header mapping and overriding
      -- override header elements if in dummy-header-TX mode
      --
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
         v.colHitmask(col) := colHitmask(col) and not(v.dummyHeader);
      end loop;
      --
      for i in 0 to TRGCNT_WIDTH_C-1 loop
         v.trgCntGlbl(i) := trgCntGlbl(i) and not(v.dummyHeader);
      end loop;
      --
      --
      v.dataHeader := asicHeaderMap(overOccError, colPause, colFifoError, colPauseError,
                                    timeoutError, v.dummyHeader, v.colHitmask, v.trgCntGlbl);
      --
      v.sAxisMaster.tData(ASIC_DATABUS_DWIDTH_C-1 downto 0) := v.txData;
      --

      -- Outputs
      arbBusy     <= r.arbBusy;
      sAxisMaster <= r.sAxisMaster;

      -- Reset
      if (RST_ASYNC_G = false and pgpRst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Iterate bit-by-bit assignment for dataRd
      for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
         if col = conv_integer(unsigned(r.colSel)) then
            dataRd(col) <= v.dataRd;
         else
            dataRd(col) <= '0';
         end if;
      end loop;

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
   -- Axi-Stream Gearbox (if needed)
   -----------------------------------------
   GEN_GBOX: if ASIC_DATABUS_DWIDTH_C /= PGP_DWIDTH_C generate

      U_Gearbox : entity surf.AxiStreamGearbox
         generic map(
            -- General Configurations
            TPD_G               => TPD_G,
            RST_POLARITY_G      => RST_POLARITY_G,
            RST_ASYNC_G         => RST_ASYNC_G,
            -- AXI Stream Port Configurations
            SLAVE_AXI_CONFIG_G  => ASIC_DATA_AXI_CONFIG_C,
            MASTER_AXI_CONFIG_G => ASIC_TX_AXI_CONFIG_C)
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

   end generate GEN_GBOX;

   GEN_NO_GBOX: if ASIC_DATABUS_DWIDTH_C = PGP_DWIDTH_C generate

      pgpTxMaster <= sAxisMaster;
      sAxisSlave  <= pgpTxSlave;

   end generate GEN_NO_GBOX;

end rtl;
