-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: PIX2PGP Top Level
--
-- cb
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

entity Pix2PgpTop is
   generic(
      TPD_G                     : time      := 1 ns;
      RST_ASYNC_G               : boolean   := true;
      RST_POLARITY_G            : std_logic := '1';
      PIPELINE_DATA_G           : boolean   := false;
      PIPELINE_STATUS_G         : boolean   := true;
      COLMANAGER_DATA_DEPTH_G   : integer   := 7;
      COLMANAGER_STATUS_DEPTH_G : integer   := 6;
      DATAFIFO_PIPE_G           : natural   := 1;
      STATUSFIFO_PIPE_G         : natural   := 1);
   port(
      -- General Interface
      sparseClk    : in  sl;
      pgpClk       : in  sl;
      sparseRst    : in  sl;
      pgpRst       : in  sl;
      config       : in  Pix2PgpCfgConfigType;
      readback     : out Pix2PgpCfgReadbackType;
      -- Column Manager Interface
      din          : in  Pix2PgpSparseDinArray;
      wrEn         : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      sof          : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      eof          : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      overOcc      : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      pauseAck     : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      busy         : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      pause        : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- Pgp4TxLite Interface
      pgpTxMaster : out  AxiStreamMasterType;
      pgpTxSlave  : in   AxiStreamSlaveType);
end Pix2PgpTop;

architecture rtl of Pix2PgpTop is

   signal dataRd         : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
   signal statusRd       : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
   signal statusBus      : Pix2PgpStatusBusArray;
   signal dataBus        : Pix2PgpDataBusArray;
   --
   signal arbStart       : sl;
   signal colFifoError   : sl;
   signal overOccError   : sl;
   signal arbBusy        : sl;
   signal superBusy      : sl;
   signal colPause       : sl;
   signal colPauseError  : sl;
   signal timeoutError   : sl;
   signal anyColBusy     : sl;
   signal trgCntGlbl     : slv(TRGCNT_WIDTH_C-1 downto 0);
   signal colHitmask     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
   signal colTimeout     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
   signal colBusy        : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
   signal colDataEmpty   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
   signal colStatusEmpty : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
   --

begin

   ---------------------------------------
   -- Column Manager
   ---------------------------------------
   GEN_COL_MANAGER: for col in 0 to NUM_OF_COL_MANAGERS_C-1 generate

      U_ColumnManager: entity pix2pgp.Pix2PgpColumnManager
         generic map(
            TPD_G             => TPD_G,
            RST_ASYNC_G       => RST_ASYNC_G,
            RST_POLARITY_G    => RST_POLARITY_G,
            COL_ID_G          => col,
            DATAFIFO_PIPE_G   => DATAFIFO_PIPE_G,
            STATUSFIFO_PIPE_G => STATUSFIFO_PIPE_G,
            DATA_DEPTH_G      => COLMANAGER_DATA_DEPTH_G,
            STATUS_DEPTH_G    => COLMANAGER_STATUS_DEPTH_G)
         port map(
            -- General Interface
            sparseClk   => sparseClk,
            pgpClk      => pgpClk,
            sparseRst   => sparseRst,
            config      => config,
            dataEmpty   => colDataEmpty(col),
            statusEmpty => colStatusEmpty(col),
            -- Sparse Logic Interface
            din         => din(col),
            wrEn        => wrEn(col),
            sof         => sof(col),
            eof         => eof(col),
            overOcc     => overOcc(col),
            pauseAck    => pauseAck(col),
            busy        => colBusy(col),
            pause       => pause(col),
            -- Arbiter and Column Supervisor Interface
            statusRd    => statusRd(col),
            dataRd      => dataRd(col),
            statusBus   => statusBus(col),
            dataBus     => dataBus(col));

   end generate GEN_COL_MANAGER;

   ---------------------------------------
   -- Column Supervisor
   ---------------------------------------
   U_ColumnSupervisor : entity pix2pgp.Pix2PgpColumnSupervisor
      generic map(
         TPD_G             => TPD_G,
         RST_ASYNC_G       => RST_ASYNC_G,
         RST_POLARITY_G    => RST_POLARITY_G,
         PIPELINE_STATUS_G => PIPELINE_STATUS_G)
      port map(
         -- General Interface
         pgpClk        => pgpClk,
         pgpRst        => pgpRst,
         sparseClk     => sparseClk,
         sparseRst     => sparseRst,
         config        => config,
         superBusy     => superBusy,
         -- Column Manager Interface
         colBusy       => anyColBusy,
         statusBus     => statusBus,
         statusRd      => statusRd,
         -- Arbiter Interface
         arbiterBusy   => arbBusy,
         arbiterStart  => arbStart,
         trgCntGlbl    => trgCntGlbl,
         colFifoError  => colFifoError,
         overOccError  => overOccError,
         timeoutError  => timeoutError,
         colPauseError => colPauseError,
         colPause      => colPause,
         colHitmask    => colHitmask,
         colTimeout    => colTimeout);

   -----------------------------------------
   -- Arbiter
   -----------------------------------------
   U_Arbiter : entity pix2pgp.Pix2PgpArbiter
      generic map (
         TPD_G             => TPD_G,
         RST_ASYNC_G       => RST_ASYNC_G,
         RST_POLARITY_G    => RST_POLARITY_G,
         PIPELINE_STATUS_G => PIPELINE_STATUS_G,
         PIPELINE_DATA_G   => PIPELINE_DATA_G)
      port map (
         -- General Interface
         pgpClk        => pgpClk,
         pgpRst        => pgpRst,
         arbBusy       => arbBusy,
         -- Column Manager Interface
         statusBus     => statusBus,
         dataBus       => dataBus,
         dataRd        => dataRd,
         -- Column Supervisor Interface
         arbStart      => arbStart,
         trgCntGlbl    => trgCntGlbl,
         colFifoError  => colFifoError,
         colPauseError => colPauseError,
         overOccError  => overOccError,
         timeoutError  => timeoutError,
         colPause      => colPause,
         colHitmask    => colHitmask,
         colTimeout    => colTimeout,
         -- Pgp4TxLite Interface
         pgpTxMaster   => pgpTxMaster,
         pgpTxSlave    => pgpTxSlave);

   -----------------------------------------
   -- Async signals
   -----------------------------------------
   -- busy out
   busy <= colBusy;

   -- busy internal (sparseClk domain; re-sync if necessary)
   anyColBusy <= uOr(colBusy);

   -- readback bus glue logic
   readback.cfgColBusy        <= uOr(colBusy);
   readback.cfgColDataEmpty   <= uAnd(colDataEmpty);
   readback.cfgColStatusEmpty <= uAnd(colStatusEmpty);
   readback.cfgSuperBusy      <= superBusy;
   readback.cfgArbBusy        <= arbBusy;

end rtl;
