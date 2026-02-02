#-----------------------------------------------------------------------------
# This file is part of the 'pix2pgp'. It is subject to
# the license terms in the LICENSE.txt file found in the top-level directory
# of this distribution and at:
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# No part of the 'pix2pgp', including this file, may be
# copied, modified, propagated, or distributed except according to the terms
# contained in the LICENSE.txt file.
#-----------------------------------------------------------------------------

import pyrogue as pr
import time

import pix2pgp

class Pix2PgpLaneMon(pr.Device):
    def __init__(self,
            numColPerLane=24,
            monCntWidth=8,
            **kwargs):
        super().__init__(**kwargs)

        self.numColPerLane = numColPerLane
        self.monCntWidth   = monCntWidth

        ###################################################

        self.addRemoteVariables(
            name        = 'ColHitmaskCnt',
            description = 'Increments by one each time the column-hitmask of an event is high',
            offset      = 0x000,
            bitSize     = self.monCntWidth,
            number      = self.numColPerLane,
            stride      = 4,
            mode        = 'RO',
            disp        = '{:d}',
            pollInterval= 1,
        )

        self.add(pr.RemoteVariable(
            name         = 'LaneDecErrorCnt',
            description  = 'Increments by one for each data decoding error detected',
            offset       = 0xA00,
            bitSize      = self.monCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneOverOccCnt',
            description = 'Increments by one each time the lane reports an over-occupancy',
            offset       = 0xA04,
            bitSize      = self.monCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LanePauseCnt',
            description = 'Increments by one each time the lane reports a pause',
            offset       = 0xA08,
            bitSize      = self.monCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LanePauseErrorCnt',
            description = 'Increments by one for each pause-error detected',
            offset       = 0xA0C,
            bitSize      = self.monCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneFullCnt',
            description = 'Increments by one each time the lane FPGA FIFOs get full',
            offset       = 0xA10,
            bitSize      = self.monCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneEventCnt',
            description = 'Increments by one each time a trigger/event is registered',
            offset       = 0xA14,
            bitSize      = self.monCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LaneDown',
            description  = 'Lane is Down',
            offset       = 0xA18,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LaneDecErrCntOverflow',
            description  = 'The LaneDecErrCnt has overflowed; reset is needed if True',
            offset       = 0xA1C,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LanePauseErrCntOverflow',
            description  = 'The LanePauseErrCnt has overflowed; reset is needed if True',
            offset       = 0xA20,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LaneFullCntOverflow',
            description  = 'The LaneFullCnt has overflowed; reset is needed if True',
            offset       = 0xA24,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LaneOverOccCntOverflow',
            description  = 'The LaneOverOccCnt has overflowed; reset is needed if True',
            offset       = 0xA28,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LanePauseCntOverflow',
            description  = 'The LanePauseCnt has overflowed; reset is needed if True',
            offset       = 0xA2C,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LaneEventCntOverflow',
            description  = 'The LaneEventCnt has overflowed; reset is needed if True',
            offset       = 0xA30,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name        = 'ColHitmaskCntOverflow',
            description = 'The ColHitmaskCnt of the associated bit that is high has overflowed; reset is needed if True',
            offset       = 0xA34,
            bitSize      = self.numColPerLane,
            mode         = 'RO',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneID',
            description = 'Lane ID',
            offset       = 0xA38,
            bitSize      = self.monCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteCommand(
            name         = 'CntRst',
            description  = 'Counter Reset',
            offset       = 0xB00,
            bitSize      = 1,
            function     = lambda cmd: cmd.post(1),
            hidden       = False,
        ))

    def countReset(self):
        self.CntRst()
