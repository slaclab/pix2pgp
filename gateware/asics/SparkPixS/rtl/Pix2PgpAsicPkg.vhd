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

package Pix2PgpAsicPkg is

   -----------------------------------------------------------------------------
   ------------------------------ SparkPix-S -----------------------------------
   -----------------------------------------------------------------------------
   -- ASIC-specific parameters

   -- Primary parameters to tune
   --
   constant NUM_OF_COL_MANAGERS_C : natural := 24; -- number of columns per serializer
   constant NUM_OF_SERIALIZERS_C  : natural :=  8; -- number of serializers per-ASIC
   constant ASIC_DATABUS_DWIDTH_C : natural := 20; -- data width

   -- every ASIC implementation has a specific decimal identifier
   constant ASIC_TYPE_C : natural := 0; -- SparkPix-S = 0

   -- if set to True:
   -- overOcc signal causes trigger counter to increment
   constant INCR_TRGCNT_OVEROCC_C : boolean := True;

   -- **************************************************************************
   --
   -- Secondary parameters to tune
   --
   -- 2^DATALEN_WIDTH_C-1 events should fit in ColManager data FIFO
   constant DATALEN_WIDTH_C : natural := 5;

   --  counter to double-check alignment
   constant TRGCNT_WIDTH_C : natural := 6;

   -- timeout counter
   constant TIMEOUT_LIMIT_WIDTH_C : natural := 12;

   -- internal data bus width is twice the inbound data width to maximize bandwidth
   constant PIX2PGP_DATABUS_DWIDTH_C : natural := ASIC_DATABUS_DWIDTH_C*2;
   --
   constant EVAL_SOF_C  : boolean := False;
   constant EVAL_EOFE_C : boolean := False;
   --
   -- **************************************************************************

   ------------------------------------------------------------------------------
   -- Header and Column metadata mapping
   -- ~~~~~~
   -- Header
   -- ~~~~~~
   -- Pix2Pgp data frame header *has* to be an integer-multiple of the databus width
   constant HEADER_WIDTH_MULT_C : natural := 1;
   --
   constant HEADER_DWIDTH_C     : natural := HEADER_WIDTH_MULT_C*PIX2PGP_DATABUS_DWIDTH_C;
   --

   -- bitfields
   constant OVEROCC_FLAG_POS_C      : natural := HEADER_DWIDTH_C-1; -- 39
   constant PAUSE_FLAG_POS_C        : natural := HEADER_DWIDTH_C-2; -- 38
   constant COLUMN_ERROR_FLAG_POS_C : natural := HEADER_DWIDTH_C-3; -- 37
   constant PAUSE_ERROR_FLAG_POS_C  : natural := HEADER_DWIDTH_C-4; -- 36
   constant DUMMY_HEADER_POS_C      : natural := HEADER_DWIDTH_C-5; -- 35
   constant TIMEOUT_FLAG_POS_C      : natural := HEADER_DWIDTH_C-6; -- 34
   --------------------------
   subtype  FLAGS_RESERVED_POS_C   is natural range  HEADER_DWIDTH_C-7  -- [33:32]
                                              downto HEADER_DWIDTH_C-8;
   --------------------------
   -- col-hitmask
   subtype  COL_HITMASK_POS_C      is natural range  HEADER_DWIDTH_C-9  -- [31:8]
                                              downto HEADER_DWIDTH_C-32;
   --------------------------
   -- trigger counter
   subtype  TRGCNT_POS_C           is natural range  HEADER_DWIDTH_C-33 -- [7:0]
                                              downto HEADER_DWIDTH_C-40;
   ------------------------------------------------------------------------------
   -- ~~~~~~~~~~~~~~~
   -- Column Metadata
   -- ~~~~~~~~~~~~~~~
   -- Pix2Pgp column metadata *have* to be an equal to the databus width
   -- three flags: timeout, overOcc and Pause:
   -- colMeta[26] -> timeout
   -- colMeta[25] -> overOcc
   -- colMeta[24] -> pause
   subtype  META_FLAGS_POS_C   is natural range  PIX2PGP_DATABUS_DWIDTH_C-1 downto 24;
   subtype  META_COL_POS_C     is natural range  23 downto 16;
   subtype  META_TRGCNT_POS_C  is natural range  15 downto 8;
   subtype  META_DATALEN_POS_C is natural range   7 downto 0;
   ------------------------------------------------------------------------------

   -- FPGA receiver needs to widen the data bus cope with bandwidth;
   -- The default width (PIX2PGP_DATABUS_DWIDTH_C*NUM_OF_SERIALIZERS_C) might be too wide;
   -- too wide -> synthesis or timing closure issues;
   -- user can choose to introduce a scaling factor here (e.g. *1/2 or *3/4) to make bus narrower;
   -- user should use a clk for AsicStreamRx that is faster than the PHY clk at all times...
   -- ...but a narrower FPGA_DATABUS_DWIDTH_C might need an even faster clk to not cause bottleneck
   constant FPGA_DATABUS_DWIDTH_C : natural := PIX2PGP_DATABUS_DWIDTH_C*NUM_OF_SERIALIZERS_C;

end Pix2PgpAsicPkg;

package body Pix2PgpAsicPkg is

end package body Pix2PgpAsicPkg;
