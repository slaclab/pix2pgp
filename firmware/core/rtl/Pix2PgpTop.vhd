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
      TPD_G                     : time     := 1 ns;
      RST_ASYNC_G               : boolean  := true;
      RST_POLARITY_G            : sl       := '1';
      PIPELINE_DATA_G           : boolean  := false;
      PIPELINE_STATUS_G         : boolean  := true;
      TIMEOUT_LIMIT_WIDTH_G     : positive := 12;
      COLMANAGER_DATA_DEPTH_G   : integer  := 7;
      COLMANAGER_STATUS_DEPTH_G : integer  := 6;
      DATAFIFO_PIPE_G           : natural  := 1;
      STATUSFIFO_PIPE_G         : natural  := 1);
   port(
      -- General Interface
      sparseClk    : in  sl;
      pgpClk       : in  sl;
      sparseRst    : in  sl;
      pgpRst       : in  sl;
      timeoutLimit : in  slv(TIMEOUT_LIMIT_WIDTH_G-1 downto 0);
      columnEnable : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
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
   signal columnBusy     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
   --
   signal arbStart       : sl;
   signal colFifoError   : sl;
   signal overOccError   : sl;
   signal arbBusy        : sl;
   signal colPause       : sl;
   signal colPauseError  : sl;
   signal timeoutError   : sl;
   signal trgCntGlbl     : slv(TRGCNT_WIDTH_C-1 downto 0);
   signal colBitmask     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
   --

begin

   -- route to output port
   busy <= columnBusy;

   ---------------------------------------
   -- Column Manager
   ---------------------------------------
   GEN_COL_MANAGER: for col in 0 to NUM_OF_COL_MANAGERS_C-1 generate
      U_ColumnManager: entity pix2pgp.Pix2PgpColumnManager
         generic map(
            TPD_G             => TPD_G,
            RST_ASYNC_G       => RST_ASYNC_G,
            RST_POLARITY_G    => RST_POLARITY_G,
            DATAFIFO_PIPE_G   => DATAFIFO_PIPE_G,
            STATUSFIFO_PIPE_G => STATUSFIFO_PIPE_G,
            DATA_DEPTH_G      => COLMANAGER_DATA_DEPTH_G,
            STATUS_DEPTH_G    => COLMANAGER_STATUS_DEPTH_G)
         port map(
            -- General Interface
            sparseClk => sparseClk,
            pgpClk    => pgpClk,
            sparseRst => sparseRst,
            -- Sparse Logic Interface
            din       => din(col),
            wrEn      => wrEn(col),
            sof       => sof(col),
            eof       => eof(col),
            overOcc   => overOcc(col),
            pauseAck  => pauseAck(col),
            busy      => columnBusy(col),
            pause     => pause(col),
            -- Arbiter and Column Supervisor Interface
            statusRd  => statusRd(col),
            dataRd    => dataRd(col),
            statusBus => statusBus(col),
            dataBus   => dataBus(col));
   end generate GEN_COL_MANAGER;

   ---------------------------------------
   -- Column Supervisor
   ---------------------------------------
   U_ColumnSupervisor : entity pix2pgp.Pix2PgpColumnSupervisor
      generic map(
         TPD_G                 => TPD_G,
         RST_ASYNC_G           => RST_ASYNC_G,
         RST_POLARITY_G        => RST_POLARITY_G,
         PIPELINE_STATUS_G     => PIPELINE_STATUS_G,
         TIMEOUT_LIMIT_WIDTH_G => TIMEOUT_LIMIT_WIDTH_G)
      port map(
         -- General Interface
         pgpClk        => pgpClk,
         pgpRst        => pgpRst,
         timeoutLimit  => timeoutLimit,
         columnEnable  => columnEnable,
         -- Column Manager Interface
         statusBus     => statusBus,
         columnBusy    => columnBusy,
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
         colBitmask    => colBitmask);

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
         colBitmask    => colBitmask,
         arbBusy       => arbBusy,
         -- Pgp4TxLite Interface
         pgpTxMaster   => pgpTxMaster,
         pgpTxSlave    => pgpTxSlave);

end rtl;
