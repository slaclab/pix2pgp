-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp Package
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

package Pix2PgpPkg is

   -- pretty much fixed
   constant NUM_OF_COL_MANAGERS_C : natural := 24;
   constant BITMAX_COL_MANAGERS_C : natural := bitSize(NUM_OF_COL_MANAGERS_C)-1;

   -- sparse/matrix-related
   constant ADC_DWIDTH_C    : natural := 10;
   constant PIXADDR_WIDTH_C : natural := 10;
   constant SPARSE_DWIDTH_C : natural := ADC_DWIDTH_C + PIXADDR_WIDTH_C;

   -- ColumnManager-related
   constant DATALEN_WIDTH_C  : natural := 10; -- 672 pixels max (TO-DO: make this dynamic)
   -- data bus
   constant DATABUS_WIDTH_C : natural := SPARSE_DWIDTH_C;

   -- status FIFO bus
   -- does not have the same width as the whole status bus;
   -- *only* the overOcc flag, the trigger number and the dataLen are stored into the FIFO
   -- the other flags (dataFull/statusFull/statusEmpty) run parallel the FIFO dout on the status bus
   constant STATUSFIFO_TRG_WIDTH_C   : natural := 8; -- this number is coupled with the overall PGP frame size
   constant STATUSFIFO_DWIDTH_C      : natural := DATALEN_WIDTH_C + STATUSFIFO_TRG_WIDTH_C + 1;

   constant STATUSFIFO_OVEROCC_POS_C : natural := STATUSFIFO_DWIDTH_C-1;

   subtype STATUSFIFO_TRG_POS_C     is natural range STATUSFIFO_DWIDTH_C-2
                                           downto DATALEN_WIDTH_C;

   subtype STATUSFIFO_DATALEN_POS_C is natural range DATALEN_WIDTH_C-1
                                           downto 0;

   type Pix2PgpStatusBusType is record
      -- flags begin
      overOcc     : sl;
      dataFull    : sl;
      statusFull  : sl;
      statusEmpty : sl;
      -- flags end
      trgNum      : slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0);
      dataLen     : slv(DATALEN_WIDTH_C-1 downto 0);
   end record;

   constant DEFAULT_PIX2PGP_STATUSBUS_C : Pix2PgpStatusBusType := (
      -- flags begin
      overOcc     => '0',
      dataFull    => '0',
      statusFull  => '0',
      statusEmpty => '1',
      -- flags end
      trgNum      => (others => '1'), -- so that the first trigger rolls-over to zero
      dataLen     => (others => '0'));

   type Pix2PgpStatusBusArray is array (NUM_OF_COL_MANAGERS_C-1 downto 0) of Pix2PgpStatusBusType;

   type Pix2PgpDataBusType is record
      -- flags begin
      data : slv(SPARSE_DWIDTH_C-1 downto 0);
   end record;

   constant DEFAULT_PIX2PGP_DATABUS_C : Pix2PgpDataBusType := (
      data => (others => '0'));

   type Pix2PgpDataBusArray is array (NUM_OF_COL_MANAGERS_C-1 downto 0) of Pix2PgpDataBusType;

   ----------------------------
   -- Pix2Pgp data frame header
   ----------------------------

   -- the Pix2Pgp data frame header *has* to be an interger-multiple of the sparse data width
   constant HEADER_DWITDH_C     : natural := 2*SPARSE_DWIDTH_C;
   -- constant STATUSFIFO_TRG_WIDTH_C : natural := 8;               -- 8
   constant FLAGS_WIDTH_C       : natural := 8;                     -- 8
   constant COL_BITMASK_WIDTH_C : natural := NUM_OF_COL_MANAGERS_C; -- 24
   -- 8+8+24=40 -> 2*SPARSE_DWIDTH_C

   ---------------------------------------------
   -- Pix2Pgp data frame header bitmapping begin
   ---------------------------------------------
   constant OVEROCC_FLAG_POS_C      : natural := HEADER_DWITDH_C-1;
   constant DATA_FULL_FLAG_POS_C    : natural := HEADER_DWITDH_C-2;
   constant STATUS_FULL_FLAG_POS_C  : natural := HEADER_DWITDH_C-3;
   constant TRG_ALIGN_ERROR_POS_C   : natural := HEADER_DWITDH_C-4;
   constant TIMEOUT_HEADER_POS_C    : natural := HEADER_DWITDH_C-5;
   -- reserved bits
   subtype  FLAGS_RESERVED_POS_C   is natural range  HEADER_DWITDH_C-6
                                              downto HEADER_DWITDH_C-8;
   -- col-bitmask
   subtype  COL_BITMASK_POS_C      is natural range  HEADER_DWITDH_C-9
                                              downto STATUSFIFO_TRG_WIDTH_C;
   -- trigger counter
   subtype  TRG_CNT_POS_C          is natural range  STATUSFIFO_TRG_WIDTH_C-1
                                              downto 0;
   -------------------------------------------
   -- Pix2Pgp data frame header bitmapping end
   -------------------------------------------

   -- and finally, the Pix2Pgp data frame data also have to be related to the sparse data width
   -- the receiver can deduce which columns have data from the bitmask
   -- and it can also deduce how many data by appending the dataLen before each seq of hits

   -- examples of the final pix2pgp frame format:
   -- e.g. 1: this event has 2 hits from two different cols (cols 0 and 5)
   -- pgp data frame header | col0_dataLen | col0_hit0 | col5_dataLen | col5_hit0
   -- e.g. 2: this event has 3 hits from one column (col 2)
   -- pgp data frame header | col2_dataLen | col2_hit0 | col2_hit1 | col2_hit2

   -- if the gearbox input data width is 20-bit wide, it makes it very fast to parse the data in;
   -- (SPARSE_DWIDTH_C = 20)
   -- convenient, since the frame header is 40-bit wide, so it can be parsed-in in two clock cycles
   -- unfortunately, the dataLen is 10-bit wide, so have to pad it and lose 10 bits per column

   constant ARB_GEARBOX_INPUT_WIDTH_G  : natural := 20;

   -- functions
   function selRange (inputBusLen : positive; lenRatio : positive; sel : slv; isLow : boolean) return integer;
   function selBus (inputBus : slv; lenRatio : positive; sel : slv) return slv;

end Pix2PgpPkg;

package body Pix2PgpPkg is

   function selRange (inputBusLen : positive; lenRatio : positive; sel : slv; isLow : boolean) return integer is
      variable low          : integer;
      variable high         : integer;
      variable retVar       : integer;
   begin
      high   := inputBusLen - 1 - lenRatio*conv_integer(unsigned(sel));
      low    := inputBusLen - LenRatio*(conv_integer(unsigned(sel))+1);
      retVar := high;
      report "sel" & integer'image(conv_integer(unsigned(sel)));
      report "LOW=" & integer'image(low);
      report "HIGH=" & integer'image(high);
      if isLow then
         retVar := low;
      end if;
      return retVar;
   end;

   function selBus (inputBus : slv; lenRatio : positive; sel : slv) return slv is
      variable low    : integer;
      variable high   : integer;
      variable retBus : slv(19 downto 0);
   begin
      low    := selRange(inputBus'length, lenRatio, sel, True);
      high   := selRange(inputBus'length, lenRatio, sel, False);
      retBus := inputBus(high downto low);
      return retBus;
   end;

end package body Pix2PgpPkg;
