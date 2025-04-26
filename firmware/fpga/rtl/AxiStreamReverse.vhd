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
      TPD_G          : time    := 1 ns;
      RST_ASYNC_G    : boolean := false;
      RST_POLARITY_G : sl      := '1';  -- '1' for active high rst, '0' for active low
      IB_DWIDTH_G    : natural := 40;   -- in bits
      OB_DWIDTH_G    : natural := 320   -- in bits
   );
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

   constant AXI_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C         => false,
      TDATA_BYTES_C      => OB_DWIDTH_G/8,
      TDEST_BITS_C       => 4,
      TID_BITS_C         => 0,
      TKEEP_MODE_C       => TKEEP_NORMAL_C,
      TUSER_BITS_C       => 4,
      TUSER_MODE_C       => TUSER_NORMAL_C);


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
      variable validBytesCnt : integer := 0;
      variable validWordsCnt : integer := 0;
      variable dataBusBytes  : integer := dataBusWidth/8;
      variable wordIndex     : integer := 0;
   begin

      -- how many valid bytes?
      for i in 0 to 127 loop
         if tKeep(i) = '1' then
            validBytesCnt := validBytesCnt + 1;
         end if;
      end loop;

      validWordsCnt := validBytesCnt / dataBusBytes;

      -- Reverse the input order
      for i in 0 to validWordsCnt - 1 loop
         wordIndex := validWordsCnt - 1 - i;
         dout((i * dataBusWidth) + dataBusWidth-1 downto (i * dataBusWidth))
            := din((wordIndex * dataBusWidth) + dataBusWidth-1 downto (wordIndex * dataBusWidth));
      end loop;

        return dout; -- Return the reversed array
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

         -- Check if previous word terminated the frame
         if (r.sAxisMaster.tLast = '1') then
            v.sAxisMaster.tStrb := (others => '0');
            v.sAxisMaster.tKeep := (others => '0');
         end if;

      end if;

      if ibTxMaster.tValid = '1' and
         v.sAxisMaster.tValid   = '0' and
         v.sAxisMaster.tLast    = '0' then

         -- Accept the input word
         v.ibTxSlave.tReady := '1';

         v.sAxisMaster.tValid := ibTxMaster.tValid;
         v.sAxisMaster.tLast  := ibTxMaster.tLast;
         v.sAxisMaster.tKeep  := ibTxMaster.tKeep;
         v.sAxisMaster.tStrb  := ibTxMaster.tStrb;
      end if;

      -- data assignment (reversing)
      v.sAxisMaster.tData := reverse(ibTxMaster.tData, ibTxMaster.tKeep, IB_DWIDTH_G);

      -- Outputs
      ibTxSlave   <= v.ibTxSlave;   -- upstream slave output
      sAxisMaster <= r.sAxisMaster; -- downstream master input

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

   -----------------------------------------
   -- Axi-Stream FIFO
   -----------------------------------------
   U_Fifo : entity surf.AxiStreamFifoV2
      generic map (
         -- General Configurations
         TPD_G               => TPD_G,
         RST_ASYNC_G         => RST_ASYNC_G,
         -- FIFO configurations
         FIFO_ADDR_WIDTH_G   => AXIS_FIFO_WIDTH_C,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => AXI_CONFIG_C,
         MASTER_AXI_CONFIG_G => AXI_CONFIG_C)
      port map (
         -- Slave Port
         sAxisClk    => sysClk,
         sAxisRst    => fifoRst,
         sAxisMaster => sAxisMaster,
         sAxisSlave  => sAxisSlave,
         -- Master Port
         mAxisClk    => sysClk,
         mAxisRst    => fifoRst,
         mAxisMaster => obTxMaster,
         mAxisSlave  => obTxSlave);

   fifoRst <= ite(toBoolean(RST_POLARITY_G), sysRst, not(sysRst));

end rtl;
