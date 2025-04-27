-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp Lane Adapter; converts lane data to AXI-Stream
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

entity Pix2PgpLaneAdapter is
   generic(
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1'  -- '1' for active high rst, '0' for active low
   );
   port(
      -- General Interface
      sysClk         : in  sl;
      sysRst         : in  sl := not(RST_POLARITY_G);
      -- Lane Interface
      frameDataRd    : out sl;
      frameDataDout  : in  slv(ASIC_DATABUS_DWIDTH_C-1 downto 0);
      frameDataFull  : in  sl;
      frameDataValid : in  sl;
      frameMetaRd    : out sl;
      frameMetaDout  : in  slv(LANERX_FRAMELEN_BUFF_WIDTH_C-1 downto 0);
      frameMetaValid : in  sl;
      -- ASIC Rx Interface
      laneError      : out sl;
      laneErrorAck   : in  sl;
      laneTxMaster   : out AxiStreamMasterType;
      laneTxSlave    : in  AxiStreamSlaveType);
end Pix2PgpLaneAdapter;

architecture rtl of Pix2PgpLaneAdapter is

   -- delay between reading of FIFO and writing into bus
   constant WRITE_DELAY_C : natural := 0;

   -- axi-stream gearbox configuration
   constant SLAVE_AXI_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C    => false,
      TDATA_BYTES_C => ASIC_DATABUS_DWIDTH_C/8,
      TDEST_BITS_C  => 4,
      TID_BITS_C    => 0,
      TKEEP_MODE_C  => TKEEP_NORMAL_C,
      TUSER_BITS_C  => 4,
      TUSER_MODE_C  => TUSER_NORMAL_C);

   -- note that the bus becomes wider to have enough bandwidth to read-out all lanes fast enough
   constant MASTER_AXI_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C    => false,
      TDATA_BYTES_C => FPGA_DATABUS_DWIDTH_C/8,
      TDEST_BITS_C  => 4,
      TID_BITS_C    => 0,
      TKEEP_MODE_C  => TKEEP_NORMAL_C,
      TUSER_BITS_C  => 4,
      TUSER_MODE_C  => TUSER_NORMAL_C);

   type StateType is (
      IDLE_S,
      PARSE_FRAME_S,
      ERROR_S);

   type RegType is record
      laneError   : sl;
      frameLen    : slv(LANERX_FRAMELEN_WIDTH_C-1 downto 0);
      frameMetaRd : sl;
      frameDataRd : sl;
      dataRdCnt   : slv(LANERX_FRAMELEN_WIDTH_C-1 downto 0);
      dataWrCnt   : slv(LANERX_FRAMELEN_WIDTH_C-1 downto 0);
      sAxisMaster : AxiStreamMasterType;
      sAxisSlave  : AxiStreamSlaveType;
      state       : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      laneError   => '0',
      frameLen    => (others => '0'),
      frameMetaRd => '0',
      frameDataRd => '0',
      dataRdCnt   => (others => '0'),
      dataWrCnt   => (others => '0'),
      sAxisMaster => AXI_STREAM_MASTER_INIT_C,
      sAxisSlave  => AXI_STREAM_SLAVE_INIT_C,
      state       => IDLE_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   -- reset via the variables
   signal sAxisMaster : AxiStreamMasterType;
   signal sAxisSlave  : AxiStreamSlaveType;

begin

   comb : process (r, sysRst, frameDataFull, laneErrorAck, frameMetaDout,
                   frameMetaValid, frameDataValid, sAxisSlave) is

      -- omnipresent
      variable v : RegType;

      -- various data fields encoded in variables; are used in data checks and FSM flow control

      -- header
      variable decError : sl := '0';
      variable frameLen : slv(LANERX_FRAMELEN_WIDTH_C-1 downto 0) := (others => '0');

   begin

      -- Latch the current value
      v := r;

      -- Register inputs
      v.sAxisSlave := sAxisSlave;

      -- variables
      decError := frameMetaDout(frameMetaDout'length-1);
      frameLen := frameMetaDout(frameMetaDout'length-2 downto 0);

      -- Defaults
      v.frameMetaRd := '0';
      v.frameDataRd := '0';

      -- data-write counter before flow control check
      if sAxisMaster.tValid = '1' and sAxisSlave.tReady = '1' then
         v.dataWrCnt := r.dataWrCnt + 1;
      end if;

      -- flow control check
      if v.sAxisSlave.tReady = '1' then
         v.sAxisMaster.tValid := '0';
         v.sAxisMaster.tLast  := '0';
         v.sAxisMaster.tUser  := (others => '0');
      end if;

      -- default flags
      v.sAxisMaster.tKeep := (others => '1');
      ---------------------------------------------------------------------------
      case r.state is
      ---------------------------------------------------------------------------
         -- stay here until a valid metadata value is available
         when IDLE_S =>
            v.dataRdCnt := (others => '0');
            v.dataWrCnt := (others => '0');

            if frameMetaValid = '1' then
               v.frameLen    := frameLen; -- register the frame length
               v.laneError   := decError; -- register the decoding error
               v.frameMetaRd := '1';      -- pop the word out
               v.state       := PARSE_FRAME_S;

               -- override in case of error
               if decError = '1' then
                  v.state := ERROR_S;
               end if;
            end if;

         ----------------------------------------------------------------------
         -- parse lane data
         when PARSE_FRAME_S =>
            if v.sAxisMaster.tValid = '0' then

               v.dataRdCnt   := r.dataRdCnt + 1;
               v.frameDataRd := '1';
               v.sAxisMaster.tValid := '1';

               -- FIFO data have all been read
               if r.dataRdCnt = r.frameLen then
                  v.frameDataRd := '0';
                  v.dataRdCnt   := r.dataRdCnt;
               end if;

               -- dataWrCnt incremented by another sub-process
               -- first frame -> SoF
               if r.dataWrCnt = 0 then
                  v.sAxisMaster.tUser(1) := '1';
               end if;

               -- done writing
               if r.dataWrCnt = r.frameLen-1  and
                  sAxisSlave.tReady     = '1' then
                  --
                  v.sAxisMaster.tLast := '1';
                  v.state := IDLE_S;
               end if;

            end if;

         ----------------------------------------------------------------------
         -- report the error further upstream until acknowledged
         when ERROR_S =>
            if laneErrorAck = '1' then
               v.laneError := '0';
               v.state     := IDLE_S;
            end if;

      end case;
      ---------------------------------------------------------------------------

      -- Outputs
      frameMetaRd <= r.frameMetaRd;
      frameDataRd <= r.frameDataRd;
      laneError   <= r.laneError;

      -- All except for the data
      sAxisMaster.tValid <= r.sAxisMaster.tValid;
      sAxisMaster.tStrb  <= r.sAxisMaster.tStrb;
      sAxisMaster.tKeep  <= r.sAxisMaster.tKeep;
      sAxisMaster.tLast  <= r.sAxisMaster.tLast;
      sAxisMaster.tDest  <= r.sAxisMaster.tDest;
      sAxisMaster.tId    <= r.sAxisMaster.tId;
      sAxisMaster.tUser  <= r.sAxisMaster.tUser;

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

   U_PipelineAxiDin : entity surf.SlvDelay
      generic map (
         TPD_G          => TPD_G,
         RST_POLARITY_G => RST_POLARITY_G,
         WIDTH_G        => ASIC_DATABUS_DWIDTH_C,
         DELAY_G        => WRITE_DELAY_C)
      port map (
         clk  => sysClk,
         din  => frameDataDout,
         dout => sAxisMaster.tData(ASIC_DATABUS_DWIDTH_C-1 downto 0));

   -----------------------------------------
   -- Axi-Stream Gearbox (1-to-8)
   -----------------------------------------
   U_Gearbox : entity surf.AxiStreamGearbox
      generic map(
         -- General Configurations
         TPD_G               => TPD_G,
         RST_POLARITY_G      => RST_POLARITY_G,
         RST_ASYNC_G         => RST_ASYNC_G,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => SLAVE_AXI_CONFIG_C,
         MASTER_AXI_CONFIG_G => MASTER_AXI_CONFIG_C)
      port map(
         -- Clock and reset
         axisClk     => sysClk,
         axisRst     => sysRst,
         -- Slave Port
         sAxisMaster => sAxisMaster,
         sSideBand   => (others => '0'),
         sAxisSlave  => sAxisSlave,
         -- Master Port
         mAxisMaster => laneTxMaster,
         mSideBand   => open,
         mAxisSlave  => laneTxSlave);

end rtl;
