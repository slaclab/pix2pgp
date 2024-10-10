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

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpTop is
   generic(
      TPD_G                      : time     := 1 ns;
      RST_ASYNC_G                : boolean  := true;
      RST_POLARITY_G             : sl       := '1';
      PIPELINE_BRIDGE_DATA_G     : boolean  := false;
      PIPELINE_BRIDGE_STATUS_G   : boolean  := true;
      COLMANAGER_DATA_DEPTH_G    : integer  := 6;
      COLMANAGER_STATUS_DEPTH_G  : integer  := 4;
      ADAPTER_DEPTH_G            : integer  := 16;
      ADAPTER_AF_LVL_G           : integer  := 2;
      SUPER_FIFO_RD_DELAY_G      : positive := 3;
      DATAFIFO_PIPE_G            : positive := 1;
      STATUSFIFO_PIPE_G          : positive := 1;
      ARB_DOUT_PIPE_G            : positive := 1);
   port(
      -- General Interface
      sparseClk    : in  sl;
      pgpClk       : in  sl;
      sparseRst    : in  sl := not(RST_POLARITY_G);
      pgpRst       : in  sl := not(RST_POLARITY_G);
      columnEnable : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- Column Manager Interface
      din          : in  Pix2PgpSparseDinArray;
      wrEn         : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      sof          : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      eof          : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      overOcc      : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      busy         : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      pause        : out slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- Pgp4TxLite Interface
      txReady      : in  sl;
      txValid      : out sl;
      txData       : out slv(63 downto 0);
      txSof        : out sl;
      txEof        : out sl;
      txEofe       : out sl);
end Pix2PgpTop;

architecture rtl of Pix2PgpTop is

   signal dataRd         : sl := '0';
   signal colSel         : slv(BITMAX_COL_MANAGERS_C downto 0) := (others => '0');
   signal dataRdSel      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal statusBusSel   : Pix2PgpStatusBusType  := DEFAULT_PIX2PGP_STATUSBUS_C;
   signal dataBusSel     : Pix2PgpDataBusType    := DEFAULT_PIX2PGP_DATABUS_C;
   signal statusBus      : Pix2PgpStatusBusArray := (others => DEFAULT_PIX2PGP_STATUSBUS_C);
   signal statusBusGlbl  : Pix2PgpStatusBusArray := (others => DEFAULT_PIX2PGP_STATUSBUS_C);
   signal dataBus        : Pix2PgpDataBusArray   := (others => DEFAULT_PIX2PGP_DATABUS_C);
   signal statusRdSuper  : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal statusRdCol    : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   --
   signal arbStart       : sl := '0';
   signal colFifoError   : sl := '0';
   signal overOccError   : sl := '0';
   signal alignError     : sl := '0';
   signal arbBusy        : sl := '0';
   signal colPause       : sl := '0';
   signal colBitmask     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0)  := (others => '0');
   signal trgNum         : slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0) := (others => '0');
   --
   signal pgpReady       : sl := '0';
   signal pgpValid       : sl := '0';
   signal pgpData        : slv(PGP_DWIDTH_C-1 downto 0) := (others => '0');

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
            DATAFIFO_PIPE_G   => DATAFIFO_PIPE_G,
            STATUSFIFO_PIPE_G => STATUSFIFO_PIPE_G,
            DATA_DEPTH_G      => COLMANAGER_DATA_DEPTH_G,
            STATUS_DEPTH_G    => COLMANAGER_STATUS_DEPTH_G)
         port map(
            -- General Interface
            sparseClk => sparseClk,
            pgpClk    => pgpClk,
            sparseRst => sparseRst,
            enable    => columnEnable(col),
            -- Sparse Logic Interface
            din       => din(col),
            wrEn      => wrEn(col),
            sof       => sof(col),
            eof       => eof(col),
            overOcc   => overOcc(col),
            busy      => busy(col),
            pause     => pause(col),
            -- Arbiter Interface
            statusRd  => statusRdCol(col),
            dataRd    => dataRdSel(col),
            statusBus => statusBus(col),
            dataBus   => dataBus(col));
   end generate GEN_COL_MANAGER;

   ---------------------------------------
   -- Bridge
   ---------------------------------------
   -- set bridge to no pipelining since we are pipelining on the column manager level;
   -- that is, the FIFO dins/wrEns are pipelined; these signals can be 'slower'.
   -- reading and switching between FIFOs should be much faster. So no pipelinening.
   U_Bridge : entity pix2pgp.Pix2PgpBridge
      generic map(
         TPD_G             => TPD_G,
         PIPELINE_DATA_G   => PIPELINE_BRIDGE_DATA_G,
         PIPELINE_STATUS_G => PIPELINE_BRIDGE_STATUS_G)
      port map(
         -- General Interface
         pgpClk        => pgpClk,
         -- Column Manager Interface
         statusBusIn   => statusBus,
         dataBusIn     => dataBus,
         statusRdOut   => statusRdCol,
         dataRdOut     => dataRdSel,
         -- Column Supervisor Interface
         statusRdIn    => statusRdSuper,
         statusBusGlbl => statusBusGlbl,
         -- Arbiter Interface
         dataRdIn      => dataRd,
         colSel        => colSel,
         statusBusSel  => statusBusSel,
         dataBusSel    => dataBusSel);

   ---------------------------------------
   -- Column Supervisor
   ---------------------------------------
   U_ColumnSupervisor : entity pix2pgp.Pix2PgpColumnSupervisor
      generic map(
         TPD_G           => TPD_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         FIFO_RD_DELAY_G => SUPER_FIFO_RD_DELAY_G)
      port map(
         -- General Interface
         pgpClk        => pgpClk,
         pgpRst        => pgpRst,
         columnEnable  => columnEnable,
         -- Column Manager Interface (via Bridge)
         statusBusGlbl => statusBusGlbl,
         statusRd      => statusRdSuper,
         -- Arbiter Interface
         arbiterBusy   => arbBusy,
         arbiterStart  => arbStart,
         colFifoError  => colFifoError,
         overOccError  => overOccError,
         alignError    => alignError,
         colPause      => colPause,
         colBitmask    => colBitmask,
         trgNum        => trgNum);

   -----------------------------------------
   -- Arbiter
   -----------------------------------------
   U_Arbiter : entity pix2pgp.Pix2PgpArbiter
      generic map (
         TPD_G           => TPD_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         DOUT_PIPE_G     => ARB_DOUT_PIPE_G)
      port map (
         -- General Interface
         pgpClk       => pgpClk,
         pgpRst       => pgpRst,
         -- Column Manager Interface
         dataLenSel   => statusBusSel.dataLen,
         dataBusSel   => dataBusSel,
         dataRd       => dataRd,
         colSel       => colSel,
         -- Column Supervisor Interface
         arbStart     => arbStart,
         colFifoError => colFifoError,
         overOccError => overOccError,
         alignError   => alignError,
         colPause     => colPause,
         colBitmask   => colBitmask,
         trgNum       => trgNum,
         arbBusy      => arbBusy,
         -- Pgp Adapter Interface
         pgpReady     => pgpReady,
         pgpValid     => pgpValid,
         pgpData      => pgpData);

   -----------------------------------------
   -- PGP FIFO adapter
   -----------------------------------------
   U_Adapter: entity pix2pgp.Pix2PgpAdapter
      generic map(
         TPD_G           => TPD_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         DWARE_DEPTH_G   => ADAPTER_DEPTH_G,
         DWARE_AF_LVL_G  => ADAPTER_AF_LVL_G)
      port map(
         -- General Interface
         pgpClk   => pgpClk,
         pgpRst   => pgpRst,
         -- Gearbox Interface
         pgpValid => pgpValid,
         pgpData  => pgpData,
         pgpReady => pgpReady,
         -- Pgp4TxLite Interface
         txReady  => txReady,
         txValid  => txValid,
         txData   => txData,
         txSof    => txSof,
         txEof    => txEof,
         txEofe   => txEofe);

end rtl;
