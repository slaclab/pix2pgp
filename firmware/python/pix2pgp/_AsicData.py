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
                 asicType   = "SparkPixS",
                 asicData   = False,
                 fpgaTbData = False,
                 selfRst    = False,
                 verbose    = 0,
                 **kwargs):
        """
        Class for the entire ASIC dataset.
        Container for all datapoints associated with the ASIC.
        """

        # class parameters (parameters have _ prefix)
        self._asicType   = asicType
        self._asicData   = asicData
        self._fpgaTbData = fpgaTbData
        self._selfRst    = selfRst
        self._verbose    = verbose

        # the real initialization method
        self.reset()

    #################################################################
    def reset(self):
        """
        Reset Class variables
        """

        # populated by fpgaParameterSet() (parameters have _ prefix)
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
        self.asicType        = 0
        self.asicId          = 0
        self.fpgaId          = 0
        self.fpgaTrgCnt      = 0

        # asic-specific formats
        self.asicParams     = None
        self.fpgaDataFormat = None

        # initialize the values
        self.fpgaParameterSet()

        # initialize the lane decoding class
        self.laneDecoder = pix2pgp.LaneData(asicType=self._asicType,
                                            asicData=self._asicData,
                                            fpgaTbData=self._fpgaTbData,
                                            verbose=self._verbose)

        # call after self.fpgaParameterSet
        # fpga header
        self.headerErr      = False
        self.laneValid      = [None] * self.numOfLanes
        self.laneTimeout    = [None] * self.numOfLanes
        self.laneDecError   = [None] * self.numOfLanes
        self.lanePauseError = [None] * self.numOfLanes
        self.frameSize      = [0]    * self.numOfLanes

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

        self.colBitmask  = [False] * totalCols
        self.colOverOcc  = [False] * totalCols
        self.colPause    = [False] * totalCols
        self.colDecColId = [0]     * totalCols
        self.colTrgCnt   = [0]     * totalCols
        self.colLen      = [0]     * totalCols
        self.asicHits    = [[] for _ in range(totalCols)]

        # lane-decoder-assigned flags
        self.laneHeaderErr = [False] * self.numOfLanes
        self.laneDecErr    = [False] * self.numOfLanes
        self.laneIsEmpty   = [False] * self.numOfLanes

        # trailer
        self.trailerErr  = False

        # trigger misalignment flag
        self.asicGlblTrgCntMisalign = False

        # data index
        self.dataIndexStart = 0
        self.dataIndexEnd   = 0

        # flag indicating that we are done processing
        self.done = False
    #################################################################

    #################################################################
    def formatter(self, data, dataLen):
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

        dat = _dat.view(np.uint64)

        # Parse them in
        self.eventParseFsm(frame=dat, size=dataLen)
    #################################################################

    #################################################################
    def dataIndexStartSet(self, dataIndexStart):
        """
        Externally set the data index
        """
        self.dataIndexStart = dataIndexStart
    #################################################################

    #################################################################
    def fpgaParameterSet(self):
        """
        Sets the parameters of the frame length depending on the ASIC type
        """
        self.fpgaDataFormat = pix2pgp.FpgaRxDataFormat()

        if self._asicType == 'SparkPixS':
            self.asicParams = pix2pgp.SparkPixSParameters()

        elif self._asicType == 'SparkPixT':
            self.asicParams = pix2pgp.SparkPixTParameters()

        else:
            click.secho(f"[ERROR]: asicType parameter not set properly! options: SparkPixS, SparkPixT", bg='red')
            sys.exit()

        self.numOfLanes   = self.asicParams.asicParamExtract()['numOfLanes']
        self.numOfCols    = self.asicParams.asicParamExtract()['numOfCols']
        self.wordLen      = self.asicParams.asicParamExtract()['wordLen']
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
        if pix2pgp.Tools.toAscii(_dict['pix2pgpId']) != "pix2pgp":
            self.preambleErr = True
        elif self.asicType != self.asicParams.asicParamExtract()['asicTypeId']:
            self.typeMismatchErr = True

        if ((self.preambleErr or self.typeMismatchErr) and self._verbose > 0) or self._verbose > 1:
            print(f"")
            print(f"+=+=+=+=+=+=+=+=+=+=+=+=+=+= Pix2Pgp Frame Begin =+=+=+=+=+=+=+=+=+=+=+=+=+=+=")
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
        self.laneValid      = [(_dict['laneValid'] >> i) & 1 == 1 for i in range(
                                                                                self.numOfLanes)]

        self.headerErr = ( _dict['laneDecError'] > 0 or
                           _dict['laneTimeout']  > 0 or
                           _dict['laneFull'] > 0)

        if (self.headerErr and self._verbose > 0) or self._verbose > 1:
            _format = 'LaneDecError, LanePauseError, LaneFull, LaneTimeout  =  0x{0:<02X}, 0x{1:<02X}, 0x{2:<02X}, 0x{3:<02X}'
            print(f"~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=")
            print(_format.format(
                _dict['laneDecError'], _dict['lanePauseError'],
                _dict['laneFull'], _dict['laneTimeout'],
            ))
            print(f"~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=")
            if self.headerErr:
                pix2pgp.Tools.printError('FPGA Header')
    #################################################################

    #################################################################
    def trailerEval(self, trailer):
        """
        Parses in the trailer
        """
        _dict = self.fpgaDataFormat.fpgaTrailerDecoder(trailer=trailer)

        if pix2pgp.Tools.toAscii(_dict['pix2pgpId']) != "pix2pgp":
            self.trailerErr = True

        if (self.trailerErr and self._verbose > 0) or self._verbose > 1:
            print(f"")
            print(f"-=-=-=-=-=-=-=-=-=-=-=-=-=-=- Pix2Pgp Frame End -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=")
            print(f"")
            if self.trailerErr:
                pix2pgp.Tools.printError('FPGA Trailer')
    #################################################################

    #################################################################
    def allocWide(self, oldVar, newVar, offset):
        oldVar[offset:offset + self.numOfCols] = [
            newVar[idx] for idx in range(self.numOfCols)]
    #################################################################

    #################################################################
    def extractLaneData(self, laneSel):
        """
        Extracts lane data from the lane decoder into the AsicData class arrays.
        """
        if laneSel < self.numOfLanes:
            # ~~~~~~~~~~~~~~~~~~~~~~~~~
            # header data
            # ~~~~~~~~~~~~~~~~~~~~~~~~~

            self.asicGlblOverOcc[laneSel]    = self.laneDecoder.overOcc
            self.asicGlblPause[laneSel]      = self.laneDecoder.pause
            self.asicGlblColErr[laneSel]     = self.laneDecoder.colErr
            self.asicGlblPauseErr[laneSel]   = self.laneDecoder.pauseErr
            self.asicGlblDummy[laneSel]      = self.laneDecoder.dummy
            self.asicGlblColTimeout[laneSel] = self.laneDecoder.timeout
            self.asicGlblTrgCnt[laneSel]     = self.laneDecoder.trgCnt

            # Errors and status flags
            self.laneHeaderErr[laneSel]      = self.laneDecoder.headerErr
            self.laneDecErr[laneSel]         = self.laneDecoder.decErr
            self.laneIsEmpty[laneSel]        = self.laneDecoder.isEmpty

            offset = laneSel * self.numOfCols

            self.colBitmask[offset:offset  + self.numOfCols] = self.laneDecoder.colBitmask
            self.colOverOcc[offset:offset  + self.numOfCols] = self.laneDecoder.colOverOcc
            self.colPause[offset:offset    + self.numOfCols] = self.laneDecoder.colPause
            self.colLen[offset:offset      + self.numOfCols] = self.laneDecoder.colLen
            self.colDecColId[offset:offset + self.numOfCols] = self.laneDecoder.colId
            self.colTrgCnt[offset:offset   + self.numOfCols] = self.laneDecoder.colTrgCnt

            # Actual hits
            if not self.laneIsEmpty[laneSel]:
                for colIdx in range(self.numOfCols):
                    self.asicHits[offset + colIdx].extend((self.laneDecoder.laneHits[colIdx]))
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

        state   = "preamble_s"
        index   = self.dataIndexStart
        laneSel = 0
        pause   = False

        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        while index < size and not(self.done):
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            # --------------------------------------------------------------------------------------
            if state == "preamble_s":
                laneSel = 0

                wordHex = ''.join(format(x, '02x') for x in frame[index:index + self.preambleLen])
                self.preambleEval(wordHex)

                index += self.preambleLen
                state = "header_s"

            # --------------------------------------------------------------------------------------
            elif state == "header_s":

                wordHex = ''.join(format(x, '02x') for x in frame[index:index + self.headerLen])
                self.headerEval(wordHex)

                index += self.headerLen

                if any(self.laneValid):
                    state = "frameSize_s"
                else:
                    state = "trailer_s"

            # --------------------------------------------------------------------------------------
            elif state == "frameSize_s":
                if laneSel < self.numOfLanes:

                    wordHex = ''.join(format(x, '02x') for x in frame[
                        index:index + self.frameSizeLen])

                    self.frameSize[laneSel] = int(wordHex, 16)

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

                _frameSlice = frame[index:index + self.frameSize[laneSel] * self.wordLen]

                self.laneDecoder.laneIdSet(laneId=laneSel)
                self.laneDecoder.formatter(data=_frameSlice, dataLen=len(_frameSlice))

                while not(self.laneDecoder.done):
                    time.sleep(0.1) # crude; sleep before checking again

                # update the index
                index += self.laneDecoder.dataIndexEnd

                self.extractLaneData(laneSel=laneSel)
                self.laneDecoder.reset()

                laneSel += 1
                state = "laneValidCheck_s"

            # --------------------------------------------------------------------------------------
            elif state == "trailer_s":

                wordHex = ''.join(format(x, '02x') for x in frame[index:index + self.trailerLen])
                self.trailerEval(wordHex)
                index += self.trailerLen

                laneSel = 0
                self.done = self._selfRst

        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        if index >= size:
            self.done = True

        if self.done:
            self.dataIndexEnd = index

            # trigger counter check
            if not(all(x == self.asicGlblTrgCnt[0] for x in self.asicGlblTrgCnt)):
                self.asicGlblTrgCntMisalign = True

            self.asicDataPrinter()
    #################################################################

    #################################################################
    def asicDataPrinter(self):
        """
        Prints out all the data
        """
        if self.asicGlblTrgCntMisalign and self._verbose > 0:
            pix2pgp.Tools.printWarning('ASIC Global Trigger Counter Mismatch. Values below')
            print(', '.join(str(value) for value in self.asicGlblTrgCnt))

        if self._verbose > 3:
            for name, value in self.__dict__.items():
                print(f"self.asicData.{name} = {value}")
    #################################################################