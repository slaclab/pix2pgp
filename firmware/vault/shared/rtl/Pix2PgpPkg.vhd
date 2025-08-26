-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Pix2Pgp Package
--
-- imports the associated Pix2PgpAsicPkg; the latter is a symbolic link;
-- the symbolic link is created by the Makefile
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
use pix2pgp.Pix2PgpAsicPkg.all;

package Pix2PgpPkg is

   -----------------------------------------------------------------------------
   ------------------------------ Pix2PgpPkg -----------------------------------
   -----------------------------------------------------------------------------

   -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   -- Functions
   -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   function colMetaMap   (flags: slv; col: slv; trgCnt: slv; dataLen: slv) return slv;
   function asicHeaderMap(overOccError: sl; colPause: sl; colFifoError : sl;
                          colPauseError: sl; timeoutError: sl; dummyHeader: sl;
                          colHitmask: slv; trgCntGlbl: slv) return slv;
   function isDummy        (din : slv) return boolean;
   function fpgaPreambleMap(pix2pgpId: slv; asicType: slv;
                            asicId: slv; fpgaId: slv; fpgaTrgCnt: slv) return slv;
   function fpgaHeaderMap  (laneDecError: slv; laneOverOcc: slv; lanePause: slv;
                            lanePauseError: slv; laneFull: slv; laneTimeout: slv;
                            laneDown: slv; laneValid: slv) return slv;
   function laneMetaMap    (overOcc: sl; pause: sl; pauseError: sl;
                            frameSize: slv; colCnt: slv; trgCnt: slv) return slv;
   function tKeepSet       (dataLen : natural) return slv;
   function rangeToLen     (high : integer; low : integer) return integer;
   --
   function powerOfTwo(N: natural) return slv;
   -- function stolen from numeric_std
   function rightShift (inSlv: slv; count: natural) return slv;
   --
   -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

   type Pix2PgpSparseDinArray is array (NUM_OF_COL_MANAGERS_C-1 downto 0) of
      slv(ASIC_DATABUS_DWIDTH_C-1 downto 0);

   constant BITMAX_COL_MANAGERS_C : natural := bitSize(NUM_OF_COL_MANAGERS_C);
   constant BITMAX_SERIALIZERS_C  : natural := bitSize(NUM_OF_SERIALIZERS_C);

   constant PGP_DWIDTH_C : natural := 64;
   constant SER_DWIDTH_C : natural := 32;

   -- *** ColumnManager-related (for SparkPix-S) ***
   -- even though we have 672 pixels max, DATALEN_WIDTH_C should be less than 10 (10 bits fit 672);
   -- this is because the dataLength for a single event can never reach 672;
   -- the data FIFO cannot accommodate for that amount of hits.
   -- so the true data length can only be smaller than the hits the data FIFO can fit.
   -- after hitting almost-full, the data FIFO will get drained...

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

   type Pix2PgpCfgConfigType is record
      colEnaSparse : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      colEnaPgp    : slv(NUM_OF_COL_MANAGERS_C-1 downto 0);
      timeoutLimit : slv(TIMEOUT_LIMIT_WIDTH_C-1 downto 0);
      pauseLimit   : slv(TIMEOUT_LIMIT_WIDTH_C-1 downto 0);
   end record;

   constant DEFAULT_PIX2PGP_CONFIG_C : Pix2PgpCfgConfigType := (
      colEnaSparse => (others => '1'),
      colEnaPgp    => (others => '1'),
      timeoutLimit => (others => '1'),
      pauseLimit   => (others => '1'));

   type Pix2PgpCfgReadbackType is record
      cfgColBusy        : sl;
      cfgColDataEmpty   : sl;
      cfgColStatusEmpty : sl;
      cfgSuperBusy      : sl;
      cfgArbBusy        : sl;
   end record;

   constant DEFAULT_PIX2PGP_ASICRDBK_C : Pix2PgpCfgReadbackType := (
      cfgColBusy        => '0',
      cfgColDataEmpty   => '1',
      cfgColStatusEmpty => '1',
      cfgSuperBusy      => '0',
      cfgArbBusy        => '0');

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
      data : slv(PIX2PGP_DATABUS_DWIDTH_C-1 downto 0);
   end record;

   constant DEFAULT_PIX2PGP_DATABUS_C : Pix2PgpDataBusType := (
      data => (others => '0'));

   type Pix2PgpDataBusArray is array (NUM_OF_COL_MANAGERS_C-1 downto 0) of Pix2PgpDataBusType;

   -- FPGA-related
   ------------------------------------------------------------------------------
   -- FPGA-RX related parameters
   constant LANERX_FRAME_SIZE_WIDTH_C : integer := 16;

   -- has to be greater or equal to LANERX_FRAME_SIZE_WIDTH_C
   constant STREAMRX_FRAME_SIZE_WIDTH_C : integer := 16;

   constant COLCNT_WIDTH_C : natural := BITMAX_COL_MANAGERS_C;

   -- trigger counter; plus frame size; plus number of active cols; plus overOcc, pause, pauseError
   constant LANERX_META_DWIDTH_C : integer := TRGCNT_WIDTH_C +
                                              LANERX_FRAME_SIZE_WIDTH_C +
                                              COLCNT_WIDTH_C + 3;
   -- ~~~~~~~~~~~~~~~~~~
   -- FPGA Lane Metadata
   -- ~~~~~~~~~~~~~~~~~~
   constant LANE_OVEROCC_POS_C     : natural := LANERX_META_DWIDTH_C-1;
   constant LANE_PAUSE_POS_C       : natural := LANERX_META_DWIDTH_C-2;
   constant LANE_PAUSE_ERROR_POS_C : natural := LANERX_META_DWIDTH_C-3;
   subtype  LANE_SIZE_POS_C     is   natural range LANERX_META_DWIDTH_C-4 downto COLCNT_WIDTH_C+TRGCNT_WIDTH_C;
   subtype  LANE_COLCNT_POS_C   is   natural range COLCNT_WIDTH_C+TRGCNT_WIDTH_C-1 downto TRGCNT_WIDTH_C;
   subtype  LANE_TRGCNT_POS_C   is   natural range TRGCNT_WIDTH_C-1 downto 0;

   ------------------------------------------------------------------------------
   -- FPGA Preamble Mapping
   ------------------------------------------------------------------------------
   constant FPGA_PREAMBLE_LEN_C : natural := 128;
   subtype PIX2PGP_ID_POS_C    is natural range  FPGA_PREAMBLE_LEN_C-1 downto 64;
   subtype ASIC_TYPE_POS_C     is natural range  63 downto 48;
   subtype ASIC_ID_POS_C       is natural range  47 downto 32;
   subtype FPGA_ID_POS_C       is natural range  31 downto 16;
   subtype RESERVED_POS_C      is natural range  15 downto TRGCNT_WIDTH_C;
   subtype FPGA_TRGCNT_POS_C   is natural range  TRGCNT_WIDTH_C-1 downto  0;
   --
   constant FPGA_ID_DEFAULT_C   : slv(15 downto  0) := x"1925";
   constant PIX2PGP_ID_C        : slv(63 downto  0) := x"00"  -- 0
                                                     & x"70"  -- p
                                                     & x"69"  -- i
                                                     & x"78"  -- x
                                                     & x"32"  -- 2
                                                     & x"70"  -- p
                                                     & x"67"  -- g
                                                     & x"70"; -- p
   --
   constant PIX2PGP_ID_LEN_C : natural := rangeToLen(PIX2PGP_ID_POS_C'high, PIX2PGP_ID_POS_C'low);
   constant ASIC_TYPE_LEN_C  : natural := rangeToLen(ASIC_TYPE_POS_C'high, ASIC_TYPE_POS_C'low);
   constant ASIC_ID_LEN_C    : natural := rangeToLen(ASIC_ID_POS_C'high, ASIC_ID_POS_C'low);
   constant FPGA_ID_LEN_C    : natural := rangeToLen(FPGA_ID_POS_C'high, FPGA_ID_POS_C'low);
   constant FPGA_TRGCNT_LEN_C: natural := rangeToLen(FPGA_TRGCNT_POS_C'high, FPGA_TRGCNT_POS_C'low);
   --
   ------------------------------------------------------------------------------
   -- FPGA Header Mapping
   ------------------------------------------------------------------------------
   -- 8 fields; laneDecError, laneOverOcc, lanePause, lanePauseError,
   --           laneFull,     laneTimeout, laneDown,  laneValid
   ------------------------------------------------------------------------------
   constant FPGA_HEADER_FIELDS_C   : natural := 8;
   constant FPGA_HEADER_LEN_C      : natural := FPGA_HEADER_FIELDS_C*NUM_OF_SERIALIZERS_C;
   constant FPGA_HEADER_STRADDLE_C : natural := FPGA_HEADER_LEN_C-((FPGA_HEADER_FIELDS_C-1)*
                                                                   NUM_OF_SERIALIZERS_C);
   ------------------------------------------------------------------------------
   subtype FPGA_LANERX_DEC_ERROR_POS_C   is natural range  FPGA_HEADER_LEN_C-1 downto
                                             FPGA_HEADER_LEN_C-1*FPGA_HEADER_STRADDLE_C;

   subtype FPGA_LANERX_OVEROCC_POS_C     is natural range  FPGA_HEADER_STRADDLE_C*7-1 downto
                                             FPGA_HEADER_STRADDLE_C*6;

   subtype FPGA_LANERX_PAUSE_POS_C       is natural range  FPGA_HEADER_STRADDLE_C*6-1 downto
                                             FPGA_HEADER_STRADDLE_C*5;

   subtype FPGA_LANERX_PAUSE_ERROR_POS_C is natural range  FPGA_HEADER_STRADDLE_C*5-1 downto
                                             FPGA_HEADER_STRADDLE_C*4;

   subtype FPGA_LANERX_FULL_POS_C        is natural range  FPGA_HEADER_STRADDLE_C*4-1 downto
                                             FPGA_HEADER_STRADDLE_C*3;

   subtype FPGA_LANERX_TIMEOUT_POS_C     is natural range  FPGA_HEADER_STRADDLE_C*3-1 downto
                                             FPGA_HEADER_STRADDLE_C*2;

   subtype FPGA_LANERX_DOWN_POS_C        is natural range  FPGA_HEADER_STRADDLE_C*2-1 downto
                                             FPGA_HEADER_STRADDLE_C;

   subtype FPGA_LANERX_VALID_POS_C       is natural range  FPGA_HEADER_STRADDLE_C*1-1 downto 0;
   ------------------------------------------------------------------------------

   -- trailer is fixed; contains the pix2pgp identifier string
   ------------------------------------------------------------------------------
   constant FPGA_TRAILER_LEN_C : natural := 64;
   ------------------------------------------------------------------------------

   type Pix2PgpFpgaRxDataArray is array (NUM_OF_SERIALIZERS_C-1 downto 0) of
      slv(PIX2PGP_DATABUS_DWIDTH_C-1 downto 0);

   type Pix2PgpLaneFrameSizeArray is array (NUM_OF_SERIALIZERS_C-1 downto 0) of
      slv(LANERX_FRAME_SIZE_WIDTH_C-1 downto 0);

   type Pix2PgpLaneStatusType is record
      -- flags begin
      decError     : sl;
      overOcc      : sl;
      pause        : sl;
      pauseError   : sl;
      overflow     : sl;
      valid        : sl;
      down         : sl;
      timeout      : sl;
      -- flags end
      activeColCnt : slv(BITMAX_COL_MANAGERS_C-1 downto 0);
      trgCnt       : slv(TRGCNT_WIDTH_C-1 downto 0);
      frameSize    : slv(LANERX_FRAME_SIZE_WIDTH_C-1 downto 0);
   end record;

   constant DEFAULT_PIX2PGP_LANESTATUS_C : Pix2PgpLaneStatusType := (
      -- flags begin
      decError     => '0',
      overOcc      => '0',
      pause        => '0',
      pauseError   => '0',
      overflow     => '0',
      valid        => '0',
      down         => '0',
      timeout      => '0',
      -- flags end
      activeColCnt => (others => '0'),
      trgCnt       => (others => '0'),
      frameSize    => (others => '0'));

   constant FPGA_TIMEOUT_LIMIT_WIDTH_C         : positive := 16;
   --
   constant FPGA_TIMEOUT_LIMIT_DEFAULT_C       : positive := 16384;
   constant FPGA_PAUSE_TIMEOUT_LIMIT_DEFAULT_C : positive := 16;
   --

   type Pix2PgpStreamRxConfigType is record
      dropColMisalign  : sl;
      dropLaneMisalign : sl;
      realignOnSof     : sl;
      fpgaId           : slv(15 downto 0);
      laneEnable       : slv(NUM_OF_SERIALIZERS_C-1 downto 0);
      laneTimeout      : slv(FPGA_TIMEOUT_LIMIT_WIDTH_C-1 downto 0);
      lanePauseTimeout : slv(FPGA_TIMEOUT_LIMIT_WIDTH_C-1 downto 0);
   end record;

   constant DEFAULT_PIX2PGP_STREAMRX_CONFIG_C : Pix2PgpStreamRxConfigType := (
      -- flags begin
      dropColMisalign  => '1',
      dropLaneMisalign => '1',
      realignOnSof     => toSl(EVAL_SOF_C),
      fpgaId           => FPGA_ID_DEFAULT_C,
      laneEnable       => (others => '1'),
      laneTimeout      => toSlv(FPGA_TIMEOUT_LIMIT_DEFAULT_C,       FPGA_TIMEOUT_LIMIT_WIDTH_C),
      lanePauseTimeout => toSlv(FPGA_PAUSE_TIMEOUT_LIMIT_DEFAULT_C, FPGA_TIMEOUT_LIMIT_WIDTH_C));

   type Pix2PgpLaneStatusArray is array (NUM_OF_SERIALIZERS_C-1 downto 0) of Pix2PgpLaneStatusType;

   -- FPGA receiver needs to widen the data bus by the amount of serializers to cope with bandwidth
   constant FPGA_DATABUS_DWIDTH_C : natural := PIX2PGP_DATABUS_DWIDTH_C*NUM_OF_SERIALIZERS_C;

   -- AXI-Stream configuration
   constant ASIC_DATA_AXI_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C    => false,
      TDATA_BYTES_C => PIX2PGP_DATABUS_DWIDTH_C/8,
      TDEST_BITS_C  => 4,
      TID_BITS_C    => 0,
      TKEEP_MODE_C  => TKEEP_NORMAL_C,
      TUSER_BITS_C  => 4,
      TUSER_MODE_C  => TUSER_NORMAL_C);

   constant ASIC_TX_AXI_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C    => false,
      TDATA_BYTES_C => PGP_DWIDTH_C/8,
      TDEST_BITS_C  => 4,
      TID_BITS_C    => 0,
      TKEEP_MODE_C  => TKEEP_NORMAL_C,
      TUSER_BITS_C  => 4,
      TUSER_MODE_C  => TUSER_NORMAL_C);

   constant PIX2PGP_FPGA_AXI_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C    => false,
      TDATA_BYTES_C => FPGA_DATABUS_DWIDTH_C/8,
      TDEST_BITS_C  => 4,
      TID_BITS_C    => 0,
      TKEEP_MODE_C  => TKEEP_NORMAL_C,
      TUSER_BITS_C  => 4,
      TUSER_MODE_C  => TUSER_NORMAL_C);

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
   function rangeToLen (high : integer; low : integer) return integer is
   begin
      return (high - low + 1);
   end function;

   function colMetaMap (flags: slv; col: slv; trgCnt: slv; dataLen: slv) return slv is
      variable retMeta: slv(PIX2PGP_DATABUS_DWIDTH_C-1 downto 0) := (others => '0');
   begin

      retMeta(META_FLAGS_POS_C) := resize(flags, rangeToLen(META_FLAGS_POS_C'high,
                                                            META_FLAGS_POS_C'low));
      --
      retMeta(META_COL_POS_C) := resize(col, rangeToLen(META_COL_POS_C'high,
                                                        META_COL_POS_C'low));
      --
      retMeta(META_TRGCNT_POS_C) := resize(trgCnt, rangeToLen(META_TRGCNT_POS_C'high,
                                                              META_TRGCNT_POS_C'low));
      --
      retMeta(META_DATALEN_POS_C) := resize(dataLen, rangeToLen(META_DATALEN_POS_C'high,
                                                                META_DATALEN_POS_C'low));
      --
      return retMeta;
   end colMetaMap;

   function asicHeaderMap (overOccError: sl; colPause: sl; colFifoError : sl;
                           colPauseError: sl; timeoutError: sl; dummyHeader: sl;
                           colHitmask: slv; trgCntGlbl: slv) return slv is
      variable retHeader: slv(PIX2PGP_DATABUS_DWIDTH_C-1 downto 0) := (others => '0');
   begin

      retHeader(OVEROCC_FLAG_POS_C)      := overOccError  and not(dummyHeader);
      retHeader(PAUSE_FLAG_POS_C)        := colPause      and not(dummyHeader);
      retHeader(COLUMN_ERROR_FLAG_POS_C) := colFifoError  and not(dummyHeader);
      retHeader(PAUSE_ERROR_FLAG_POS_C)  := colPauseError and not(dummyHeader);
      retHeader(TIMEOUT_FLAG_POS_C)      := timeoutError  and not(dummyHeader);
      retHeader(DUMMY_HEADER_POS_C)      := dummyHeader;
      retHeader(FLAGS_RESERVED_POS_C)    := (others => '0');
      retHeader(COL_HITMASK_POS_C)       := colHitmask;
      retHeader(TRGCNT_POS_C)            := resize(trgCntGlbl, rangeToLen(TRGCNT_POS_C'high,
                                                                TRGCNT_POS_C'low));

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
   function fpgaPreambleMap (pix2pgpId: slv; asicType: slv;
                             asicId: slv; fpgaId: slv; fpgaTrgCnt: slv ) return slv is
      variable retPreamble: slv(FPGA_PREAMBLE_LEN_C-1 downto 0) := (others => '0');
   begin

      retPreamble(PIX2PGP_ID_POS_C)  := resize(pix2pgpId, PIX2PGP_ID_LEN_C);

      retPreamble(ASIC_TYPE_POS_C) := resize(asicType, ASIC_TYPE_LEN_C);

      retPreamble(ASIC_ID_POS_C) := resize(asicId, ASIC_ID_LEN_C);

      retPreamble(FPGA_ID_POS_C) := resize(fpgaId, FPGA_ID_LEN_C);

      retPreamble(FPGA_TRGCNT_POS_C) := resize(fpgaTrgCnt, FPGA_TRGCNT_LEN_C);

      return retPreamble;

   end fpgaPreambleMap;

   function tKeepSet (dataLen : natural) return slv is
      variable retTkeep: slv(AXI_STREAM_MAX_TKEEP_WIDTH_C-1 downto 0) := (others => '0');
      variable bytes : natural := 1;
   begin

      bytes := dataLen/8;

      for i in 0 to bytes-1 loop
         retTkeep(i) := '1';
      end loop;

      return retTkeep;

   end tKeepSet;

   function fpgaHeaderMap (laneDecError: slv; laneOverOcc: slv; lanePause: slv;
                           lanePauseError: slv; laneFull: slv; laneTimeout: slv;
                           laneDown: slv; laneValid: slv) return slv is
      variable retHeader: slv(FPGA_HEADER_LEN_C-1 downto 0) := (others => '0');
   begin

      retHeader(FPGA_LANERX_DEC_ERROR_POS_C)   := resize(laneDecError, NUM_OF_SERIALIZERS_C);
      retHeader(FPGA_LANERX_OVEROCC_POS_C)     := resize(laneOverOcc, NUM_OF_SERIALIZERS_C);
      retHeader(FPGA_LANERX_PAUSE_POS_C)       := resize(lanePause, NUM_OF_SERIALIZERS_C);
      retHeader(FPGA_LANERX_PAUSE_ERROR_POS_C) := resize(lanePauseError, NUM_OF_SERIALIZERS_C);
      retHeader(FPGA_LANERX_FULL_POS_C)        := resize(laneFull, NUM_OF_SERIALIZERS_C);
      retHeader(FPGA_LANERX_TIMEOUT_POS_C)     := resize(laneTimeout, NUM_OF_SERIALIZERS_C);
      retHeader(FPGA_LANERX_DOWN_POS_C)        := resize(laneDown, NUM_OF_SERIALIZERS_C);
      retHeader(FPGA_LANERX_VALID_POS_C)       := resize(laneValid, NUM_OF_SERIALIZERS_C);

      return retHeader;

   end fpgaHeaderMap;

   function laneMetaMap (overOcc: sl; pause: sl; pauseError: sl;
                         frameSize: slv; colCnt: slv; trgCnt: slv) return slv is
      variable retLaneMeta: slv(LANERX_META_DWIDTH_C-1 downto 0) := (others => '0');
   begin

      retLaneMeta(LANE_OVEROCC_POS_C)     := overOcc;
      retLaneMeta(LANE_PAUSE_POS_C)       := pause;
      retLaneMeta(LANE_PAUSE_ERROR_POS_C) := pauseError;
      retLaneMeta(LANE_SIZE_POS_C)        := resize(frameSize, rangeToLen(LANE_SIZE_POS_C'high,
                                                                          LANE_SIZE_POS_C'low));

      retLaneMeta(LANE_COLCNT_POS_C)      := resize(frameSize, rangeToLen(LANE_COLCNT_POS_C'high,
                                                                          LANE_COLCNT_POS_C'low));

      retLaneMeta(LANE_TRGCNT_POS_C)      := resize(trgCnt, rangeToLen(LANE_TRGCNT_POS_C'high,
                                                                       LANE_TRGCNT_POS_C'low));

      return retLaneMeta;

   end laneMetaMap;

end package body Pix2PgpPkg;
