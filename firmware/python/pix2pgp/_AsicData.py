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
import time

import copy
import pix2pgp

class AsicData(object):
    def __init__(self,
                 asicType  = "SparkPixS",
                 rawData   = False,
                 oldFormat = False,
                 verbose   = 0,
                 **kwargs):
        """
        Class for the entire ASIC dataset.
        Container for all datapoints associated with the ASIC.
        """

        # class parameters (parameters have _ prefix)
        self._asicType    = asicType
        self._rawData     = rawData
        self._verbose     = verbose
        self._oldFormat   = oldFormat
        self._hitPrint    = self._verbose == 4
        self._headerPrint = self._verbose > 1 and not(self._hitPrint)

        # initialize the lane decoding class
        self.laneDecoder = pix2pgp.LaneData(asicType=self._asicType,
                                            rawData=self._rawData,
                                            verbose=self._verbose)

        # the real initialization method
        self.reset()
        self.currentIndex = 0 # Initialize a class variable for current index
    #################################################################
    def reset(self):
        """
        Reset Class variables
        """
        # flag indicating that we are done processing
        self.done = False

        # populated by asicParamSet() (parameters have _ prefix)
        self.numOfLanes   = None
        self.numOfCols    = None
        self.wordLen      = None
        self.preambleLen  = None
        self.headerLen    = None
        self.trailerLen   = None
        self.frameSizeLen = None

        # populated by the data themselves
        # preamble
        self.preambleErr     = False
        self.typeMismatchErr = False
        self.dropFrame       = False
        self.streamRxFrame   = False
        self.asicType        = 0
        self.asicId          = 0
        self.fpgaId          = 0
        self.fpgaTrgCnt      = 0

        # asic-specific formats
        self.asicParams     = None
        self.fpgaDataFormat = None

        # initialize the values
        self.asicParamSet()

        # call after self.asicParamSet
        # fpga header
        self.headerErr      = False
        self.laneValid      = [None] * self.numOfLanes
        self.laneTimeout    = [None] * self.numOfLanes
        self.laneDecError   = [None] * self.numOfLanes
        self.lanePauseError = [None] * self.numOfLanes
        self.laneDown       = [None] * self.numOfLanes
        self.frameSize      = [0]    * self.numOfLanes
        self.activeColCnt   = [0]    * self.numOfLanes

        # asic-global data (from headers of each lane)
        self.asicGlblOverOcc    = [False]  * self.numOfLanes
        self.asicGlblPause      = [False]  * self.numOfLanes
        self.asicGlblColErr     = [False]  * self.numOfLanes
        self.asicGlblPauseErr   = [False]  * self.numOfLanes
        self.asicGlblDummy      = [False]  * self.numOfLanes
        self.asicGlblColTimeout = [False]  * self.numOfLanes
        self.asicGlblTrgCnt     = [0]      * self.numOfLanes

        # unroll the list dimensions into a single list for each data point
        totalCols = self.numOfLanes * self.numOfCols

        self.colHitmask  = [False] * totalCols
        self.colTimeout  = [False] * totalCols
        self.colOverOcc  = [False] * totalCols
        self.colPause    = [False] * totalCols
        self.colDecColId = [0]     * totalCols
        self.colTrgCnt   = [0]     * totalCols
        self.colLen      = [0]     * totalCols
        self.asicHits    = []

        # lane-decoder-assigned flags
        self.laneHeaderErr = [False] * self.numOfLanes
        self.laneDecErr    = [False] * self.numOfLanes
        self.laneHasData   = [False] * self.numOfLanes

        # trailer
        self.trailerErr = False

        # trigger misalignment flag
        self.asicGlblTrgCntMisalign = False
    #################################################################

    #################################################################
    def formatter(self, data, dataLen, startIndex=0): # Added startIndex
        """
        Parses raw frame data and extracts specific fields based on predefined bit masks.

        Parameters:
        data (numpy array): Input array containing raw frame data to be formatted.
        dataLen (int): Length of the data in bytes or number of words.
        startIndex (int): Starting index within the data array

        Processing Steps:
        - The input data is interpreted as 64-bit unsigned integers.
        - Specific fields are extracted using bitwise operations and slicing.
        - Extracted fields are stored in their respective attributes of the class.
        """

        # Reset all attributes
        self.reset()

        # Set the current index to the starting position
        self.currentIndex = startIndex

        # Convert input data to 64-bit unsigned integers for consistent processing;
        # Parse them in
        self.eventParseFsm(frame=np.array(data), size=dataLen)
    #################################################################

    #################################################################
    def verboseSet(self, verbose):
        """
        Externally set the verbosity level
        """
        self._verbose     = verbose
        self._hitPrint    = self._verbose == 4
        self._headerPrint = self._verbose > 1 and not(self._hitPrint)
        self.laneDecoder.verboseSet(verbose)
    #################################################################

    #################################################################
    def rawDataFormatSet(self, rawData):
        """
        Externally set the raw data type;
        """
        self._rawData = rawData
        self.laneDecoder.rawDataFormatSet(rawData)
    #################################################################

    #################################################################
    def asicParamSet(self):
        """
        Sets the parameters of the frame length depending on the ASIC type
        """
        self.fpgaDataFormat = pix2pgp.FpgaRxDataFormat()

        try:
            self.asicParams = pix2pgp.AsicParameterBase.asicParams[self._asicType]()
        except KeyError:
            click.secho(f"[ERROR]: asicType parameter not set properly! options: {', '.join(_asicParams.keys())}", bg='red')
            sys.exit()

        self.numOfLanes   = self.asicParams.asicParamExtract()['numOfLanes']
        self.numOfCols    = self.asicParams.asicParamExtract()['numOfCols']
        self.wordLen      = self.asicParams.asicParamExtract()['wordLen']

        self.fpgaDataFormat.asicNumOfLanesSet(numOfLanes=self.numOfLanes)

        self.preambleLen  = self.fpgaDataFormat.fpgaParamExtract()['preambleLen']
        self.headerLen    = self.fpgaDataFormat.fpgaParamExtract()['headerLen']
        self.frameSizeLen = self.fpgaDataFormat.fpgaParamExtract()['frameSizeLen']
        self.trailerLen   = self.fpgaDataFormat.fpgaParamExtract()['trailerLen']
    #################################################################

    #################################################################
    def preambleEval(self, preamble):
        """
        Parses in the preamble and returns
        """

        _dict = self.fpgaDataFormat.fpgaPreambleDecoder(preamble=preamble)

        self.asicType   = _dict['asicType']
        self.asicId     = _dict['asicId']
        self.fpgaId     = _dict['fpgaId']
        self.fpgaTrgCnt = _dict['fpgaTrgCnt']

        # error-checking
        if pix2pgp.Tools.toAscii(_dict['pix2pgpId']) != "pixpgp":
            self.preambleErr = True

        # type-checking (both pix2pgp frame and asic-type)
        if _dict['pix2pgpType'] == 0:
            self.streamRxFrame = True
        elif self.asicType == 0:
            self.dropFrame = True
        elif self.asicType != self.asicParams.asicParamExtract()['asicTypeId']:
            self.typeMismatchErr = True

        _errorPrint = (self.preambleErr or self.typeMismatchErr) and self._verbose > 0

        if (_errorPrint or self._headerPrint) and self.streamRxFrame:
            print(f"")
            print(f"+=+=+=+=+=+=+=+=+=+=+= Pix2Pgp AsicStreamRx Frame Begin =+=+=+=+=+=+=+=+=+=+=+")
            print(f"")
            _format = 'AsicType={0:<20} AsicId={1:<8} FpgaId={2:<11x} FpgaTrgCnt={3:<8}'
            print(_format.format(self.asicParams.asicParamExtract()['asicType'],
                  self.asicId,
                  self.fpgaId,
                  self.fpgaTrgCnt))
            print(f"")

            if self.preambleErr:
                pix2pgp.Tools.printError('Preamble')

            if self.typeMismatchErr:
                pix2pgp.Tools.printError('ASIC Type Mismatch')

            if self.dropFrame:
                pix2pgp.Tools.printWarning('Dropped Frame')
    #################################################################

    #################################################################
    def headerEval(self, header):
        """
        Parses in the FPGA header, and returns the status of the lanes
        """
        _dict = self.fpgaDataFormat.fpgaHeaderDecoder(header=header)

        self.laneDecError   = [(_dict['laneDecError'] >> i) & 1 == 1 for i in range(
                                                                                self.numOfLanes)]
        self.lanePauseError = [(_dict['lanePauseError'] >> i) & 1 == 1 for i in range(
                                                                                self.numOfLanes)]
        self.laneFull       = [(_dict['laneFull'] >> i) & 1 == 1 for i in range(
                                                                                self.numOfLanes)]
        self.laneTimeout    = [(_dict['laneTimeout'] >> i) & 1 == 1 for i in range(
                                                                                self.numOfLanes)]
        self.laneDown       = [(_dict['laneDown'] >> i) & 1 == 1 for i in range(
                                                                                self.numOfLanes)]
        self.laneValid      = [(_dict['laneValid'] >> i) & 1 == 1 for i in range(
                                                                                self.numOfLanes)]

        self.headerErr = ( _dict['laneDecError'] > 0 or
                           _dict['laneFull'] > 0)

        _errorPrint = self.headerErr and self._verbose > 0

        if _errorPrint or self._headerPrint:
            _format = 'Lane: DecError, Full, Timeout, Down, Valid       =     0x{0:<01X}, 0x{1:<01X}, 0x{2:<01X}, 0x{3:<01X} 0x{4:<01X}'
            print(f"~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=")
            print(_format.format(
                _dict['laneDecError'], _dict['laneFull'],
                _dict['laneTimeout'], _dict['laneDown'],
                _dict['laneValid']
            ))
            print(f"~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=")

            if self.headerErr:
                pix2pgp.Tools.printError('FPGA Rx: Lane')

            if any(self.laneTimeout) and self._verbose > 2:
                pix2pgp.Tools.printWarning('FPGA Rx: Lane Timeout')
    #################################################################

    #################################################################
    def trailerEval(self, trailer):
        """
        Parses in the trailer
        """
        _dict = self.fpgaDataFormat.fpgaTrailerDecoder(trailer=trailer)

        if pix2pgp.Tools.toAscii(_dict['pix2pgpId']) != "pixpgp":
            self.trailerErr = True

        _errorPrint = self.trailerErr and self._verbose > 0

        if _errorPrint or self._headerPrint:
            print(f"")
            print(f"-=-=-=-=-=-=-=-=-=-=-=- Pix2Pgp AsicStreamRx Frame End -=-=-=-=-=-=-=-=-=-=-=-")
            print(f"")

            if self.trailerErr:
                pix2pgp.Tools.printError('FPGA Trailer')
    #################################################################

    #################################################################
    def extractLaneData(self, laneSel):
        """
        Extracts lane data from the lane decoder into the AsicData class arrays.
        """
        # ~~~~~~~~~~~~~~~~~~~~~~~~~
        # header data
        # ~~~~~~~~~~~~~~~~~~~~~~~~~
        self.asicGlblOverOcc[laneSel] = (
            np.array(self.asicGlblOverOcc[laneSel]) |
            np.array(self.laneDecoder.overOcc)).tolist()

        self.asicGlblPause[laneSel] = (
            np.array(self.asicGlblPause[laneSel]) |
            np.array(self.laneDecoder.pause)).tolist()

        self.asicGlblColErr[laneSel] = (
            np.array(self.asicGlblColErr[laneSel]) |
            np.array(self.laneDecoder.colErr)).tolist()

        self.asicGlblPauseErr[laneSel] = (
            np.array(self.asicGlblPauseErr[laneSel]) |
            np.array(self.laneDecoder.pauseErr)).tolist()

        self.asicGlblDummy[laneSel] = (
            np.array(self.asicGlblDummy[laneSel]) |
            np.array(self.laneDecoder.dummy)).tolist()

        self.asicGlblColTimeout[laneSel] = (
            np.array(self.asicGlblColTimeout[laneSel]) |
            np.array(self.laneDecoder.timeout)).tolist()

        # should not change within the same event
        self.asicGlblTrgCnt[laneSel] = self.laneDecoder.trgCnt

        # Errors and status flags
        self.laneDecErr[laneSel] = (
            np.array(self.laneDecErr[laneSel]) |
            np.array(self.laneDecoder.decErr)).tolist()

        self.laneHasData[laneSel] = (
            np.array(self.laneHasData[laneSel]) |
            np.array(self.laneDecoder.hasData)).tolist()

        offset = laneSel * self.numOfCols

        self.colHitmask[offset:offset + self.numOfCols] = (
            np.array(self.colHitmask[offset:offset + self.numOfCols]) |
            np.array(self.laneDecoder.colHitmask)).tolist()

        self.colTimeout[offset:offset + self.numOfCols] = (
            np.array(self.colTimeout[offset:offset + self.numOfCols]) |
            np.array(self.laneDecoder.colTimeout)).tolist()

        self.colOverOcc[offset:offset + self.numOfCols] = (
            np.array(self.colOverOcc[offset:offset + self.numOfCols]) |
            np.array(self.laneDecoder.colOverOcc)).tolist()

        self.colPause[offset:offset + self.numOfCols] = (
            np.array(self.colPause[offset:offset + self.numOfCols]) |
            np.array(self.laneDecoder.colPause)).tolist()

        self.colDecColId[offset:offset + self.numOfCols] = (
            np.array(self.colDecColId[offset:offset + self.numOfCols]) |
            np.array(self.laneDecoder.colId)).tolist()

        # each column-length accumulates on itself for each frame
        self.colLen[offset:offset + self.numOfCols] = (
            np.array(self.colLen[offset:offset + self.numOfCols]) +
            np.array(self.laneDecoder.colLen)).tolist()

        # should not change within the same event
        self.colTrgCnt[offset:offset + self.numOfCols] = self.laneDecoder.colTrgCnt

        # Actual hits
        if self.laneHasData[laneSel]:
            for hit in self.laneDecoder.laneHits:
                self.asicHits.append(hit)
    #################################################################

    #################################################################
    def eventParseFsm(self, frame, size):
        """
        Parsing the data in stages
        first is the preamble,
        then the FPGA-generated header,
        then the Lane Contents, where a sub-class is used,
        then the trailer.
        """

        state         = "preamble_s"
        index         = self.currentIndex
        _frameSize    = [0] * self.numOfLanes
        _activeColCnt = [0] * self.numOfLanes
        laneSel       = 0
        inPause       = False
        rawPrint      = True if self._verbose == 7 else False

        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        while index < size and not self.done:
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            # --------------------------------------------------------------------------------------
            if state == "preamble_s":

                _slice = frame[index:index + self.preambleLen]
                wordHex = ''.join(format(x, '02x') for x in _slice[::-1])
                pix2pgp.Tools.rawPrint(rawPrint, 'AsicData.Preamble', wordHex)

                self.preambleEval(wordHex)

                index += self.preambleLen

                # check if this is not a drop-frame and if this originated from asicStreamRx
                if not(self.streamRxFrame):
                    break
                elif not(self.dropFrame):
                    state = "header_s"
                else:
                    # in the special case of a drop-frame, a trailer follows the preamble
                    state = "trailer_s"

            # --------------------------------------------------------------------------------------
            elif state == "header_s":

                _slice = frame[index:index + self.headerLen]

                wordHex = ''.join(format(x, '02x') for x in _slice[::-1])
                pix2pgp.Tools.rawPrint(rawPrint, 'AsicData.Header', wordHex)

                self.headerEval(wordHex)


                index += self.headerLen
                state = "frameSize_s"

            # --------------------------------------------------------------------------------------
            elif state == "frameSize_s":

                if laneSel < self.numOfLanes:

                    _slice = frame[index:index + self.frameSizeLen]

                    wordHex = ''.join(format(x, '02x') for x in _slice[::-1])
                    pix2pgp.Tools.rawPrint(rawPrint, 'AsicData.FrameSize', wordHex)

                    _frameSize[laneSel] = int(wordHex, 16)

                    # accumulate frameSize
                    self.frameSize[laneSel] = _frameSize[laneSel] + self.frameSize[laneSel]

                    index += self.frameSizeLen
                    laneSel += 1

                else:

                    laneSel = 0

                    # skip active-col-cnt stuff by default; this feature was deprecated Feb 2026
                    # To-Do: skip this check eventually
                    state = "laneValidCheck_s"

                    if self._oldFormat:
                        state = "activeColCnt_s"

            # --------------------------------------------------------------------------------------
            # To-Do: remove this state eventually
            elif state == "activeColCnt_s":

                if laneSel < self.numOfLanes:

                    _slice = frame[index:index + self.frameSizeLen]

                    wordHex = ''.join(format(x, '02x') for x in _slice[::-1])
                    pix2pgp.Tools.rawPrint(rawPrint, 'AsicData.ActiveColCnt', wordHex)

                    _activeColCnt[laneSel] = int(wordHex, 16)

                    # accumulate activeColCnt
                    self.activeColCnt[laneSel] = _activeColCnt[laneSel] + self.activeColCnt[laneSel]

                    index += self.frameSizeLen
                    laneSel += 1

                else:

                    laneSel = 0
                    state = "laneValidCheck_s"

            # --------------------------------------------------------------------------------------
            elif state == "laneValidCheck_s":

                if laneSel < self.numOfLanes:
                    if self.laneValid[laneSel]:
                        state = "lane_s"
                    else:
                        laneSel += 1
                else:
                    state = "trailer_s"

            # --------------------------------------------------------------------------------------
            elif state == "lane_s":

                _frameSlice = frame[index:index + _frameSize[laneSel] * self.wordLen]

                _frameSliceSwap = pix2pgp.Tools.wordSwap(_frameSlice, self.wordLen)

                _label = 'AsicData.AllLaneData.Lane=' + str(laneSel)
                pix2pgp.Tools.rawPrint(rawPrint, _label, _frameSliceSwap)

                self.laneDecoder.laneIdSet(laneId=laneSel)
                self.laneDecoder.formatter(data=_frameSliceSwap, dataLen=len(_frameSlice))

                while not(self.laneDecoder.done):
                    time.sleep(0.1) # crude; sleep before checking again

                self.extractLaneData(laneSel=laneSel)

                # update the index
                index += self.laneDecoder.dataIndexEnd

                inPause = self.laneDecoder.pause or inPause

                self.laneDecoder.reset()

                laneSel += 1
                state = "laneValidCheck_s"

            # --------------------------------------------------------------------------------------
            elif state == "trailer_s":

                if not(inPause) or self.headerErr:
                    _slice = frame[index:index + self.trailerLen]

                    wordHex = ''.join(format(x, '02x') for x in _slice[::-1])
                    pix2pgp.Tools.rawPrint(rawPrint, 'AsicData.Trailer', wordHex)

                    self.trailerEval(wordHex)

                    state = "end_s"
                else:
                    # reset and parse in another frame for this event
                    laneSel    = 0
                    _frameSize = [0] * self.numOfLanes
                    inPause    = False
                    state      = "header_s"

            # --------------------------------------------------------------------------------------
            elif state == "end_s":

                _frameSize    = [0] * self.numOfLanes
                _activeColCnt = [0] * self.numOfLanes
                laneSel       = 0
                inPause       = False
                self.done     = True
                index         += self.trailerLen

                # make sure this is set to something that makes sense if not using old format
                # To-Do: skip this check eventually
                if not(self._oldFormat):
                    self.activeColCnt = [None] * self.numOfLanes

                # trigger counter check
                validLane = next((index for index, value in enumerate(self.laneValid) if value is True), None)

                for lane in range(self.numOfLanes):
                    if self.laneValid[lane]:
                        if self.asicGlblTrgCnt[lane] != self.asicGlblTrgCnt[validLane]:
                            self.asicGlblTrgCntMisalign = True
                            break

                self.asicDataPrinter()

        self.currentIndex = index # Update the current index in the end
    #################################################################

    #################################################################
    def asicDataPrinter(self):
        """
        Prints out all the data
        """
        if self.asicGlblTrgCntMisalign and self._verbose > 0:
            pix2pgp.Tools.printWarning('ASIC Global Trigger Counter Mismatch. Values below')
            print(', '.join(str(value) for value in self.asicGlblTrgCnt))

        if self._hitPrint:
            self.laneDecoder.dataFormat.dataPrinter(self.asicHits, self._rawData)
            print(f"~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=")

        if self._verbose == 5:
            for name, value in self.__dict__.items():
                print(f"self.asicData.{name} = {value}")
    #################################################################
