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
      TPD_G           : time     := 1 ns;
      RST_ASYNC_G     : boolean  := false;
      RST_POLARITY_G  : sl       := '1'; -- '1' for active high rst, '0' for active low
      LANE_ID_G       : natural  := 0;
      MON_CNT_WIDTH_G : positive := 8);
   port(
      -- General Interface
      pgpRxClk        : in  sl;
      pgpRxRst        : in  sl;
      -- Lane Interface
      laneDown        : in  sl;
      laneStatus      : in  Pix2PgpLaneStatusType;
      config          : in  Pix2PgpStreamRxConfigType;
      -- AXI-Lite Interface (sync'd to pgpRxClk domain)
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType);
end Pix2PgpLaneMon;

architecture rtl of Pix2PgpLaneMon is

   type HitmaskCntArray is array (natural range NUM_OF_COL_MANAGERS_C-1 downto 0) of slv(MON_CNT_WIDTH_G-1 downto 0);

   type RegType is record
      cntRst          : sl;
      laneValid       : sl;
      laneDown        : sl;
      laneStatus      : Pix2PgpLaneStatusType;
      laneDecError    : sl;
      laneOverOcc     : sl;
      lanePause       : sl;
      lanePauseError  : sl;
      laneFull        : sl;
      laneHitmask     : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      -- readback
      laneDecErrCnt   : slv(MON_CNT_WIDTH_G-1 downto 0);
      lanePauseErrCnt : slv(MON_CNT_WIDTH_G-1 downto 0);
      laneFullCnt     : slv(MON_CNT_WIDTH_G-1 downto 0);
      laneOverOccCnt  : slv(MON_CNT_WIDTH_G-1 downto 0);
      lanePauseCnt    : slv(MON_CNT_WIDTH_G-1 downto 0);
      colHitmaskCnt   : HitmaskCntArray;
      -- AXI-Lite
      readSlave       : AxiLiteReadSlaveType;
      writeSlave      : AxiLiteWriteSlaveType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      cntRst          => '1',
      laneValid       => '0',
      laneDown        => '0',
      laneStatus      => DEFAULT_PIX2PGP_LANESTATUS_C,
      laneDecError    => '0',
      laneOverOcc     => '0',
      lanePause       => '0',
      lanePauseError  => '0',
      laneFull        => '0',
      laneHitmask     => (others => '0'),
      -- readback
      laneDecErrCnt   => (others => '0'),
      lanePauseErrCnt => (others => '0'),
      laneFullCnt     => (others => '0'),
      laneOverOccCnt  => (others => '0'),
      lanePauseCnt    => (others => '0'),
      colHitmaskCnt   => (others => (others => '0')),
      -- AXI-Lite
      readSlave       => AXI_LITE_READ_SLAVE_INIT_C,
      writeSlave      => AXI_LITE_WRITE_SLAVE_INIT_C);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   -------------------------------------------------------------------------------------------------
   -------------------------------------------------------------------------------------------------
   comb : process (axilReadMaster, pgpRxRst, axilWriteMaster, laneDown, config,
                   laneStatus, r) is

      variable v : RegType;
      variable axilEp : AxiLiteEndpointType;

      variable laneDecErrCntOverflow   : sl := '0';
      variable lanePauseErrCntOverflow : sl := '0';
      variable laneFullCntOverflow     : sl := '0';
      variable laneOverOccCntOverflow  : sl := '0';
      variable lanePauseCntOverflow    : sl := '0';
      variable colHitmaskCntOverflow   : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');

   begin

      -- Latch the current value
      v := r;

      -- Defaults
      v.cntRst    := '0';
      v.laneDown  := laneDown;

      -- Register the lane status bus
      v.laneStatus := laneStatus;

      v.laneValid      := r.laneStatus.valid;
      v.laneDecError   := r.laneStatus.decError;
      v.laneOverOcc    := r.laneStatus.overOcc;
      v.lanePause      := r.laneStatus.pause;
      v.lanePauseError := r.laneStatus.pauseError;
      v.laneFull       := r.laneStatus.overflow;
      v.laneHitmask    := r.laneStatus.eventHitmask;

      laneDecErrCntOverflow   := uAnd(r.laneDecErrCnt);
      lanePauseErrCntOverflow := uAnd(r.lanePauseErrCnt);
      laneFullCntOverflow     := uAnd(r.laneFullCnt);
      laneOverOccCntOverflow  := uAnd(r.laneOverOccCnt);
      lanePauseCntOverflow    := uAnd(r.lanePauseCnt);

      for i in NUM_OF_COL_MANAGERS_C-1 downto 0 loop
         colHitmaskCntOverflow(i) := uAnd(r.colHitmaskCnt(i));
      end loop;

      ----------------------------------------------------------------------------------------------
      if config.laneEnable(LANE_ID_G) = '1' and r.cntRst = '0' and r.laneDown = '0' then

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

            -- increment column hitmask counter
            for i in NUM_OF_COL_MANAGERS_C-1 downto 0 loop

               if v.laneHitmask(i) = '1' and uAnd(r.colHitmaskCnt(i)) = '0' then
                  v.colHitmaskCnt(i) := r.colHitmaskCnt(i) + 1;
               end if;

            end loop;

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

         for i in NUM_OF_COL_MANAGERS_C-1 downto 0 loop
            v.colHitmaskCnt(i) := (others => '0');
         end loop;

      end if;
      ----------------------------------------------------------------------------------------------

      ----------------------------------------------------------------------------------------------
      -- AXI-Lite Transactions
      ----------------------------------------------------------------------------------------------

      -- Determine the transaction type
      axiSlaveWaitTxn(axilEp, axilWriteMaster, axilReadMaster, v.writeSlave, v.readSlave);

      for i in NUM_OF_COL_MANAGERS_C-1 downto 0 loop
         axiSlaveRegisterR(axilEp, toSlv(4*i, 12), 0, r.colHitmaskCnt(i));   -- StartAddr=0x000
      end loop;
      --
      axiSlaveRegisterR(axilEp, x"A00", 0, r.laneDecErrCnt);
      axiSlaveRegisterR(axilEp, x"A04", 0, r.laneOverOccCnt);
      axiSlaveRegisterR(axilEp, x"A08", 0, r.lanePauseCnt);
      axiSlaveRegisterR(axilEp, x"A0C", 0, r.lanePauseErrCnt);
      axiSlaveRegisterR(axilEp, x"A10", 0, r.laneFullCnt);
      axiSlaveRegisterR(axilEp, x"A14", 0, r.laneDown);
      --
      axiSlaveRegisterR(axilEp, x"A18", 0, laneDecErrCntOverflow);
      axiSlaveRegisterR(axilEp, x"A1C", 0, lanePauseErrCntOverflow);
      axiSlaveRegisterR(axilEp, x"A20", 0, laneFullCntOverflow);
      axiSlaveRegisterR(axilEp, x"A24", 0, laneOverOccCntOverflow);
      axiSlaveRegisterR(axilEp, x"A28", 0, lanePauseCntOverflow);
      axiSlaveRegisterR(axilEp, x"A2C", 0, colHitmaskCntOverflow);
      --
      axiSlaveRegisterR(axilEp, x"A30", 0, toSlv(LANE_ID_G, MON_CNT_WIDTH_G));
      --
      axiSlaveRegister (axilEp, x"B00", 0, v.cntRst);
      --

      -- Closeout the transaction
      axiSlaveDefault(axilEp, v.writeSlave, v.readSlave, AXI_RESP_DECERR_C);
      ----------------------------------------------------------------------------------------------

      -- AXI-Lite Outputs
      axilWriteSlave <= r.writeSlave;
      axilReadSlave  <= r.readSlave;

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
