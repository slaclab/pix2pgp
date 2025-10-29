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
      RST_POLARITY_G : sl      := '1');   -- '1' for active high rst, '0' for active low
   port(
      -- General Interface
      pgpRxClk        : in  sl;
      pgpRxRst        : in  sl;
      usrRst          : out sl;
      config          : out Pix2PgpStreamRxConfigType;
      -- Internal Module Interface
      mergerBusy      : in  sl;
      laneDown        : in  slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      asicStatus      : in  Pix2PgpLaneStatusArray;
      fpgaTrgCnt      : in  slv(TRGCNT_WIDTH_C-1 downto 0);
      -- AXI-Lite Interface
      axilClk         : in  sl;
      axilRst         : in  sl;
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType);
end Pix2PgpAxiLiteManager;

architecture rtl of Pix2PgpAxiLiteManager is

   type TrgCntArray is array (NUM_OF_SERIALIZERS_C-1 downto 0) of slv(TRGCNT_WIDTH_C-1 downto 0);

   signal readMaster  : AxiLiteReadMasterType;
   signal readSlave   : AxiLiteReadSlaveType;
   signal writeMaster : AxiLiteWriteMasterType;
   signal writeSlave  : AxiLiteWriteSlaveType;

   type RegType is record
      config          : Pix2PgpStreamRxConfigType;
      cntRst          : sl;
      usrRst          : sl;
      laneDecError    : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneOverOcc     : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      lanePause       : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      lanePauseError  : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneFull        : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneTimeout     : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneDecErrCnt   : Slv8Array(NUM_OF_SERIALIZERS_C-1 downto 0);
      lanePauseErrCnt : Slv8Array(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneFullCnt     : Slv8Array(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneOverOccCnt  : Slv8Array(NUM_OF_SERIALIZERS_C-1 downto 0);
      lanePauseCnt    : Slv8Array(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneTrgCnt      : TrgCntArray;
      -- AXI-Lite
      readSlave       : AxiLiteReadSlaveType;
      writeSlave      : AxiLiteWriteSlaveType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      config          => DEFAULT_PIX2PGP_STREAMRX_CONFIG_C,
      cntRst          => '1',
      usrRst          => '0',
      laneDecError    => (others => '0'),
      laneOverOcc     => (others => '0'),
      lanePause       => (others => '0'),
      lanePauseError  => (others => '0'),
      laneFull        => (others => '0'),
      laneTimeout     => (others => '0'),
      laneDecErrCnt   => (others => (others => '0')),
      lanePauseErrCnt => (others => (others => '0')),
      laneFullCnt     => (others => (others => '0')),
      laneOverOccCnt  => (others => (others => '0')),
      lanePauseCnt    => (others => (others => '0')),
      laneTrgCnt      => (others => (others => '0')),
      -- AXI-Lite
      readSlave       => AXI_LITE_READ_SLAVE_INIT_C,
      writeSlave      => AXI_LITE_WRITE_SLAVE_INIT_C);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   U_AxiLiteAsync : entity surf.AxiLiteAsync
      generic map (
         TPD_G           => TPD_G,
         NUM_ADDR_BITS_G => 12)
      port map (
         -- Slave Interface
         sAxiClk         => axilClk,
         sAxiClkRst      => axilRst,
         sAxiReadMaster  => axilReadMaster,
         sAxiReadSlave   => axilReadSlave,
         sAxiWriteMaster => axilWriteMaster,
         sAxiWriteSlave  => axilWriteSlave,
         -- Master Interface
         mAxiClk         => pgpRxClk,
         mAxiClkRst      => pgpRxRst,
         mAxiReadMaster  => readMaster,
         mAxiReadSlave   => readSlave,
         mAxiWriteMaster => writeMaster,
         mAxiWriteSlave  => writeSlave);

   -------------------------------------------------------------------------------------------------
   -------------------------------------------------------------------------------------------------
   comb : process (readMaster, pgpRxRst, writeMaster, laneDown,
                   mergerBusy, asicStatus, fpgaTrgCnt, r) is
      variable v : RegType;
      variable axilEp : AxiLiteEndpointType;
   begin

      -- Latch the current value
      v := r;

      -- Defaults
      v.cntRst := '0';

      ----------------------------------------------------------------------------------------------

      for i in NUM_OF_SERIALIZERS_C-1 downto 0 loop

         v.laneDecError(i)   := asicStatus(i).decError;
         v.laneOverOcc(i)    := asicStatus(i).overOcc;
         v.lanePause(i)      := asicStatus(i).pause;
         v.lanePauseError(i) := asicStatus(i).pauseError;
         v.laneFull(i)       := asicStatus(i).overflow;
         v.laneTimeout(i)    := asicStatus(i).timeout;
         v.laneTrgCnt(i)     := asicStatus(i).trgCnt;

         -- status counters
         -- increment counters on rising edge
         if  (v.laneDecError(i) = '1' and r.laneDecError(i) = '0') and
             (r.config.laneEnable(i) = '1')
         and uAnd(r.laneDecErrCnt(i)) /= '1' then
            v.laneDecErrCnt(i) := r.laneDecErrCnt(i) + 1;
         end if;

         if  (v.laneOverOcc(i) = '1' and r.laneOverOcc(i) = '0') and
             (r.config.laneEnable(i) = '1')
         and uAnd(r.laneOverOccCnt(i)) /= '1' then
            v.laneOverOccCnt(i) := r.laneOverOccCnt(i) + 1;
         end if;

         if  (v.lanePause(i) = '1' and r.lanePause(i) = '0') and
             (r.config.laneEnable(i) = '1')
         and uAnd(r.lanePauseCnt(i)) /= '1' then
            v.lanePauseCnt(i) := r.lanePauseCnt(i) + 1;
         end if;

         if  (v.lanePauseError(i) = '1' and r.lanePauseError(i) = '0') and
             (r.config.laneEnable(i) = '1')
         and  uAnd(r.lanePauseErrCnt(i)) /= '1' then
            v.lanePauseErrCnt(i) := r.lanePauseErrCnt(i) + 1;
         end if;

         if  (v.laneFull(i) = '1' and r.laneFull(i) = '0') and
             (r.config.laneEnable(i) = '1')
         and  uAnd(r.laneFullCnt(i)) /= '1' then
            v.laneFullCnt(i) := r.laneFullCnt(i) + 1;
         end if;

         if (r.cntRst = '1') then
            v.laneDecErrCnt(i)   := (others => '0');
            v.laneOverOccCnt(i)  := (others => '0');
            v.lanePauseCnt(i)    := (others => '0');
            v.lanePauseErrCnt(i) := (others => '0');
            v.laneFullCnt(i)     := (others => '0');
         end if;

      end loop;
      ----------------------------------------------------------------------------------------------

      ----------------------------------------------------------------------------------------------
      -- AXI-Lite Transactions
      ----------------------------------------------------------------------------------------------

      -- Determine the transaction type
      axiSlaveWaitTxn(axilEp, writeMaster, readMaster, v.writeSlave, v.readSlave);

      for i in NUM_OF_SERIALIZERS_C-1 downto 0 loop
         -- (Stride=4 bytes)
         axiSlaveRegisterR(axilEp, toSlv(512+4*i,  12), 0, r.laneDecErrCnt(i));   -- StartAddr=0x200
         axiSlaveRegisterR(axilEp, toSlv(768+4*i,  12), 0, r.laneOverOccCnt(i));  -- StartAddr=0x300
         axiSlaveRegisterR(axilEp, toSlv(1024+4*i, 12), 0, r.lanePauseCnt(i));    -- StartAddr=0x400
         axiSlaveRegisterR(axilEp, toSlv(1280+4*i, 12), 0, r.lanePauseErrCnt(i)); -- StartAddr=0x500
         axiSlaveRegisterR(axilEp, toSlv(1536+4*i, 12), 0, r.laneFullCnt(i));     -- StartAddr=0x600
         axiSlaveRegisterR(axilEp, toSlv(1792+4*i, 12), 0, r.laneTrgCnt(i));      -- StartAddr=0x700
      end loop;

      axiSlaveRegister (axilEp, x"800", 0, v.config.fpgaId);
      axiSlaveRegister (axilEp, x"804", 0, v.config.laneTimeout);
      axiSlaveRegister (axilEp, x"808", 0, v.config.laneEnable);
      axiSlaveRegister (axilEp, x"80C", 0, v.config.dropColMisalign);
      axiSlaveRegister (axilEp, x"810", 0, v.config.dropLaneMisalign);
      axiSlaveRegister (axilEp, x"814", 0, v.config.realignOnSof);
      axiSlaveRegister (axilEp, x"818", 0, v.config.autoRealign);
      axiSlaveRegister (axilEp, x"81C", 0, v.config.rstFpgaTrgCnt);
      axiSlaveRegister (axilEp, x"820", 0, v.config.incrSroEnLow);
      --
      axiSlaveRegister (axilEp, x"900", 0, v.cntRst);
      axiSlaveRegister (axilEp, x"904", 0, v.usrRst);
      --
      axiSlaveRegisterR(axilEp, x"A08", 0, laneDown);
      axiSlaveRegisterR(axilEp, x"A0C", 0, mergerBusy);
      axiSlaveRegisterR(axilEp, x"A10", 0, fpgaTrgCnt);
      --
      axiSlaveRegisterR(axilEp, x"B00", 0, r.laneDecError);
      axiSlaveRegisterR(axilEp, x"B04", 0, r.laneOverOcc);
      axiSlaveRegisterR(axilEp, x"B08", 0, r.lanePause);
      axiSlaveRegisterR(axilEp, x"B0C", 0, r.lanePauseError);
      axiSlaveRegisterR(axilEp, x"B10", 0, r.laneFull);
      axiSlaveRegisterR(axilEp, x"B14", 0, r.laneTimeout);

      -- Closeout the transaction
      axiSlaveDefault(axilEp, v.writeSlave, v.readSlave, AXI_RESP_DECERR_C);
      ----------------------------------------------------------------------------------------------

      -- AXI-Lite Outputs
      writeSlave <= r.writeSlave;
      readSlave  <= r.readSlave;

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
