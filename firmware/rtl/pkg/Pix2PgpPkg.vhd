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

   -- ASIC-specific
   constant NUM_OF_COL_MANAGERS_C : natural := 24;
   constant BITMAX_COL_MANAGERS_C : natural := bitSize(NUM_OF_COL_MANAGERS_C)-1;
   constant NUM_OF_SERIALIZERS_C  : natural := 8;
   constant BITMAX_SERIALIZERS_C  : natural := bitSize(NUM_OF_SERIALIZERS_C)-1;

   -- sparse/matrix-related (also ASIC-specific)
   constant ADC_DWIDTH_C    : natural := 10;
   constant PIXADDR_WIDTH_C : natural := 10;
   constant SPARSE_DWIDTH_C : natural := ADC_DWIDTH_C + PIXADDR_WIDTH_C;

   type Pix2PgpSparseDinArray is array (NUM_OF_COL_MANAGERS_C-1 downto 0) of slv(SPARSE_DWIDTH_C-1 downto 0);

   -- ColumnManager-related
   constant DATALEN_WIDTH_C  : natural := 10; -- 672 pixels max (TO-DO: make this dynamic)
   -- data bus width is twice the pixel data width;
   -- to maximize bandwidth
   constant DATABUS_DWIDTH_C : natural := SPARSE_DWIDTH_C*2;

   constant PGP_DWIDTH_C     : natural := 64;

   -- status FIFO bus
   -- does not have the same width as the whole status bus;
   -- *only* the overOcc flag, the trigger number and the dataLen are stored into the FIFO
   -- the other flags (columnFull/columnEmpty) run parallel the FIFO dout on the status bus
   constant STATUSFIFO_TRG_WIDTH_C   : natural := 8; -- this number is coupled with the overall PGP frame size

   -- status fifo data width is +2 because of the overoccupancy and pause flags
   constant STATUSFIFO_DWIDTH_C      : natural := DATALEN_WIDTH_C + STATUSFIFO_TRG_WIDTH_C + 2;

   constant STATUSFIFO_OVEROCC_POS_C : natural := STATUSFIFO_DWIDTH_C-1;
   constant STATUSFIFO_PAUSE_POS_C   : natural := STATUSFIFO_DWIDTH_C-2;

   subtype STATUSFIFO_TRG_POS_C     is natural range STATUSFIFO_DWIDTH_C-3
                                               downto DATALEN_WIDTH_C;

   subtype STATUSFIFO_DATALEN_POS_C is natural range DATALEN_WIDTH_C-1
                                               downto 0;

   type Pix2PgpStatusBusType is record
      -- flags begin
      overOcc     : sl;
      pause       : sl;
      columnFull  : sl;
      columnEmpty : sl;
      -- flags end
      trgNum      : slv(STATUSFIFO_TRG_WIDTH_C-1 downto 0);
      dataLen     : slv(DATALEN_WIDTH_C-1 downto 0);
   end record;

   constant DEFAULT_PIX2PGP_STATUSBUS_C : Pix2PgpStatusBusType := (
      -- flags begin
      overOcc     => '0',
      pause       => '0',
      columnFull  => '0',
      columnEmpty => '1',
      -- flags end
      trgNum      => (others => '1'), -- so that the first trigger rolls-over to zero
      dataLen     => (others => '0'));

   type Pix2PgpStatusBusArray is array (NUM_OF_COL_MANAGERS_C-1 downto 0) of Pix2PgpStatusBusType;

   type Pix2PgpDataBusType is record
      -- flags begin
      data : slv(DATABUS_DWIDTH_C-1 downto 0);
   end record;

   constant DEFAULT_PIX2PGP_DATABUS_C : Pix2PgpDataBusType := (
      data => (others => '0'));

   type Pix2PgpDataBusArray is array (NUM_OF_COL_MANAGERS_C-1 downto 0) of Pix2PgpDataBusType;

   ----------------------------
   -- Pix2Pgp data frame header
   ----------------------------

   -- the Pix2Pgp data frame header *has* to be an interger-multiple of the databus width
   constant HEADER_DWITDH_C     : natural := DATABUS_DWIDTH_C;
   -- constant STATUSFIFO_TRG_WIDTH_C : natural := 8;               -- 8
   constant FLAGS_WIDTH_C       : natural := 8;                     -- 8
   constant COL_BITMASK_WIDTH_C : natural := NUM_OF_COL_MANAGERS_C; -- 24
   -- 8+8+24=40 -> DATABUS_DWIDTH_C=2*SPARSE_DWIDTH_C

   ---------------------------------------------
   -- Pix2Pgp data frame header bitmapping begin
   ---------------------------------------------
   constant OVEROCC_FLAG_POS_C     : natural := HEADER_DWITDH_C-1;
   constant PAUSE_FLAG_POS_C       : natural := HEADER_DWITDH_C-2;
   constant COLUMN_FULL_FLAG_POS_C : natural := HEADER_DWITDH_C-3;
   constant TRG_ALIGN_ERROR_POS_C  : natural := HEADER_DWITDH_C-4;
   constant DUMMY_HEADER_POS_C     : natural := HEADER_DWITDH_C-5;
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
   -- the receiver can deduce which columns have data from the bitmask
   -- and it can also deduce how many data by reading the dataLen before each seq of hits

   -- examples of the final pix2pgp frame format:
   -- e.g. 1: this event has 2 hits from two different cols (cols 0 and 5)
   -- pgp data frame header | col0_dataLen | col0_hit0 | col5_dataLen | col5_hit0
   -- e.g. 2: this event has 3 hits from one column (col 2)
   -- pgp data frame header | col2_dataLen | col2_hit0 | col2_hit1 | col2_hit2

   -- note that because the datalength is 40-bit, the colX_dataLen word is padded with zeros;
   -- (on the MSB)

   -- also, if a column yielded odd number of events, the last hit will have an extra 20-bit padding
   -- at the end; the receiver will ignore it since it knows the true event dataLen from that col

   constant GEARBOX_OUTPUT_WIDTH_C  : natural := DATABUS_DWIDTH_C*8;

end Pix2PgpPkg;

package body Pix2PgpPkg is

end package body Pix2PgpPkg;
