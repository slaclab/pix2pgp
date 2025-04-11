-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp Single-Lane Receiver
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

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity Pix2PgpLaneRx is
   generic(
      TPD_G          : time     := 1 ns;
      RST_ASYNC_G    : boolean  := false;
      RST_POLARITY_G : sl       := '1'  -- '1' for active high rst, '0' for active low
   );
   port(
      -- General Interface
      pgpClk   : in  sl;
      pgpRst   : in  sl := not(RST_POLARITY_G);
      sysClk   : in  sl;
      sysRst   : in  sl := not(RST_POLARITY_G);
      -- RX FIFO Interface
      pgpValid : in  sl;
      pgpData  : in  slv(DATABUS_DWIDTH_C-1 downto 0);
      pgpReady : out sl;
      -- Framer Interface
      ready    : out sl;
      noHits   : out sl;
      colHits  : out slv(BITMAX_COL_MANAGERS_C-1 downto 0);
      ibValid  : in  sl;
      dout     : out slv(DWIDTH_G-1 downto 0);
      obValid  : out sl
   );
end Pix2PgpLaneRx;

architecture rtl of Pix2PgpLaneRx is

   type RegType is record
      din      : slv(DWIDTH_G-1 downto 0);
      ibValid  : sl;
      dout     : slv(DWIDTH_G-1 downto 0);
      obValid  : sl;
      flag     : sl;
   end record RegType;

   constant REG_INIT_C : RegType := (
      din      => (others => '0'),
      ibValid  => '0',
      dout     => (others => '0'),
      obValid  => '0',
      flag     => '0'
   );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   -----------------------------
   -- First Buffer Level
   -----------------------------
   U_protoBuffer : entity surf.Fifo
      generic map (
         TPD_G           => TPD_G,
         GEN_SYNC_FIFO_G => false, -- false = dual-clock FIFO
         MEMORY_TYPE_G   => "block",
         FWFT_EN_G       => true,
         DATA_WIDTH_G    => DATABUS_DWIDTH_C,
         ADDR_WIDTH_G    => 4)
      port map (
         rst      => sysRst,
         -- Write Ports
         wr_clk   => pgpClk,
         wr_en    => pgpValid,
         din      => pgpData,
         overflow => pgpFull,
         -- Read Ports
         rd_clk   => sysClk,
         rd_en    => protoBufValid, -- always stream data
         dout     => protoBufDout,
         valid    => protoBufValid);

   U_SyncFull : entity surf.Synchronizer
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         RST_ASYNC_G    => RST_ASYNC_G)
      port map (
         clk     => sysClk,
         dataIn  => pgpFull,
         dataOut => pgpFullSync);

   comb : process (r, rst, protoBufDout, protoBufValid, pgpFull, pgpFullSync) is

      -- omnipresent
      variable v : RegType;

      -- various data fields encoded in variables; are used in data checks and FSM flow control

      -- header
      variable overOcc    : sl := '0';
      variable pause      : sl := '0';
      variable colError   : sl := '0';
      variable pauseError : sl := '0';
      variable timeout    : sl := '0';
      variable colBitmask : slv(NUM_OF_COL_MANAGERS_C-1 downto 0) := (others => '0');
      variable trgCnt     : slv(TRGCNT_WIDTH_C-1 downto 0)        := (others => '0');

      -- column metadata
      variable metaTrgCnt  : slv(7 downto 0) := (others => '0');
      variable metaDataLen : slv(7 downto 0) := (others => '0');

   begin

      -- Latch the current value
      v := r;

      -- Register inputs
      v.protoBufDout  := protoBufDout;
      v.protoBufValid := protoBufValid;

      -- Defaults
      v.frameLenWr := '0';
      v.decError   := '1';

      -- First layer of dataRx
      v.din   := r.protoBufDout; -- register the data
      v.valid := '0';            -- disable by default; enable one level below

      if r.protoBufValid = '1' and r.waitHeader = '0' then
         v.valid := '1';
      elsif r.protoBufValid = '1' and r.waitHeader = '1' and not(isDummy(r.protoBufDout)) then
         v.valid := '1';
      end if;

      -- header variables
      overOcc     := r.din(OVEROCC_FLAG_POS_C);
      pause       := r.din(PAUSE_FLAG_POS_C);
      colError    := r.din(COLUMN_ERROR_FLAG_POS_C);
      pauseError  := r.din(PAUSE_ERROR_FLAG_POS_C);
      timeout     := r.din(TIMEOUT_FLAG_POS_C);
      colBitmask  := r.din(COL_BITMASK_POS_C);
      trgCnt      := r.din(TRG_CNT_POS_C);
      -- column metadata variables
      metaTrgCnt  := r.din(META_TRG_CNT_POS_C);
      metaDataLen := r.din(META_DATALEN_POS_C);

      if r.frameLenWr = '1' then
         v.frameLenCnt := (others => '0');
      elsif r.valid = '1' then
         v.frameLenCnt := r.frameLenCnt + 1;
      end if;

      ---------------------------------------------------------------------------
      case r.state is
      ---------------------------------------------------------------------------
         -- stay here until a valid header comes in
         when WAIT_HEADER_S =>
            if r.valid = '1' then
               v.inPause := pause;

               if allBits(colBitmask) = '0' then
                  v.frameLenWr   := '1'; -- close data frame
               else
                  v.waitHeader   := '0';
                  v.trgCntHeader := trgCnt;
                  v.activeColCnt := onesCount(colBitmask);
                  v.state        := PARSE_DATA_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- parse column metadata;
         when PARSE_COL_METADATA_S =>
            if r.valid = '1' then

               -- still more columns to go
               if r.activeColCnt > 0 then
                  -- data check
                  if metaTrgCnt /= r.trgCntHeader or
                     metaDataLen >= leftShift(1, DATALEN_WIDTH_C) then
                     v.decError   := '1';
                     v.frameLenWr := '1';
                     v.waitHeader := '1';
                     v.state      := WAIT_HEADER_S;
                  end if;

                  v.activeColCnt := r.activeColCnt - 1;
                  v.dataLenCnt   := metaDataLen;
                  v.state        := PARSE_DATA_S;
               else
                  v.waitHeader := '1';
                  v.state      := WAIT_HEADER_S;
                  if r.inPause := '0' then
                     v.frameLenWr := '1'; -- close data frame
                  end if;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- parse column data;
         when PARSE_DATA_S =>
            if r.valid = '1' then
               -- data parsing
               if r.dataLenCnt > 1 then
                  v.dataLenCnt := r.dataLenCnt - 2;
               else
                  v.state := PARSE_COL_METADATA_S;
               end if;
            end if;

      end case;
      ---------------------------------------------------------------------------

      -- Outputs
      pgpReady <= not(pgpFull); -- not registered

      -- Reset
      if (RST_ASYNC_G = false and sysRst = RST_POLARITY_G) then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

   end process comb;

   seq : process (sysClk, sysRst) is
   begin
      if (RST_ASYNC_G and sysRst = RST_POLARITY_G) then
         r <= REG_INIT_C after TPD_G;
      elsif rising_edge(sysClk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

   -- TO-DO TO-DO
   -- v.frameLenWr must arrive a bit later than the data
   --v.tkeep      := lsbSet(DATABUS_DWIDTH_C/8, AXI_STREAM_MAX_TKEEP_WIDTH_C);
   -- move tkeep later in the chain

end rtl;
