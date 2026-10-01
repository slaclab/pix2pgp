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
                                4:'WR_ERROR_S',
                                5:'ERROR_S',
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
            offset       = 0xB00,
            bitSize      = self.monCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneOverOccCnt',
            description = 'Increments by one each time the lane reports an over-occupancy',
            offset       = 0xB04,
            bitSize      = self.monCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LanePauseCnt',
            description = 'Increments by one each time the lane reports a pause',
            offset       = 0xB08,
            bitSize      = self.monCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LanePauseErrorCnt',
            description = 'Increments by one for each pause-error detected',
            offset       = 0xB0C,
            bitSize      = self.monCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneFullCnt',
            description = 'Increments by one each time the lane FPGA FIFOs get full',
            offset       = 0xB10,
            bitSize      = self.monCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneEventCnt',
            description = 'Increments by one each time a trigger/event is registered',
            offset       = 0xB14,
            bitSize      = self.monCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LaneDownCnt',
            description  = 'Increments by one each time the lane drops its PGP link',
            offset       = 0xB18,
            bitSize      = self.monCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LaneDecErrCntOverflow',
            description  = 'The LaneDecErrCnt has overflowed; reset is needed if True',
            offset       = 0xC00,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LanePauseErrCntOverflow',
            description  = 'The LanePauseErrCnt has overflowed; reset is needed if True',
            offset       = 0xC04,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LaneFullCntOverflow',
            description  = 'The LaneFullCnt has overflowed; reset is needed if True',
            offset       = 0xC08,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LaneOverOccCntOverflow',
            description  = 'The LaneOverOccCnt has overflowed; reset is needed if True',
            offset       = 0xC0C,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LanePauseCntOverflow',
            description  = 'The LanePauseCnt has overflowed; reset is needed if True',
            offset       = 0xC10,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LaneEventCntOverflow',
            description  = 'The LaneEventCnt has overflowed; reset is needed if True',
            offset       = 0xC14,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneDownCntOverflow',
            description = 'The LaneDownCnt has overflowed; reset is needed if True',
            offset       = 0xC18,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name        = 'ColHitmaskCntOverflow',
            description = 'The ColHitmaskCnt of the associated bit that is high has overflowed; reset is needed if True',
            offset       = 0xC1C,
            bitSize      = self.numColPerLane,
            mode         = 'RO',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LaneOverOcc',
            description  = 'Last Event had an Over-Occ Flag raised',
            offset       = 0xD00,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LanePause',
            description  = 'Last Event had its Pause Flag raised',
            offset       = 0xD04,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name         = 'LanePauseError',
            description  = 'Last Event had its Pause-Error Flag raised',
            offset       = 0xD08,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneTrgCnt',
            description = 'Last Event AsicTrgCnt for this Lane',
            offset       = 0xD0C,
            bitSize      = self.trgCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneHitmask',
            description = 'Last Event Hitmask for this Lane',
            offset       = 0xD10,
            bitSize      = self.numColPerLane,
            mode         = 'RO',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneFrameSize',
            description = 'Last Event FrameSize for this Lane',
            offset       = 0xD30,
            bitSize      = self.frameSizeWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneRxState',
            description = 'Current State of LaneRx',
            offset      = 0xD34,
            bitSize     = 4,
            mode        = 'RO',
            enum        = self.laneRxStateEnum))

        self.add(pr.RemoteVariable(
            name         = 'RxDataEmpty',
            description  = 'Lane Data FIFO is empty',
            offset       = 0xD38,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))


        self.add(pr.RemoteVariable(
            name         = 'RxMetaEmpty',
            description  = 'Lane Metadata FIFO is empty',
            offset       = 0xD3C,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneRxDin',
            description = 'Last Data Word received',
            offset       = 0xD40,
            bitSize      = self.dataWordWidth,
            mode         = 'RO',
            disp         = '{:#x}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name        = 'LaneID',
            description = 'Lane ID',
            offset       = 0xE00,
            bitSize      = self.monCntWidth,
            mode         = 'RO',
            disp         = '{:d}',
            pollInterval = 1,
        ))

        self.add(pr.RemoteCommand(
            name         = 'CntRst',
            description  = 'Counter Reset',
            offset       = 0xF00,
            bitSize      = 1,
            function     = lambda cmd: cmd.post(1),
            hidden       = False,
        ))

    def countReset(self):
        self.CntRst()
