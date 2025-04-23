# -------------------------------------------------------------------------------
# -- This file is part of 'Pix2Pgp'.
# -- It is subject to the license terms in the LICENSE.txt file found in the
# -- top-level directory of this distribution and at:
# --    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# -- No part of 'Pix2Pgp', including this file,
# -- may be copied, modified, propagated, or distributed except according to
# -- the terms contained in the LICENSE.txt file.
# -------------------------------------------------------------------------------

import numpy as np
import click


class LaneData(object):
    def __init__(self,
                 verbose  = False,
                 maxAsics = 8,
                 **kwargs):
        """
        Initializes the data
        """
        self.headers     = []
        self.samples     = np.zeros((maxAsics, 64, 32))
        self.trailers    = []
        self._asicId     = 0
        self._frameCnt   = 0
        self._eventCnt   = 0
        self._headerErr  = False
        self._trailerErr = False

        self.verbose     = verbose

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
        dat = data.view(np.uint64)

        # Determine the total number of words (64-bit entries) in the frame
        self.wordSize = len(dat)

        self.EventParseFsm(frame=dat, size=self.wordSize)

    #################################################################
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
    def HitAlloc(self, data, frameCnt, samplesHex, samplesInt):
        """
        Allocates hits in the sample matrix
        Every row represents a channel
        Every column represents an ADC sample from that channel
        Returns Hex
        Also converts to Int and returns that as well
        """
        _sampleIndex = frameCnt

        for dataIndex in range(32):
            _channelIndex = dataIndex

            if frameCnt > 31:
                _sampleIndex  = frameCnt  - 32
                _channelIndex = dataIndex + 32

            samplesHex[abs(_channelIndex-63)][_sampleIndex] = data[dataIndex*3:dataIndex*3+3]
            samplesInt[abs(_channelIndex-63)][_sampleIndex] = int(data[dataIndex*3:dataIndex*3+3], 16)

        return samplesHex, samplesInt
    #################################################################

    #################################################################
    def HitPrinter(self, header, sampleMatrix):
        _format = 'AsicID={0:<%d} FrameCnt={1:<%d} SampleID={2:<%d} ChannelID={3:<%d} ADC={4:<%d} {5:<%d}' % (2, 11, 3, 3, 5, 5)

        _asicId   = (header >> np.uint8(48)) & np.uint16(0xFFFF)
        _frameCnt = (header >> np.uint8( 0)) & np.uint32(0xFFFFFFFF)

        for row in range(64):
            for col in range(32):
                _channelId = row
                _sampleId  = col
                _sample = sampleMatrix[row][col]
                print(_format.format(_asicId, _frameCnt, _sampleId, _channelId, str(int(str(_sample), 16)), "(" + "0x"+str(_sample)) + ")")
            print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
    #################################################################


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

        state = "header_s"
        _word = 0

        while _word < size:
        # ------------------------------------------------------------------------------------------
            if state == "header_s":
                self.HeaderEval(header=frame[_word])

                if not(self._headerErr):
                    _frameCnt = 0
                    self.headers.append(frame[_word])
                    samplesHex = [[0] * 32 for _ in range(64)]
                    samplesInt = np.zeros((64, 32))
                    _word += 1
                    state = "parseData_s"
                else:
                    _word += 1
                    state == "trailer_s"

            # --------------------------------------------------------------------------------------
            elif state == "parseData_s":
                _hitSlice   = []
                _allDataHex = 0

                for i in range(6):
                    _hitSlice.insert(0, frame[_word]) # prepend!
                    _word += 1

                _allDataHex = ''.join([hex(num)[2:].zfill(16) for num in _hitSlice])
                samplesHex, samplesInt = self.HitAlloc(_allDataHex, _frameCnt, samplesHex, samplesInt)

                _frameCnt += 1
                if _frameCnt == 64:
                    self.samples[self._asicId] = samplesInt

                    if self.verbose and len(samplesHex) > 0:
                        self.HitPrinter(header=self.headers[-1], sampleMatrix=samplesHex)

                    state = "trailer_s"
                else:
                    state = "parseData_s"

            # --------------------------------------------------------------------------------------
            elif state == "trailer_s":
                self.TrailerEval(trailer=frame[_word])
                self.trailers.append(frame[_word])
                _word += 1
                state = "header_s"

    #################################################################
