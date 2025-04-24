-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp Package for SparkPix-S
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
   -- even though we have 672 pixels max, DATALEN_WIDTH_C should be less than 10 (10 bits fit 672);
   -- this is because the dataLength for a single event can never reach 672;
   -- the data FIFO cannot accommodate for that amount of hits.
   -- so the true data length can only be smaller than the hits the data FIFO can fit.
   -- after hitting almost-full, the data FIFO will get drained...
   -- ...therefore
   constant DATALEN_WIDTH_C : natural := 5; -- 2^5=31 hits max before almost-full/pause

   constant TRGCNT_WIDTH_C  : natural := 6; -- 6-bit counter to double-check alignment

   -- data bus width is twice the pixel data width;
   -- to maximize bandwidth
   constant ASIC_DATABUS_DWIDTH_C : natural := SPARSE_DWIDTH_C*2;

   constant PGP_DWIDTH_C : natural := 64;
   constant SER_DWIDTH_C : natural := 32;

   -- status FIFO bus
   -- does not have the same width as the whole status bus;
   -- *only* the overOcc flag, the pause, the trgCnt, and the dataLen are stored into the FIFO
   -- the other flags (fifoError/columnEmpty) run parallel the FIFO dout on the status bus

   -- status fifo data width is + 2 because of the overoccupancy and pause flags
   constant STATUSFIFO_DWIDTH_C       : natural := DATALEN_WIDTH_C + TRGCNT_WIDTH_C + 2;

   constant STATUSFIFO_OVEROCC_POS_C  : natural := STATUSFIFO_DWIDTH_C-1;
   constant STATUSFIFO_PAUSE_POS_C    : natural := STATUSFIFO_DWIDTH_C-2;

   subtype STATUSFIFO_TRGCNT_POS_C   is natural range STATUSFIFO_DWIDTH_C-3
                                                downto DATALEN_WIDTH_C;

   subtype STATUSFIFO_DATALEN_POS_C  is natural range DATALEN_WIDTH_C-1
                                                downto 0;

   type Pix2PgpStatusBusType is record
      -- flags begin
      overOcc     : sl;
      pause       : sl;
      fifoError   : sl;
      columnEmpty : sl;
      -- flags end
      trgCnt      : slv(TRGCNT_WIDTH_C-1 downto 0);
      dataLen     : slv(DATALEN_WIDTH_C-1 downto 0);
   end record;

   constant DEFAULT_PIX2PGP_STATUSBUS_C : Pix2PgpStatusBusType := (
      -- flags begin
      overOcc     => '0',
      pause       => '0',
      fifoError   => '0',
      columnEmpty => '1',
      -- flags end
      trgCnt      => (others => '1'),
      dataLen     => (others => '0'));

   type Pix2PgpStatusBusArray is array (NUM_OF_COL_MANAGERS_C-1 downto 0) of Pix2PgpStatusBusType;

   type Pix2PgpDataBusType is record
      -- flags begin
      data : slv(ASIC_DATABUS_DWIDTH_C-1 downto 0);
   end record;

   constant DEFAULT_PIX2PGP_DATABUS_C : Pix2PgpDataBusType := (
      data => (others => '0'));

   type Pix2PgpDataBusArray is array (NUM_OF_COL_MANAGERS_C-1 downto 0) of Pix2PgpDataBusType;

   ----------------------------
   -- Pix2Pgp data frame header
   ----------------------------

   -- the Pix2Pgp data frame header *has* to be an interger-multiple of the databus width
   -- i.e. = 40 for SparkPix-S
   -- note that TRGCNT_HEADER_WIDTH_C > TRGCNT_WIDTH_C;
   -- the header has a standard trigger counter width that needs to be larger or equal
   -- to the actual trigger counter coming in from the columns;
   -- (the inbound trigger counter from the columns gets resized to fit)
   constant HEADER_DWIDTH_C       : natural := ASIC_DATABUS_DWIDTH_C;
   constant TRGCNT_HEADER_WIDTH_C : natural := 8;                        -- 8
   -- constant FLAGS_WIDTH_C         : natural := 8;                     -- 8  (unused)
   -- constant COL_BITMASK_WIDTH_C   : natural := NUM_OF_COL_MANAGERS_C; -- 24 (unused)

   ---------------------------------------------
   -- Pix2Pgp data frame header bitmapping begin
   ---------------------------------------------
   constant OVEROCC_FLAG_POS_C      : natural := HEADER_DWIDTH_C-1; -- 39
   constant PAUSE_FLAG_POS_C        : natural := HEADER_DWIDTH_C-2; -- 38
   constant COLUMN_ERROR_FLAG_POS_C : natural := HEADER_DWIDTH_C-3; -- 37
   constant PAUSE_ERROR_FLAG_POS_C  : natural := HEADER_DWIDTH_C-4; -- 36
   constant DUMMY_HEADER_POS_C      : natural := HEADER_DWIDTH_C-5; -- 35
   constant TIMEOUT_FLAG_POS_C      : natural := HEADER_DWIDTH_C-6; -- 34
   ---------------------------------------------------------------------------
   -- reserved bits (only one left)
   subtype  FLAGS_RESERVED_POS_C   is natural range  HEADER_DWIDTH_C-7 -- [33:32]
                                              downto HEADER_DWIDTH_C-8;
   ---------------------------------------------------------------------------
   -- col-bitmask
   subtype  COL_BITMASK_POS_C      is natural range  HEADER_DWIDTH_C-9 -- [31:8]
                                              downto TRGCNT_HEADER_WIDTH_C;
   ---------------------------------------------------------------------------
   -- trigger counter
   subtype  TRG_CNT_POS_C          is natural range  TRGCNT_HEADER_WIDTH_C-1 -- [7:0]
                                              downto 0;
   ---------------------------------------------------------------------------
   -------------------------------------------
   -- Pix2Pgp data frame header bitmapping end
   -------------------------------------------

   -------------------------------------------
   -- Pix2Pgp column metadata bitmapping begin
   -------------------------------------------
   ---------------------------------------------------------------------------
   subtype  META_FLAGS_POS_C   is natural range  ASIC_DATABUS_DWIDTH_C-1 downto 24;
   ---------------------------------------------------------------------------
   subtype  META_COL_POS_C     is natural range  23 downto 16;
   ---------------------------------------------------------------------------
   subtype  META_TRG_CNT_POS_C is natural range  15 downto 8;
   ---------------------------------------------------------------------------
   subtype  META_DATALEN_POS_C is natural range  7 downto 0;
   ---------------------------------------------------------------------------
   -----------------------------------------
   -- Pix2Pgp column metadata bitmapping end
   -----------------------------------------

   -- functions
   -- asic
   function colMetaMap   (flags: slv; col: slv; trgCnt: slv; dataLen: slv) return slv;
   function asicHeaderMap(overOccError: sl; colPause: sl; colFifoError : sl;
                          colPauseError: sl; timeoutError: sl; dummyHeader: sl;
                          colBitmask: slv; trgCntGlbl: slv) return slv;
   -- fpga
   function isDummy        (din : slv) return boolean;
   function fpgaPreambleMap(pix2pgpId: slv; asicType: slv; asicId: slv; fpgaId: slv) return slv;
   function fpgaHeaderMap  (laneError: slv; laneTimeout: slv; laneValid: slv) return slv;
   function tKeepSet       (dataLen : natural) return slv;

   -- the receiver can deduce which columns have data from the bitmask
   -- and it can also deduce how many data by reading the dataLen before each seq of hits

   -- examples of the final pix2pgp frame format:
   -- e.g. 1: this event has 1 hit from two different cols (cols 0 and 5)
   -- pgp data frame header | col5_dataLen=1 | col0_hit0 | col2_dataLen=1 | col5_hit0
   -- e.g. 2: this event has 3 hits from one column (col 2)
   -- pgp data frame header | col2_dataLen=3 | col2_hit0 | col2_hit1 | col2_hit2

   -- note that the colX_dataLen field is comprised from other column-related metadata as well;
   -- it also yields info on the pause/overOcc status of the column, plus a colID for backup

   -- also, if a column yielded odd number of events, the last hit will have an extra 20-bit padding
   -- at the end; the receiver will ignore it since it knows the true event dataLen from that col
   --
   --
   function powerOfTwo(N: natural) return slv;
   -- function stolen from numeric_std
   function rightShift (inSlv: slv; count: natural) return slv;
   --

   -- FPGA-RX related
   constant LANERX_FIFO_ADDR_WIDTH_C     : integer := 10;
   constant LANERX_FRAMELEN_WIDTH_C      : integer := 20;
   constant LANERX_FRAMELEN_BUFF_WIDTH_C : integer := LANERX_FRAMELEN_WIDTH_C+1;
   constant LANERX_FIFO_PIPE_C           : integer := 2;

   -- FPGA receiver needs to widen the data bus by the amount of serializers to cope with bandwidth
   constant FPGA_DATABUS_DWIDTH_C : natural := ASIC_DATABUS_DWIDTH_C*NUM_OF_SERIALIZERS_C;

   constant FPGA_PREAMPLE_LEN_C : natural := 160;
   constant ASIC_TYPE_C         : slv(31 downto  0) := toSlv(0, 32); -- SparPix-S = 0
   constant FPGA_ID_DEFAULT_C   : slv(31 downto  0) := x"C0CAC01A";
   constant PIX2PGP_ID_C        : slv(55 downto  0) := x"70"  -- p
                                                     & x"69"  -- i
                                                     & x"78"  -- x
                                                     & x"32"  -- 2
                                                     & x"70"  -- p
                                                     & x"67"  -- g
                                                     & x"70"; -- p

   constant FPGA_HEADER_LEN_C  : natural := 3*NUM_OF_SERIALIZERS_C;
   constant FPGA_TRAILER_LEN_C : natural := 64;

   type Pix2PgpFpgaRxMetaBusType is record
      -- flags begin
      metaData : slv(LANERX_FRAMELEN_BUFF_WIDTH_C-1 downto 0);
   end record;

   constant DEFAULT_PIX2PGP_FPGARX_METABUS_C : Pix2PgpFpgaRxMetaBusType := (
      metaData => (others => '0'));

   type Pix2PgpFpgaRxDataArray is array (NUM_OF_SERIALIZERS_C-1 downto 0) of Pix2PgpDataBusType;
   type Pix2PgpFpgaRxMetaArray is array (NUM_OF_SERIALIZERS_C-1 downto 0) of Pix2PgpFpgaRxMetaBusType;

end Pix2PgpPkg;

package body Pix2PgpPkg is

   function powerOfTwo(N: natural) return slv is
      variable result : slv(N downto 0);
   begin
      result := (others => '0');
      result(N) := '1';
      return result;
   end function powerOfTwo;

   -- stolen from numeric_std
   function rightShift (inSlv: slv; count: natural) return slv is
      constant inSlvLen : integer := inSlv'LENGTH-1;
      alias    xarg     : slv(inSlvLen downto 0) is inSlv;
      variable result   : slv(inSlvLen downto 0) := (others => '0');
   begin

      if count <= inSlvLen then
         result(inSlvLen-count downto 0) := xarg(inSlvLen downto count);
      end if;

      return result;

   end rightShift;

   -- ASIC-related
   function colMetaMap (flags: slv; col: slv; trgCnt: slv; dataLen: slv) return slv is
      variable retMeta: slv(ASIC_DATABUS_DWIDTH_C-1 downto 0) := (others => '0');
   begin

      retMeta(META_FLAGS_POS_C)   := resize(flags,  16);
      retMeta(META_COL_POS_C)     := resize(col,     8);
      retMeta(META_TRG_CNT_POS_C) := resize(trgCnt,  8);
      retMeta(META_DATALEN_POS_C) := resize(dataLen, 8);

      return retMeta;
   end colMetaMap;

   function asicHeaderMap (overOccError: sl; colPause: sl; colFifoError : sl;
                           colPauseError: sl; timeoutError: sl; dummyHeader: sl;
                           colBitmask: slv; trgCntGlbl: slv) return slv is
      variable retHeader: slv(ASIC_DATABUS_DWIDTH_C-1 downto 0) := (others => '0');
   begin

      retHeader(OVEROCC_FLAG_POS_C)      := overOccError  and not(dummyHeader);
      retHeader(PAUSE_FLAG_POS_C)        := colPause      and not(dummyHeader);
      retHeader(COLUMN_ERROR_FLAG_POS_C) := colFifoError  and not(dummyHeader);
      retHeader(PAUSE_ERROR_FLAG_POS_C)  := colPauseError and not(dummyHeader);
      retHeader(TIMEOUT_FLAG_POS_C)      := timeoutError  and not(dummyHeader);
      retHeader(DUMMY_HEADER_POS_C)      := dummyHeader;
      retHeader(FLAGS_RESERVED_POS_C)    := (others => '0');
      retHeader(COL_BITMASK_POS_C)       := colBitmask;
      retHeader(TRG_CNT_POS_C)           := resize(trgCntGlbl, 8);

      return retHeader;
   end asicHeaderMap;

   -- FPGA-related
   function isDummy (din: slv) return boolean is
      variable retBool : boolean := False;
   begin

      if onesCount(din) = conv_std_logic_vector(1, din'length) and din(DUMMY_HEADER_POS_C) = '1' then
         retBool := True;
      end if;

      return retBool;

   end isDummy;

   function lsbSet(lsbToSet : positive; retLen: integer) return slv is
      variable retSlv : slv(retLen-1 downto 0) := (others => '0');
   begin

      for i in 0 to retLen - 1 loop
         if i < lsbToSet then
            retSlv(i) := '1';
         else
            retSlv(i) := '0';
         end if;
      end loop;

      return retSlv;

   end function;

   -- pretty much fixed
   function fpgaPreambleMap (pix2pgpId: slv; asicType: slv; asicId: slv; fpgaId: slv) return slv is
      variable retPreamble: slv(FPGA_PREAMPLE_LEN_C-1 downto 0) := (others => '0');
   begin

      retPreamble(FPGA_PREAMPLE_LEN_C-1 downto 96) := resize(pix2pgpId, 64);
      retPreamble(95 downto 64) := resize(asicType, 32);
      retPreamble(63 downto 32) := resize(asicId,   32);
      retPreamble(31 downto  0) := resize(fpgaId,   32);

      return retPreamble;

   end fpgaPreambleMap;

   function tKeepSet (dataLen : natural) return slv is
      variable retTkeep: slv(AXI_STREAM_MAX_TKEEP_WIDTH_C-1 downto 0) := (others => '0');
      variable preambleBytes : natural := 1;
   begin

      preambleBytes := dataLen/8;

      for i in 0 to preambleBytes-1 loop
         retTkeep(i) := '1';
      end loop;

      return retTkeep;

   end tKeepSet;

   function fpgaHeaderMap (laneError: slv; laneTimeout: slv; laneValid: slv) return slv is
      variable retHeader: slv(FPGA_HEADER_LEN_C-1 downto 0) := (others => '0');
   begin

      retHeader(FPGA_HEADER_LEN_C-1 downto 16) := resize(laneError, 8);
      retHeader(15 downto  8) := resize(laneTimeout, 8);
      retHeader(7  downto  0) := resize(laneValid,   8);

      return retHeader;

   end fpgaHeaderMap;

end package body Pix2PgpPkg;
