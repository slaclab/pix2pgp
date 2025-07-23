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

import pix2pgp

class Pix2PgpAsicStreamRx(pr.Device):
    def __init__(self,
            numLanes=8,
            timeoutLimitWidth = 16,
            statusCntWidth = 5,
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
            name        = 'LanePauseErrorCnt',
            description = 'Increments by one for each pause-error detected',
            offset      = 0x300,
            bitSize     = self.statusCntWidth,
            number      = self.numLanes,
            stride      = 4,
            mode        = 'RO',
            disp        = '{:d}',
        )

        self.addRemoteVariables(
            name        = 'LaneFullCnt',
            description = 'Increments by one each time the lane FPGA FIFOs get full',
            offset      = 0x400,
            bitSize     = self.statusCntWidth,
            number      = self.numLanes,
            stride      = 4,
            mode        = 'RO',
            disp        = '{:d}',
        )

        self.addRemoteVariables(
            name        = 'LaneTrgCnt',
            description = 'Value of last ASIC trigger counter received by the lane',
            offset      = 0x500,
            bitSize     = self.trgCntWidth,
            number      = self.numLanes,
            stride      = 4,
            mode        = 'RO',
            disp        = '{:d}',
        )

        self.add(pr.RemoteVariable(
            name         = 'FpgaId',
            description  = 'FPGA Identifier; is sent with the FPGA-generated header',
            offset       = 0x600,
            bitSize      = 16,
            mode         = 'RW',
        ))

        addTimePair(
            name        = 'LaneTimeout',
            description = 'Upon reception of a trigger, an internal watchdog starts counting. if the LaneTimeout is reached, the lanes that do not have data will be masked as timed-out and the rest will be read (if any)',
            offset      = 0x604,
        )

        self.add(pr.RemoteVariable(
            name         = 'LanePauseTimeout',
            description  = 'FPGA Identifier; is sent with the FPGA-generated header',
            offset       = 0x608,
            bitSize      = 16,
            mode         = 'RW',
        ))

        self.add(pr.RemoteVariable(
            name         = 'LaneEnable',
            description  = 'Lane enable mask; setting a lane to low keeps it in reset',
            offset       = 0x60C,
            bitSize      = self.numLanes,
            mode         = 'RW',
        ))

        addBool(
            name        = 'DropColumnMisalign',
            description = 'If True: Lane receiver will drop a frame with uneven trigger counter values from columns within the frame, and will raise a decoding error. Default (and recommended) is True',
            offset      = 0x610,
        )

        addBool(
            name        = 'DropLaneMisalign',
            description = 'If True: Lane Supervisor will drop a frame with uneven trigger counter values from lanes within the frame, and will raise a decoding error. Default (and recommended) is True',
            offset      = 0x614,
        )

        addBool(
            name        = 'RealignOnSof',
            description  = 'Realign on Start-Of-Frame after recovering from Error',
            offset       = 0x618,
        )

        self.add(pr.RemoteCommand(
            name         = 'CntRst',
            description  = 'Status counter reset',
            offset       = 0x700,
            bitSize      = 1,
            function     = lambda cmd: cmd.post(1),
            hidden       = False,
        ))

        self.add(pr.RemoteCommand(
            name         = 'UsrRst',
            description  = 'Reset Pix2PgpAsicStreamRx',
            offset       = 0x704,
            bitSize      = 1,
            function     = lambda cmd: cmd.post(1),
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'Pgp4RxLinkDown',
            description  = 'PGP4 Link is Down',
            offset       = 0x708,
            bitSize      = self.numLanes,
            mode         = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'MergerBusy',
            description  = 'Merger FSM is Busy',
            offset       = 0x70C,
            bitSize      = 1,
            mode         = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name        = 'FpgaTrgCnt',
            description = 'Value of last FPGA Trigger counter',
            offset      = 0x710,
            bitSize     = self.trgCntWidth,
            mode        = 'RO',
            disp        = '{:d}',
        ))

    def countReset(self):
        self.CntRst()

    def HardReset(self):
        self.UsrRst()
