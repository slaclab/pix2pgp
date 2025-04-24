# -------------------------------------------------------------------------------
# -- This file is part of 'Pix2Pgp'.
# -- It is subject to the license terms in the LICENSE.txt file found in the
# -- top-level directory of this distribution and at:
# --    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# -- No part of 'Pix2Pgp', including this file,
# -- may be copied, modified, propagated, or distributed except according to
# -- the terms contained in the LICENSE.txt file.
# -------------------------------------------------------------------------------

import sys
import numpy as np
import click

class AsicData(object):
    def __init__(self,
                 asicType = "SparkPixS",
                 verbose  = False,
                 **kwargs):
        """
        Class for the entire ASIC dataset.
        Container for all datapoints associated with the ASIC.
        """

        # expand as necessary; should match the associated value in the VHDL pkg
        self.asicTypeDict = {
            0: "SparkPixS",
            1: "SparkPixT",
        }

        # class parameters (parameters have _ prefix)
        self._asicTypeSet = asicType
        self._verbose     = verbose

        # populated by FrameParamSet (parameters have _ prefix)
        self._numOfLanes   = None
        self._numOfCols    = None
        self._preambleLen  = None
        self._headerLen    = None
        self._trailerLen   = None

        # populated by the data themselves
        # preamble
        self.preambleErr  = False
        self.validLanes   = None
        self.timeoutLanes = None
        self.errorLanes   = None
        self.asicType     = 0
        self.asicId       = 0
        self.fpgaId       = 0
        # header
        # [...]

        # initialize the values
        self.FrameParamSet()

        # call after self.FrameParamSet
        self.validLanes   = [None] * self._numOfLanes
        self.timeoutLanes = [None] * self._numOfLanes
        self.errorLanes   = [None] * self._numOfLanes

    #################################################################
    #################################################################
    def Formatter(self, data):
        """
        Parses raw frame data and extracts specific fields based on predefined bit masks.

        Parameters:
        data (numpy array): Input array containing raw frame data to be formatted.

        Processing Steps:
        - The input data is interpreted as 64-bit unsigned integers.
        - Specific fields are extracted using bitwise operations and slicing.
        - Extracted fields are stored in their respective attributes of the class.
        """

        # Convert input data to 64-bit unsigned integers for consistent processing
        _dat = np.array(data)

        dat = self._dat.view(np.uint64)

        # Determine the total number of words (64-bit entries) in the frame
        self.wordSize = len(dat)

        # Parse them in
        self.EventParseFsm(frame=dat, size=self.wordSize)

    #################################################################
    #################################################################

    #################################################################
    def FrameParamSet(self):
        """
        Sets the parameters of the frame length depending on the ASIC type
        """
        if self._asicTypeSet == 'SparkPixS':
            self._numOfLanes  = 8
            self._numOfCols   = 24
            self._preambleLen = 20
            self._headerLen   = 3
            self._trailerLen  = 8
        elif self._asicTypeSet == 'SparkPixT':
            self._numOfLanes  = 8
            self._numOfCols   = 24
            self._preambleLen = 20
            self._headerLen   = 3
            self._trailerLen  = 8
        else:
            click.secho(f"[ERROR]: asicType parameter not set properly! options: SparkPixS, SparkPixT", bg='red')
            sys.exit()

    #################################################################

    #################################################################
    def PreambleEval(self, preamble):
        """
        Parses in the preamble
        """

        _preamble     = int(preamble, 16)
        _pix2pgpId    = (_preamble >> 96) & 0xFFFFFFFFFFFFFFFF
        self.asicType = (_preamble >> 64) & 0xFFFFFFFF
        self.asicId   = (_preamble >> 32) & 0xFFFFFFFF
        self.fpgaId   = (_preamble >>  0) & 0xFFFFFFFF

        # error-checking
        if toAscii(_pix2pgpId) != "pix2pgp":
            self.preambleErr = True
        elif self._asicTypeSet != self.asicTypeDict.get(self.asicType):
            self.preambleErr = True

        _format = 'Pix2Pgp Frame Begin ~ AsicType={0:<10} AsicId={1:<10} FpgaId={2:<10x}~'

        if self.preambleErr or self._verbose:
            print(f"//////////////////////////////////////////////////////////////////////////////")
            print(_format.format(self.asicTypeDict.get(self.asicType), self.asicId, self.fpgaId))
            print(f"//////////////////////////////////////////////////////////////////////////////")
        if self.preambleErr:
            click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)
            click.secho(f"[ERROR]: Preamble Error!", bg='red', blink=True)
            click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)

    #################################################################


    #################################################################
    def HeaderEval(self, header):
        """
        Parses-in the header and determines if there is an error or not
        Also prints-out the header metadata if needed
        """
        _asicId       = (header >> np.uint8(48)) & np.uint16(0xFFFF)
        _timeout      = (header >> np.uint8(47)) & np.uint8(0x01)
        _overflow     = (header >> np.uint8(46)) & np.uint8(0x01)
        _underflow    = (header >> np.uint8(45)) & np.uint8(0x01)
        _decodeError  = (header >> np.uint8(44)) & np.uint8(0x01)
        _glblTrgError = (header >> np.uint8(43)) & np.uint8(0x01)
        _frameCnt     = (header >> np.uint8( 0)) & np.uint32(0xFFFFFFFF)

        self._headerErr = _timeout or _overflow or _underflow or _decodeError or _glblTrgError
        self._asicId    = int(_asicId)
        self._frameCnt  = int(_frameCnt)

        _format = 'AsicID={0:<%d} FrameCnt={1:<%d} Timeout={2:<%d} Overflow={3:<%d} Underflow={4:<%d} DecodeError={5:<%d} GlblTrgError={6:<%d} ' % (2, 11, 1, 1, 1, 1, 1)

        if self._headerErr or self.verbose:
            print(f"/////////////////////////////////////////////////////////////////////////////////////////////")
            print(_format.format(_asicId, _frameCnt, _timeout, _overflow, _underflow, _decodeError, _glblTrgError))
            print(f"/////////////////////////////////////////////////////////////////////////////////////////////")
            if self._headerErr:
                click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)
                click.secho(f"[ERROR]: Error Flag Raised!", bg='red', blink=True)
                click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)

    #################################################################
    def TrailerEval(self, trailer):
        _timeoutErrCnt  = (trailer >> np.uint8(56)) & np.uint8(0xFF)
        _frameErrCnt    = (trailer >> np.uint8(48)) & np.uint8(0xFF)
        _overflowErrCnt = (trailer >> np.uint8(40)) & np.uint8(0xFF)
        _decodeErrCnt   = (trailer >> np.uint8(32)) & np.uint8(0xFF)
        _eventCnt       = (trailer >> np.uint8( 0)) & np.uint32(0xFFFFFFFF)

        self._eventCnt = int(_eventCnt)

        # mismatch between internal-to-FPGA counter and ASIC frame counter
        if self._eventCnt != self._frameCnt:
            self._trailerErr = True

        _format = 'AsicID={0:<%d} EventCnt={1:<%d} TimeoutErrCnt={2:<%d} FrameErrCnt={3:<%d} OverflowErrCnt={4:<%d} DecodeErrCnt={5:<%d} ' % (2, 11, 4, 4, 4, 4)

        if self._trailerErr or self.verbose:
            print(f"-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=")
            print(_format.format(self._asicId, _eventCnt, _timeoutErrCnt, _frameErrCnt, _overflowErrCnt, _decodeErrCnt))
            print(f"-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=")
            if self._trailerErr:
                click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)
                click.secho(f"[ERROR]: EventCnt and FrameCnt Mismatch!", bg='red', blink=True)
                click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)


    #################################################################
    def EventParseFsm(self, frame, size):
        """
        Not a simple data packet -> an FSM-style logic is needed
        Data Format:
        First an FPGA-generated header arrives...
        If that header does not have an error, the samples follow...
        64 repetitions of 6x64-bit words is the entire data frame that follows the header;
        An FPGA-generated trailer closes the sub-frame.
        If there are more than one ASICs in the system, more headers/data follow
        """

        state = "preamble_s"
        index = 0
        preamIndex = 0
        preamble = []
        header   = []
        trailer  = []

        while index < size:
            if state == "preamble_s":

                # accumulate the entire preamble
                while preamIndex < self._preambleLen:
                    preamble.append(frame[index])
                    preamIndex += 1
                    index += 1

                preambleHex = ''.join(format(x, '02x') for x in preamble)
                self.PreambleEval(preambleHex)
                break

            # --------------------------------------------------------------------------------------
            # elif state == "parseData_s":
            #     _hitSlice   = []
            #     _allDataHex = 0

            #     for i in range(6):
            #         _hitSlice.insert(0, frame[index]) # prepend!
            #         index += 1

            #     _allDataHex = ''.join([hex(num)[2:].zfill(16) for num in _hitSlice])
            #     samplesHex, samplesInt = self.HitAlloc(_allDataHex, _frameCnt, samplesHex, samplesInt)

            #     _frameCnt += 1
            #     if _frameCnt == 64:
            #         self.samples[self._asicId] = samplesInt

            #         if self.verbose and len(samplesHex) > 0:
            #             self.HitPrinter(header=self.headers[-1], sampleMatrix=samplesHex)

            #         state = "trailer_s"
            #     else:
            #         state = "parseData_s"

            # # --------------------------------------------------------------------------------------
            # elif state == "trailer_s":
            #     self.TrailerEval(trailer=frame[index])
            #     self.trailers.append(frame[index])
            #     index += 1
            #     state = "header_s"

    #################################################################

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
def toAscii(inputArg):

    asciiChars = []

    # first convert to hex (and remove the "0x" prefix)
    hexString = hex(inputArg)[2:]

    # ensure the hex string length is even
    if len(hexString) % 2 != 0:
        hexString = '0' + hexString

    for i in range(0, len(hexString), 2):
        _byteHex = hexString[i:i+2]
        _byteInt = int(_byteHex, 16)
        _char    = chr(_byteInt)
        asciiChars.append(_char)

    retString = ''.join(asciiChars)

    return retString
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~