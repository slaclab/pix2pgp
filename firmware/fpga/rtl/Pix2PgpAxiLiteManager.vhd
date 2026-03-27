-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp ASIC Stream RX AXI Management Logic
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
use surf.AxiLitePkg.all;
use surf.SsiPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpAsicPkg.all;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpAxiLiteManager is
   generic(
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1';   -- '1' for active high rst, '0' for active low
      LANE_MON_GEN_G : boolean := false);
   port(
      -- General Interface
      pgpRxClk        : in  sl;
      pgpRxRst        : in  sl;
      usrRst          : out sl;
      config          : out Pix2PgpStreamRxConfigType;
      pgp4RxLinkDown  : in  slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      mergerState     : in  slv(STATE_MON_WIDTH_C-1 downto 0);
      superState      : in  slv(STATE_MON_WIDTH_C-1 downto 0);
      -- AXI-Lite Interface (sync'd to pgpRxClk domain)
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType);
end Pix2PgpAxiLiteManager;

architecture rtl of Pix2PgpAxiLiteManager is

   type RegType is record
      config     : Pix2PgpStreamRxConfigType;
      usrRst     : sl;
      linkDown   : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      -- AXI-Lite
      readSlave  : AxiLiteReadSlaveType;
      writeSlave : AxiLiteWriteSlaveType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      config     => DEFAULT_PIX2PGP_STREAMRX_CONFIG_C,
      usrRst     => '0',
      linkDown   => (others => '0'),
      -- AXI-Lite
      readSlave  => AXI_LITE_READ_SLAVE_INIT_C,
      writeSlave => AXI_LITE_WRITE_SLAVE_INIT_C);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   -------------------------------------------------------------------------------------------------
   -------------------------------------------------------------------------------------------------
   comb : process (axilReadMaster, pgpRxRst, axilWriteMaster,
                   mergerState, superState,  pgp4RxLinkDown, r) is

      variable v : RegType;
      variable axilEp : AxiLiteEndpointType;

   begin

      -- Latch the current value
      v := r;

      v.linkDown := pgp4RxLinkDown;

      ----------------------------------------------------------------------------------------------
      -- AXI-Lite Transactions
      ----------------------------------------------------------------------------------------------

      -- Determine the transaction type
      axiSlaveWaitTxn(axilEp, axilWriteMaster, axilReadMaster, v.writeSlave, v.readSlave);

      axiSlaveRegister (axilEp, x"400", 0, v.config.fpgaId);
      axiSlaveRegister (axilEp, x"404", 0, v.config.laneTimeout);
      axiSlaveRegister (axilEp, x"408", 0, v.config.laneEnable);
      axiSlaveRegister (axilEp, x"40C", 0, v.config.dropColMisalign);
      axiSlaveRegister (axilEp, x"410", 0, v.config.dropLaneMisalign);
      axiSlaveRegister (axilEp, x"414", 0, v.config.realignOnSof);
      axiSlaveRegister (axilEp, x"418", 0, v.config.autoRealign);
      axiSlaveRegister (axilEp, x"41C", 0, v.config.rstFpgaTrgCnt);
      axiSlaveRegister (axilEp, x"420", 0, v.config.incrSroEnLow);
      axiSlaveRegister (axilEp, x"424", 0, v.config.triggerless);
      --
      axiSlaveRegister (axilEp, x"500", 0, v.usrRst);
      --
      axiSlaveRegisterR(axilEp, x"600", 0, toSl(LANE_MON_GEN_G));
      axiSlaveRegisterR(axilEp, x"604", 0, r.linkDown);
      axiSlaveRegisterR(axilEp, x"608", 0, mergerState);
      axiSlaveRegisterR(axilEp, x"60C", 0, superState);
      --

      -- Closeout the transaction
      axiSlaveDefault(axilEp, v.writeSlave, v.readSlave, AXI_RESP_DECERR_C);
      ----------------------------------------------------------------------------------------------

      -- AXI-Lite Outputs
      axilWriteSlave <= r.writeSlave;
      axilReadSlave  <= r.readSlave;

      -- Outputs
      config <= r.config;

      -- user-generated reset
      usrRst <= r.usrRst;

      -- Reset
      if (RST_ASYNC_G = false and pgpRxRst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (pgpRxClk, pgpRxRst) is
   begin
      if (RST_ASYNC_G and pgpRxRst = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(pgpRxClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;
   -------------------------------------------------------------------------------------------------
   -------------------------------------------------------------------------------------------------

end rtl;
