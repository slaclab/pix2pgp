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
            trgCntWidth = 6,
            sysClkFreq = 185.714E+6, # Units of Hz
            **kwargs):
        super().__init__(**kwargs)

        self.numLanes          = numLanes
        self.timeoutLimitWidth = timeoutLimitWidth
        self.sysClkFreq        = sysClkFreq
        self.trgCntWidth       = trgCntWidth

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


        self.add(pr.RemoteVariable(
            name         = 'FpgaId',
            description  = 'FPGA Identifier; is sent with the FPGA-generated header',
            offset       = 0x400,
            bitSize      = 16,
            mode         = 'RW',
        ))

        addTimePair(
            name        = 'LaneTimeout',
            description = 'Upon reception of a trigger, an internal watchdog starts counting. if the LaneTimeout is reached, the lanes that do not have data will be masked as timed-out and the rest will be read (if any)',
            offset      = 0x404,
        )

        self.add(pr.RemoteVariable(
            name         = 'LaneEnable',
            description  = 'Lane enable mask; setting a lane to low keeps it in reset',
            offset       = 0x408,
            bitSize      = self.numLanes,
            mode         = 'RW',
        ))

        addBool(
            name        = 'DropColumnMisalign',
            description = 'If True: Lane receiver will drop a frame with uneven trigger counter values from columns within the frame, and will raise a decoding error. Default (and recommended) is True',
            offset      = 0x40C,
        )

        addBool(
            name        = 'DropLaneMisalign',
            description = 'If True: Lane Supervisor will drop a frame with uneven trigger counter values from lanes within the frame, and will raise a decoding error. Default (and recommended) is True',
            offset      = 0x410,
        )

        addBool(
            name        = 'RealignOnSof',
            description = 'Realign on Start-Of-Frame after recovering from Error',
            offset      = 0x414,
        )

        addBool(
            name        = 'AutoRealign',
            description = 'Only transmit a frame if FpgaTrgCnt = AsicTrgCnt',
            offset      = 0x418,
        )

        addBool(
            name        = 'RstFpgaTrgCnt',
            description = 'Reset the FPGA Trigger Counter',
            offset      = 0x41C,
        )

        addBool(
            name        = 'IncrSroEnLow',
            description = 'Increment the FPGA Trigger Counter even when SRO-enable is low',
            offset      = 0x420,
        )

        addBool(
            name        = 'Trigerless',
            description = 'Ignore SRO/DAQ trigger input and forward data on LaneRx activity only',
            offset      = 0x424,
        )

        addBool(
            name        = 'UsrRst',
            description = 'Reset Pix2PgpAsicStreamRx',
            offset      = 0x500,
        )

        self.add(pr.RemoteVariable(
            name         = 'LaneMonEnabled',
            description  = 'Lane monitoring module is present',
            offset       = 0x600,
            bitSize      = 1,
            mode         = 'RO',
            pollInterval = 1,
            base         = pr.Bool,
        ))

        self.add(pr.RemoteVariable(
            name         = 'Pgp4RxLinkDown',
            description  = 'PGP4 Link is Down',
            offset       = 0x604,
            bitSize      = self.numLanes,
            mode         = 'RO',
            pollInterval = 1,
        ))

    def FpgaCntReset(self):
        self.RstFpgaTrgCnt.set(True)
        time.sleep(0.2)
        self.RstFpgaTrgCnt.set(False)

    def HardReset(self):
        self.UsrRst.set(True)
        time.sleep(0.2)
        self.UsrRst.set(False)
