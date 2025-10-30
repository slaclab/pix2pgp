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

class Pix2PgpAsicStreamRx(pr.Device):
    def __init__(self,
            numLanes=8,
            timeoutLimitWidth = 16,
            statusCntWidth = 8,
            trgCntWidth = 6,
            sysClkFreq = 185.714E+6, # Units of Hz
            **kwargs):
        super().__init__(**kwargs)

        self.numLanes          = numLanes
        self.timeoutLimitWidth = timeoutLimitWidth
        self.sysClkFreq        = sysClkFreq
        self.trgCntWidth       = trgCntWidth
        self.statusCntWidth    = statusCntWidth

        ###################################################

        def getNs(var):
            x = var.dependencies[0].value()
            return float(x) * (1.0E+9/self.sysClkFreq)

        ###################################################

        def addTimePair(name, offset, description='', bitOffset=0, mode='RW'):

            self.add(pr.RemoteVariable(
                name         = name,
                description  = description,
                offset       = offset,
                bitSize      = self.timeoutLimitWidth,
                bitOffset    = bitOffset,
                mode         = mode,
                units        = f'1/{self.sysClkFreq/1.0E+6}MHz',
                disp         = '{:d}',
                pollInterval = 1 if (mode == 'RO') else 0,
            ))

            self.add(pr.LinkVariable(
                name         = f'{name}_ns',
                mode         = 'RO',
                units        = 'ns',
                linkedGet    = getNs,
                disp         = '{:1.2f}',
                dependencies = [self.variables[name]],
            ))

        ###################################################

        def addBool(name, description, offset):

            self.add(pr.RemoteVariable(
                name         = name,
                description  = description,
                offset       = offset,
                bitSize      = 1,
                mode         = 'RW',
                base         = pr.Bool,
            ))

        ###################################################

        self.addRemoteVariables(
            name        = 'LaneDecErrorCnt',
            description = 'Increments by one for each data decoding error detected',
            offset      = 0x200,
            bitSize     = self.statusCntWidth,
            number      = self.numLanes,
            stride      = 4,
            mode        = 'RO',
            disp        = '{:d}',
        )

        self.addRemoteVariables(
            name        = 'LaneOverOccCnt',
            description = 'Increments by one each time the lane reports an over-occupancy',
            offset      = 0x300,
            bitSize     = self.statusCntWidth,
            number      = self.numLanes,
            stride      = 4,
            mode        = 'RO',
            disp        = '{:d}',
        )

        self.addRemoteVariables(
            name        = 'LanePauseCnt',
            description = 'Increments by one each time the lane reports a pause',
            offset      = 0x400,
            bitSize     = self.statusCntWidth,
            number      = self.numLanes,
            stride      = 4,
            mode        = 'RO',
            disp        = '{:d}',
        )

        self.addRemoteVariables(
            name        = 'LanePauseErrorCnt',
            description = 'Increments by one for each pause-error detected',
            offset      = 0x500,
            bitSize     = self.statusCntWidth,
            number      = self.numLanes,
            stride      = 4,
            mode        = 'RO',
            disp        = '{:d}',
        )

        self.addRemoteVariables(
            name        = 'LaneFullCnt',
            description = 'Increments by one each time the lane FPGA FIFOs get full',
            offset      = 0x600,
            bitSize     = self.statusCntWidth,
            number      = self.numLanes,
            stride      = 4,
            mode        = 'RO',
            disp        = '{:d}',
        )

        self.addRemoteVariables(
            name        = 'LaneTimeoutCnt',
            description = 'Increments by one each time the an FPGA-Rx Lane times-out',
            offset      = 0x700,
            bitSize     = self.statusCntWidth,
            number      = self.numLanes,
            stride      = 4,
            mode        = 'RO',
            disp        = '{:d}',
        )

        self.addRemoteVariables(
            name        = 'LaneTrgCnt',
            description = 'Value of last ASIC trigger counter received by the lane',
            offset      = 0x800,
            bitSize     = self.trgCntWidth,
            number      = self.numLanes,
            stride      = 4,
            mode        = 'RO',
            disp        = '{:d}',
        )

        self.add(pr.RemoteVariable(
            name        = 'FpgaTrgCnt',
            description = 'Value of last FPGA Trigger counter',
            offset      = 0x900,
            bitSize     = self.trgCntWidth,
            mode        = 'RO',
            disp        = '{:d}',
        ))


        self.add(pr.RemoteVariable(
            name         = 'FpgaId',
            description  = 'FPGA Identifier; is sent with the FPGA-generated header',
            offset       = 0x904,
            bitSize      = 16,
            mode         = 'RW',
        ))

        addTimePair(
            name        = 'LaneTimeout',
            description = 'Upon reception of a trigger, an internal watchdog starts counting. if the LaneTimeout is reached, the lanes that do not have data will be masked as timed-out and the rest will be read (if any)',
            offset      = 0x908,
        )

        self.add(pr.RemoteVariable(
            name         = 'LaneEnable',
            description  = 'Lane enable mask; setting a lane to low keeps it in reset',
            offset       = 0x90C,
            bitSize      = self.numLanes,
            mode         = 'RW',
        ))

        addBool(
            name        = 'DropColumnMisalign',
            description = 'If True: Lane receiver will drop a frame with uneven trigger counter values from columns within the frame, and will raise a decoding error. Default (and recommended) is True',
            offset      = 0x910,
        )

        addBool(
            name        = 'DropLaneMisalign',
            description = 'If True: Lane Supervisor will drop a frame with uneven trigger counter values from lanes within the frame, and will raise a decoding error. Default (and recommended) is True',
            offset      = 0x914,
        )

        addBool(
            name        = 'RealignOnSof',
            description = 'Realign on Start-Of-Frame after recovering from Error',
            offset      = 0x918,
        )

        addBool(
            name        = 'AutoRealign',
            description = 'Only transmit a frame if FpgaTrgCnt = AsicTrgCnt',
            offset      = 0x91C,
        )

        addBool(
            name        = 'RstFpgaTrgCnt',
            description = 'Reset the FPGA Trigger Counter',
            offset      = 0x920,
        )

        addBool(
            name        = 'IncrSroEnLow',
            description = 'Increment the FPGA Trigger Counter even when SRO-enable is low',
            offset      = 0x924,
        )

        self.add(pr.RemoteCommand(
            name         = 'CntRst',
            description  = 'Status counter reset',
            offset       = 0xA00,
            bitSize      = 1,
            function     = lambda cmd: cmd.post(1),
            hidden       = False,
        ))

        addBool(
            name        = 'UsrRst',
            description = 'Reset Pix2PgpAsicStreamRx',
            offset      = 0xA04,
        )

        self.add(pr.RemoteVariable(
            name         = 'Pgp4RxLinkDown',
            description  = 'PGP4 Link is Down',
            offset       = 0xB00,
            bitSize      = self.numLanes,
            mode         = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'MergerBusy',
            description  = 'Merger FSM is Busy',
            offset       = 0xB04,
            bitSize      = 1,
            mode         = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'LaneDecErrorStatus',
            description  = 'LaneDecError (Last Status)',
            offset       = 0xC00,
            bitSize      = self.numLanes,
            mode         = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'LaneOverOccStatus',
            description  = 'LaneOverOcc (Last Status)',
            offset       = 0xC04,
            bitSize      = self.numLanes,
            mode         = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'LanePauseStatus',
            description  = 'LanePause (Last Status)',
            offset       = 0xC08,
            bitSize      = self.numLanes,
            mode         = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'LanePauseErrorStatus',
            description  = 'LanePauseError (Last Status)',
            offset       = 0xC0C,
            bitSize      = self.numLanes,
            mode         = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'LaneFullStatus',
            description  = 'LaneFull (Last Status)',
            offset       = 0xC10,
            bitSize      = self.numLanes,
            mode         = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'LaneTimeoutStatus',
            description  = 'LaneTimeout (Last Status)',
            offset       = 0xC14,
            bitSize      = self.numLanes,
            mode         = 'RO',
        ))

    def countReset(self):
        self.CntRst()

    def FpgaCntReset(self):
        self.RstFpgaTrgCnt.set(True)
        time.sleep(0.2)
        self.RstFpgaTrgCnt.set(False)

    def HardReset(self):
        self.countReset()
        self.UsrRst.set(True)
        time.sleep(0.2)
        self.UsrRst.set(False)
