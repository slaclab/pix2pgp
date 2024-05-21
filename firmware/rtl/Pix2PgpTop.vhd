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
      TPD_G                 : time     := 1 ns;
      RST_ASYNC_G           : boolean  := true;
      RST_POLARITY_G        : sl       := '1';
      GHDL_SIM_G            : boolean  := true;
      SYNTHESIZE_G          : boolean  := false;
      DATAFIFO_FWFT_G       : boolean  := true;
      PIPELINE_BRIDGE_G     : boolean  := false;
      COLMANAGER_DEPTH_G    : integer  := 32;
      PGPADAPTER_DEPTH_G    : integer  := 12;
      DATAFIFO_PIPE_G       : positive := 2;
      STATUSFIFO_PIPE_G     : positive := 2;
      SUPER_FIFO_RD_DELAY_G : positive := 3;
      ARB_FIFO_RD_DELAY_G   : positive := 1;
      ARB_DOUT_PIPE_G       : positive := 2);
   port(
      -- General Interface
      sparseClk    : in  sl;
      pgpClk       : in  sl;
      rst          : in  sl;
      -- Column Manager Interface
      tok          : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      tokFb        : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      ackN         : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      wrEn         : in  slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      din          : in  Pix2PgpSparseDinArray;
      -- Pgp4TxLite Interface
      txReady      : in  sl;
      txValid      : out sl;
      txData       : out slv(63 downto 0);
      txSof        : out sl;
      txEof        : out sl;
      txEofe       : out sl;
      -- Temporary Debugging Interface (TO-DO: remove me)
      arbValidDbg  : out sl;
      arbDataDbg   : out slv(DATABUS_DWIDTH_C-1 downto 0);
      -- Configuration Register Interface (TO-DO: add more)
      frameSize    : in  slv(5 downto 0)); --in multiples of 64-bit words
end Pix2PgpTop;

architecture rtl of Pix2PgpTop is

   signal dataRd          : sl := '0';
   signal statusRd        : sl := '0';
   signal colSel          : slv(BITMAX_COL_MANAGERS_C downto 0) := (others => '0');
   signal dataRdSel       : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   signal statusBusSel    : Pix2PgpStatusBusType  := DEFAULT_PIX2PGP_STATUSBUS_C;
   signal dataBusSel      : Pix2PgpDataBusType    := DEFAULT_PIX2PGP_DATABUS_C;
   signal statusBus       : Pix2PgpStatusBusArray := (others => DEFAULT_PIX2PGP_STATUSBUS_C);
   signal statusBusGlbl   : Pix2PgpStatusBusArray := (others => DEFAULT_PIX2PGP_STATUSBUS_C);
   signal dataBus         : Pix2PgpDataBusArray   := (others => DEFAULT_PIX2PGP_DATABUS_C);
   signal statusRdFanOut  : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
   --
   signal arbStart        : sl := '0';
   signal statusFifoError : sl := '0';
   signal dataFifoError   : sl := '0';
   signal overOccError    : sl := '0';
   signal alignError      : sl := '0';
   signal arbBusy         : sl := '0';
   signal colBitmask      : slv(NUM_OF_COL_MANAGERS_C-1 downto 0)  := (others => '0');
   signal trgNum          : slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0) := (others => '0');
   signal arbValid        : sl := '0';
   signal arbDout         : slv(DATABUS_DWIDTH_C-1 downto 0) := (others => '0');
   --
   signal pgpValid        : sl := '0';
   signal pgpData         : slv(PGP_DWIDTH_C-1 downto 0) := (others => '0');

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
            DWARE_DEPTH_G     => COLMANAGER_DEPTH_G,
            GHDL_SIM_G        => GHDL_SIM_G,
            SYNTHESIZE_G      => SYNTHESIZE_G)
         port map(
            -- General Interface
            sparseClk => sparseClk,
            pgpClk    => pgpClk,
            rst       => rst,
            -- Sparse Logic Interface
            tok       => tok(col),
            tokFb     => tokFb(col),
            ackN      => ackN(col),
            wrEn      => wrEn(col),
            din       => din(col),
            -- Arbiter Interface
            statusRd  => statusRdFanOut(col),
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
         TPD_G      => TPD_G,
         PIPELINE_G => PIPELINE_BRIDGE_G)
      port map(
         -- General Interface
         pgpClk        => pgpClk,
         -- Column Manager Interface
         statusBusIn   => statusBus,
         dataBusIn     => dataBus,
         statusRdOut   => statusRdFanOut,
         dataRdOut     => dataRdSel,
         -- Column Supervisor Interface
         statusRdIn    => statusRd,
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
         pgpClk          => pgpClk,
         rst             => rst,
         -- Column Manager Interface
         statusBusGlbl   => statusBusGlbl,
         statusRd        => statusRd,
         -- Arbiter Interface
         arbiterBusy     => arbBusy,
         arbiterStart    => arbStart,
         statusFifoError => statusFifoError,
         dataFifoError   => dataFifoError,
         overOccError    => overOccError,
         alignError      => alignError,
         colBitmask      => colBitmask,
         trgNum          => trgNum);

   -----------------------------------------
   -- Arbiter
   -----------------------------------------
   U_Arbiter : entity pix2pgp.Pix2PgpArbiter
      generic map (
         TPD_G           => TPD_G,
         RST_ASYNC_G     => RST_ASYNC_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         FIFO_RD_DELAY_G => ARB_FIFO_RD_DELAY_G,
         DOUT_PIPE_G     => ARB_DOUT_PIPE_G,
         DATAFIFO_FWFT_G => DATAFIFO_FWFT_G)
      port map (
         -- General Interface
         pgpClk          => pgpClk,
         rst             => rst,
         -- Column Manager Interface
         dataLenSel      => statusBusSel.dataLen,
         dataBusSel      => dataBusSel,
         dataRd          => dataRd,
         colSel          => colSel,
         -- Column Supervisor Interface
         arbStart        => arbStart,
         statusFifoError => statusFifoError,
         dataFifoError   => dataFifoError,
         overOccError    => overOccError,
         alignError      => alignError,
         colBitmask      => colBitmask,
         trgNum          => trgNum,
         arbBusy         => arbBusy,
         -- Gearbox Interface
         arbValid        => arbValid,
         arbDout         => arbDout);

   arbValidDbg <= arbValid;
   arbDataDbg  <= arbDout;

   -----------------------------------------
   -- Gearbox
   -----------------------------------------
   U_Gearbox : entity pix2pgp.Pix2PgpGearboxWrapper
      generic map (
         TPD_G           => TPD_G,
         RST_POLARITY_G  => RST_POLARITY_G,
         RST_ASYNC_G     => RST_ASYNC_G)
      port map (
         -- General Interface
         pgpClk     => pgpClk,
         rst        => rst,
         -- Arbiter Interface
         arbValid   => arbValid,
         arbDout    => arbDout,
         arbReady   => open, -- TO-DO: evaluate; do I need to route this to the arbiter?
         writeIndex => open, -- TO-DO: route this to arbiter
         -- PGP Interface
         pgpReady   => '1', -- TO-DO: evaluate; do I need to route this to the PGP FIFO logic?
         pgpValid   => pgpValid,
         pgpData    => pgpData);

   -----------------------------------------
   -- PGP FIFO adapter
   -----------------------------------------
   U_Adapter: entity pix2pgp.Pix2PgpAdapter
   generic map(
      TPD_G           => TPD_G,
      RST_ASYNC_G     => RST_ASYNC_G,
      RST_POLARITY_G  => RST_POLARITY_G,
      DWARE_DEPTH_G   => PGPADAPTER_DEPTH_G,
      GHDL_SIM_G      => GHDL_SIM_G,
      SYNTHESIZE_G    => SYNTHESIZE_G)
   port map(
      -- General Interface
      pgpClk     => pgpClk,
      rst        => rst,
      -- Gearbox Interface
      pgpValid   => pgpValid,
      pgpData    => pgpData,
      -- Pgp4TxLite Interface
      txReady    => txReady,
      txValid    => txValid,
      txData     => txData,
      txSof      => txSof,
      txEof      => txEof,
      txEofe     => txEofe);

end rtl;
