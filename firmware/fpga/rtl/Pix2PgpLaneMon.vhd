-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp Lane Monitoring Module
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

entity Pix2PgpLaneMon is
   generic(
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1');   -- '1' for active high rst, '0' for active low
   port(
      -- General Interface
      pgpRxClk        : in  sl;
      pgpRxRst        : in  sl;
      -- Lane Interface
      laneDown        : in  sl;
      laneStatus      : in  Pix2PgpLaneStatusType;
      config          : in  Pix2PgpStreamRxConfigType;
      -- AXI-Lite Interface
      axilClk         : in  sl;
      axilRst         : in  sl;
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType);
end Pix2PgpLaneMon;

architecture rtl of Pix2PgpLaneMon is

   signal readMaster  : AxiLiteReadMasterType;
   signal readSlave   : AxiLiteReadSlaveType;
   signal writeMaster : AxiLiteWriteMasterType;
   signal writeSlave  : AxiLiteWriteSlaveType;

   type RegType is record
      cntRst          : sl;
      laneValid       : sl;
      laneStatus      : Pix2PgpLaneStatusType;
      laneDecError    : sl;
      laneOverOcc     : sl;
      lanePause       : sl;
      lanePauseError  : sl;
      laneFull        : sl;
      laneDecErrCnt   : slv(7 downto 0);
      lanePauseErrCnt : slv(7 downto 0);
      laneFullCnt     : slv(7 downto 0);
      laneOverOccCnt  : slv(7 downto 0);
      lanePauseCnt    : slv(7 downto 0);
      laneTrgCnt      : TrgCntArray;
      -- AXI-Lite
      readSlave       : AxiLiteReadSlaveType;
      writeSlave      : AxiLiteWriteSlaveType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      cntRst          => '1',
      laneValid       => '0',
      laneStatus      => DEFAULT_PIX2PGP_LANESTATUS_C,
      laneDecError    => '0',
      laneOverOcc     => '0',
      lanePause       => '0',
      lanePauseError  => '0',
      laneFull        => '0',
      laneDecErrCnt   => (others => '0'),
      lanePauseErrCnt => (others => '0'),
      laneFullCnt     => (others => '0'),
      laneOverOccCnt  => (others => '0'),
      lanePauseCnt    => (others => '0'),
      laneTrgCnt      => (others => '0'),
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
   comb : process (readMaster, pgpRxRst, writeMaster, laneDown, config,
                   laneStatus, fpgaTrgCnt, r) is
      variable v : RegType;
      variable axilEp : AxiLiteEndpointType;
   begin

      -- Latch the current value
      v := r;

      -- Defaults
      v.cntRst    := '0';
      v.laneDown  := laneDown;

      -- Register the lane status bus
      v.laneStatus := laneStatus;

      v.laneValid      := r.laneStatus.valid;
      v.laneDecError   := r.laneStatus.laneDecError;
      v.laneOverOcc    := r.laneStatus.laneOverOcc;
      v.lanePause      := r.laneStatus.lanePause;
      v.lanePauseError := r.laneStatus.lanePauseError;
      v.laneFull       := r.laneStatus.laneFull;

      ----------------------------------------------------------------------------------------------
      if config.laneEnable = '1' and r.cntRst = '0' and r.laneDown = '0' then

         -- increment on rising-edge of valid
         if v.laneValid = '1' and r.laneValid = '0' then

            if v.laneOverOcc = '1' and uAnd(r.laneOverOccCnt) = '0' then
               v.laneOverOccCnt := r.laneOverOccCnt + 1;
            end if;

            if v.lanePause = '1' and uAnd(r.lanePauseCnt) = '0' then
               v.lanePauseCnt := r.lanePauseCnt + 1;
            end if;

            if v.lanePauseError = '1' and uAnd(r.lanePauseErrCnt) = '0' then
               v.lanePauseErrCnt := r.lanePauseErrCnt + 1;
            end if;

         end if;

         -- not going through metadata buffer; increment on rising edge of status bit
         if v.laneDecError = '1' and r.laneDecError = '0' and uAnd(r.laneDecErrCnt) = '0' then
            v.laneDecErrCnt := r.laneDecErrCnt + 1;
         end if;

         -- not going through metadata buffer; increment on rising edge of status bit
         if v.laneFull = '1' and r.laneFull = '0' and uAnd(r.laneFullCnt) = '0' then
            v.laneFullCnt := r.laneFullCnt + 1;
         end if;




      else
         v.laneDecErrCnt   := (others => '0');
         v.laneOverOccCnt  := (others => '0');
         v.lanePauseCnt    := (others => '0');
         v.lanePauseErrCnt := (others => '0');
         v.laneFullCnt     := (others => '0');

         for i in NUM_OF_SERIALIZERS_C-1 downto 0 loop
            v.colHitmaskCnt(i) := (others => '0');
         end loop;

      end if;



      --for i in NUM_OF_SERIALIZERS_C-1 downto 0 loop



      --      -- update on merger going back to idle
      --      if v.laneValid = '0' and r.laneValid = '1' then

      --         v.laneDecError(i)   := laneStatus(i).decError;
      --         v.laneOverOcc(i)    := laneStatus(i).overOcc;
      --         v.lanePause(i)      := laneStatus(i).pause;
      --         v.lanePauseError(i) := laneStatus(i).pauseError;
      --         v.laneFull(i)       := laneStatus(i).overflow;
      --         v.laneTrgCnt(i)     := laneStatus(i).trgCnt;

      --         if v.laneDecError(i) = '1' and uAnd(r.laneDecErrCnt(i)) = '0' then
      --            v.laneDecErrCnt(i) := r.laneDecErrCnt(i) + 1;
      --         end if;

      --         if v.laneOverOcc(i) = '1' and uAnd(r.laneOverOccCnt(i)) = '0' then
      --            v.laneOverOccCnt(i) := r.laneOverOccCnt(i) + 1;
      --         end if;

      --         if v.lanePause(i) = '1' and uAnd(r.lanePauseCnt(i)) = '0' then
      --            v.lanePauseCnt(i) := r.lanePauseCnt(i) + 1;
      --         end if;

      --         if v.lanePauseError(i) = '1' and uAnd(r.lanePauseErrCnt(i)) = '0' then
      --            v.lanePauseErrCnt(i) := r.lanePauseErrCnt(i) + 1;
      --         end if;

      --         if v.laneFull(i) = '1' and uAnd(r.laneFullCnt(i)) = '0' then
      --            v.laneFullCnt(i) := r.laneFullCnt(i) + 1;
      --         end if;

      --      end if;

      --   else
      --      v.laneDecError(i)   := '0';
      --      v.laneOverOcc(i)    := '0';
      --      v.lanePause(i)      := '0';
      --      v.lanePauseError(i) := '0';
      --      v.laneFull(i)       := '0';
      --      v.laneTrgCnt(i)     := (others => '0');
      --   end if;

      --   if r.cntRst = '1' or config.laneEnable(i) = '0' then
      --      v.laneDecErrCnt(i)   := (others => '0');
      --      v.laneOverOccCnt(i)  := (others => '0');
      --      v.lanePauseCnt(i)    := (others => '0');
      --      v.lanePauseErrCnt(i) := (others => '0');
      --      v.laneFullCnt(i)     := (others => '0');
      --   end if;

      --end loop;
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
         axiSlaveRegisterR(axilEp, toSlv(2048+4*i, 12), 0, r.laneTrgCnt(i));      -- StartAddr=0x800
      end loop;

      axiSlaveRegisterR(axilEp, x"900", 0, fpgaTrgCnt);
      --
      axiSlaveRegister (axilEp, x"A00", 0, v.cntRst);
      --
      axiSlaveRegisterR(axilEp, x"B00", 0, laneDown);
      --
      axiSlaveRegisterR(axilEp, x"C00", 0, r.laneDecError);
      axiSlaveRegisterR(axilEp, x"C04", 0, r.laneOverOcc);
      axiSlaveRegisterR(axilEp, x"C08", 0, r.lanePause);
      axiSlaveRegisterR(axilEp, x"C0C", 0, r.lanePauseError);
      axiSlaveRegisterR(axilEp, x"C10", 0, r.laneFull);

      -- Closeout the transaction
      axiSlaveDefault(axilEp, v.writeSlave, v.readSlave, AXI_RESP_DECERR_C);
      ----------------------------------------------------------------------------------------------

      -- AXI-Lite Outputs
      writeSlave <= r.writeSlave;
      readSlave  <= r.readSlave;

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
