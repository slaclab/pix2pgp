-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Reverses the endinanness of words within an AXI-stream bus
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

entity AxiStreamReverse is
   generic(
      TPD_G             : time    := 1 ns;
      RST_ASYNC_G       : boolean := false;
      RST_POLARITY_G    : sl      := '1';  -- '1' for active high rst, '0' for active low
      PIPE_STAGES_G     : natural := 1;
      IB_DWIDTH_G       : natural := 5;   -- in bytes
      OB_DWIDTH_G       : natural := 40); -- in bytes
   port(
      -- General Interface
      sysClk     : in  sl;
      sysRst     : in  sl := not(RST_POLARITY_G);
      -- Inbound Interface
      ibTxMaster : in  AxiStreamMasterType;
      ibTxSlave  : out AxiStreamSlaveType;
      -- Outbound Interface
      obTxMaster : out AxiStreamMasterType;
      obTxSlave  : in  AxiStreamSlaveType);
end AxiStreamReverse;

architecture rtl of AxiStreamReverse is

   type RegType is record
      sAxisMaster : AxiStreamMasterType;
      ibTxSlave   : AxiStreamSlaveType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      sAxisMaster => AXI_STREAM_MASTER_INIT_C,
      ibTxSlave   => AXI_STREAM_SLAVE_INIT_C);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   -- reset via the variables
   signal sAxisMaster : AxiStreamMasterType;
   signal sAxisSlave  : AxiStreamSlaveType;

   signal fifoRst     : sl := '0';

   function reverse(din : slv; tKeep : slv; dataBusWidth : natural) return slv is
      variable dout          : slv(AXI_STREAM_MAX_TDATA_WIDTH_C-1 downto 0) := (others => '0');
      variable tKeepBytesCnt : integer := 0;
      variable validWordsCnt : integer := 0;
      variable wordIndex     : integer := 0;
      variable dataBusBits   : integer := dataBusWidth * 8; -- Calculate bits from bytes
   begin

      tKeepBytesCnt := conv_integer(unsigned(onesCount(tKeep)));

      -- always check if the tKeep has a valid value for this conversion

      if tKeepBytesCnt mod dataBusWidth = 0 then
         -- Calculate the number of valid words
         validWordsCnt := tKeepBytesCnt / dataBusWidth;

         -- Reverse the input order
         for i in 0 to validWordsCnt - 1 loop
            wordIndex := validWordsCnt - 1 - i;
            dout((i*dataBusBits) + dataBusBits - 1 downto (i*dataBusBits))
               := din((wordIndex*dataBusBits) + dataBusBits - 1 downto (wordIndex*dataBusBits));
         end loop;

      else
         dout := resize(din, din'length);
      end if;

      return dout;

   end function reverse;

begin

   comb : process (r, sysRst, sAxisSlave, ibTxMaster) is

      -- omnipresent
      variable v : RegType;
   begin

      -- Latch the current value
      v := r;

      -- Flow Control
      v.ibTxSlave.tReady := '0';

      if sAxisSlave.tReady = '1' then

         v.sAxisMaster.tValid := '0';
         v.sAxisMaster.tLast  := '0';
         v.sAxisMaster.tUser  := (others => '0');
         v.sAxisMaster.tKeep  := (others => '1');

      end if;

      if v.sAxisMaster.tValid = '0' then
         -- Accept the input word
         v.ibTxSlave.tReady   := sAxisSlave.tReady;

         v.sAxisMaster.tUser  := ibTxMaster.tUser;
         v.sAxisMaster.tValid := ibTxMaster.tValid;
         v.sAxisMaster.tLast  := ibTxMaster.tLast;
         v.sAxisMaster.tKeep  := ibTxMaster.tKeep;
         v.sAxisMaster.tStrb  := ibTxMaster.tStrb;
         v.sAxisMaster.tId    := ibTxMaster.tId;
      end if;

      -- data assignment (reversing)
      v.sAxisMaster.tData := revEndian(ibTxMaster.tData, ibTxMaster.tKeep, OB_DWIDTH_G, IB_DWIDTH_G);

      -- Outputs
      ibTxSlave   <= v.ibTxSlave;   -- upstream slave output
      sAxisMaster <= v.sAxisMaster; -- downstream master input

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

   --------------------------
   -- Pipeline Stage (or not)
   --------------------------
   GEN_PIPE: if PIPE_STAGES_G > 0 generate
      U_Pipe : entity surf.AxiStreamPipeline
         generic map (
            TPD_G          => TPD_G,
            RST_ASYNC_G    => RST_ASYNC_G,
            RST_POLARITY_G => RST_POLARITY_G,
            PIPE_STAGES_G  => PIPE_STAGES_G)
         port map (
            -- Clock and Reset
            axisClk     => sysClk,
            axisRst     => sysRst,
            -- Slave Port
            sAxisMaster => sAxisMaster,
            sAxisSlave  => sAxisSlave,
            -- Master Port
            mAxisMaster => obTxMaster,
            mAxisSlave  => obTxSlave);
   end generate GEN_PIPE;

   GEN_NO_PIPE: if PIPE_STAGES_G <= 0 generate
      sAxisSlave <= obTxSlave;
      obTxMaster <= sAxisMaster;
   end generate GEN_NO_PIPE;

end rtl;
