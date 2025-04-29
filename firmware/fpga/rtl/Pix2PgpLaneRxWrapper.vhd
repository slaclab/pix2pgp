-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Wrapper for Pix2Pgp Single-Lane Receiver
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

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpLaneRxWrapper is
   generic(
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1'  -- '1' for active high rst, '0' for active low
   );
   port(
      -- General Interface
      pgpClk          : in  sl;
      pgpRst          : in  sl := not(RST_POLARITY_G);
      sysClk          : in  sl;
      sysRst          : in  sl := not(RST_POLARITY_G);
      -- RX FIFO Interface
      pix2pgpTxMaster : in  AxiStreamMasterType;
      pix2pgpTxSlave  : out AxiStreamSlaveType;
      -- ASIC Rx Interface
      lastTrgCnt      : out slv(TRGCNT_WIDTH_C-1 downto 0);
      laneError       : out sl;
      laneTxMaster    : out AxiStreamMasterType;
      laneTxSlave     : in  AxiStreamSlaveType);
end Pix2PgpLaneRxWrapper;

architecture rtl of Pix2PgpLaneRxWrapper is

   signal frameMetaRd      : sl := '0';
   signal frameMetaDout    : slv(LANERX_META_BUFF_WIDTH_C-1 downto 0) := (others => '0');
   signal frameMetaValid   : sl := '0';
   signal laneRxRst        : sl := '0';
   signal adapterAxiMaster : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
   signal adapterAxiSlave  : AxiStreamSlaveType  := AXI_STREAM_SLAVE_INIT_C;

begin

   U_Lane: entity pix2pgp.Pix2PgpLaneRx
      generic map(
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         RST_POLARITY_G => RST_POLARITY_G)
      port map(
         -- General Interface
         pgpClk          => pgpClk,
         pgpRst          => pgpRst,
         sysClk          => sysClk,
         sysRst          => sysRst,
         -- RX FIFO Interface
         pix2pgpTxMaster => pix2pgpTxMaster,
         pix2pgpTxSlave  => pix2pgpTxSlave,
         -- Adapter Interface
         laneRxRst       => laneRxRst,
         frameMetaRd     => frameMetaRd,
         frameMetaDout   => frameMetaDout,
         frameMetaValid  => frameMetaValid,
         -- AXI-Stream to Adapter
         obAxisMaster    => adapterAxiMaster,
         obAxisSlave     => adapterAxiSlave);

   U_Adapter: entity pix2pgp.Pix2PgpLaneAdapter
      generic map(
         TPD_G          => TPD_G,
         RST_ASYNC_G    => RST_ASYNC_G,
         RST_POLARITY_G => RST_POLARITY_G)
      port map(
         -- General Interface
         sysClk         => sysClk,
         sysRst         => sysRst,
         -- Lane Interface
         laneRxRst      => laneRxRst,
         frameMetaRd    => frameMetaRd,
         frameMetaDout  => frameMetaDout,
         frameMetaValid => frameMetaValid,
         -- AXI-Stream from Lane
         ibAxisMaster   => adapterAxiMaster,
         ibAxisSlave    => adapterAxiSlave,
         -- ASIC Rx Interface
         lastTrgCnt     => lastTrgCnt,
         laneError      => laneError,
         laneTxMaster   => laneTxMaster,
         laneTxSlave    => laneTxSlave);

end rtl;
