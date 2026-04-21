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
            trgCntWidth=6,
            monCntWidth=20,
            frameSizeWidth=16,
            dataWordWidth=64,
            **kwargs):
        super().__init__(**kwargs)

        self.numColPerLane  = numColPerLane
        self.monCntWidth    = monCntWidth
        self.trgCntWidth    = trgCntWidth
        self.frameSizeWidth = frameSizeWidth
        self.dataWordWidth  = dataWordWidth

        self.laneRxStateEnum = {0:'WAIT_HEADER_S',
                                1:'PARSE_COL_METADATA_S',
                                2:'PARSE_DATA_S',
                                3:'CLOSE_FRAME_S',
                                4:'WAIT_DUMMY_S',
                                5:'WR_ERROR_S',
                                6:'ERROR_S',
                                7:'UNDEFINED'}

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
            name         = 'LaneOverOcc',
            description  = 'Last Event had an Over-Occ Flag raised',
            offset       = 0xB00,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LanePause',
            description  = 'Last Event had its Pause Flag raised',
            offset       = 0xB04,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LanePauseError',
            description  = 'Last Event had its Pause-Error Flag raised',
            offset       = 0xB08,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneTrgCnt',
            description = 'Last Event AsicTrgCnt for this Lane',
            offset       = 0xB0C,
            bitSize      = self.trgCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneHitmask',
            description = 'Last Event Hitmask for this Lane',
            offset       = 0xB10,
            bitSize      = self.numColPerLane,
            mode         = 'RO',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneFrameSize',
            description = 'Last Event FrameSize for this Lane',
            offset       = 0xB14,
            bitSize      = self.frameSizeWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneRxDin',
            description = 'Last Data Word received',
            offset       = 0xB18,
            bitSize      = self.dataWordWidth,
            mode         = 'RO',
            disp         = '{:#x}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneRxState',
            description = 'Current State of LaneRx',
            offset      = 0xB20,
            bitSize     = 4,
            mode        = 'RO',
            enum        = self.laneRxStateEnum))

        self.add(pr.RemoteVariable(
            name        = 'LaneID',
            description = 'Lane ID',
            offset       = 0xC00,
            bitSize      = self.monCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteCommand(
            name         = 'CntRst',
            description  = 'Counter Reset',
            offset       = 0xD00,
            bitSize      = 1,
            function     = lambda cmd: cmd.post(1),
            hidden       = False,
        ))

    def countReset(self):
        self.CntRst()
