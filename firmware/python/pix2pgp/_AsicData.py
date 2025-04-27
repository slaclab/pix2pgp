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

import copy
import pix2pgp

class AsicData(object):
    def __init__(self,
                 asicType   = "SparkPixS",
                 asicData   = False,
                 fpgaTbData = False,
                 verbose    = 0,
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
        self._asicData    = asicData
        self._fpgaTbData  = fpgaTbData
        self._verbose     = verbose

        # the real initialization method
        self.reset()

    #################################################################
    def reset(self):
        """
        Reset Class variables
        """

        # populated by asicParamSet() (parameters have _ prefix)
        self._numOfLanes  = None
        self._numOfCols   = None
        self._preambleLen = None
        self._headerLen   = None
        self._trailerLen  = None

        # populated by the data themselves
        # preamble
        self.preambleErr  = False
        self.asicType     = 0
        self.asicId       = 0
        self.fpgaId       = 0

        # initialize the values
        self.asicParamSet()

        # initialize the lane decoding class
        self.laneDecoder = pix2pgp.LaneData(asicType=self._asicTypeSet,
                                            asicData=self._asicData,
                                            fpgaTbData=self._fpgaTbData,
                                            verbose=self._verbose)

        # call after self.asicParamSet
        # fpga header
        self.headerErr   = False
        self.laneValid   = [None] * self._numOfLanes
        self.laneTimeout = [None] * self._numOfLanes
        self.laneError   = [None] * self._numOfLanes

        # data from lane decoder
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        # lane header data
        self.laneGlblOverOcc    = [False] * self._numOfLanes
        self.laneGlblPause      = [False] * self._numOfLanes
        self.laneGlblColErr     = [False] * self._numOfLanes
        self.laneGlblPauseErr   = [False] * self._numOfLanes
        self.laneGlblDummy      = [False] * self._numOfLanes
        self.laneGlblColTimeout = [False] * self._numOfLanes
        self.laneColBitmask     = [[False] * self._numOfCols for _ in range(self._numOfLanes)]
        self.laneGlblTrgCnt     = [0]     * self._numOfLanes

        # lane column metadata
        self.laneColOverOcc = [[False] * self._numOfCols for _ in range(self._numOfLanes)]
        self.laneColPause   = [[False] * self._numOfCols for _ in range(self._numOfLanes)]
        self.laneColId      = [[0] * self._numOfCols     for _ in range(self._numOfLanes)]
        self.laneColTrgCnt  = [[0] * self._numOfCols     for _ in range(self._numOfLanes)]
        self.laneColLen     = [[0] * self._numOfCols     for _ in range(self._numOfLanes)]

        # data from all lanes
        self.asicHits = [[[] for _ in range(self._numOfCols)] for _ in range(self._numOfLanes)]

        # lane-decoder-assigned flags
        self.laneHeaderErr = [False] * self._numOfLanes
        self.laneDecErr    = [False] * self._numOfLanes
        self.laneIsEmpty   = [False] * self._numOfLanes
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        # trailer
        self.trailerErr  = False

        # flag indicating that we are done processing
        self.done        = False
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
    def asicParamSet(self):
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
    def preambleEval(self, preamble):
        """
        Parses in the preamble and returns
        """
        _preamble     = int(preamble, 16)
        _pix2pgpId    = (_preamble >> 96) & 0xFFFFFFFFFFFFFFFF
        self.asicType = (_preamble >> 64) & 0xFFFFFFFF
        self.asicId   = (_preamble >> 32) & 0xFFFFFFFF
        self.fpgaId   = (_preamble >>  0) & 0xFFFFFFFF

        # error-checking
        if pix2pgp.Tools.toAscii(_pix2pgpId) != "pix2pgp":
            self.preambleErr = True
        elif self._asicTypeSet != self.asicTypeDict.get(self.asicType):
            self.preambleErr = True

        if (self.preambleErr and self._verbose > 0) or self._verbose > 1:
            print(f"")
            print(f"+=+=+=+=+=+=+=+=+=+=+=+=+=+= Pix2Pgp Frame Begin =+=+=+=+=+=+=+=+=+=+=+=+=+=+=")
            print(f"")
            _format = 'AsicType={0:<22} AsicId={1:<23} FpgaId={2:<8x}'
            print(_format.format(self.asicTypeDict.get(self.asicType), self.asicId, self.fpgaId))
            print(f"")
            if self.preambleErr:
                click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)
                click.secho(f"[ERROR]: Preamble Error!", bg='red', blink=True)
                click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)
    #################################################################


    #################################################################
    def headerEval(self, header):
        """
        Parses in the FPGA header, and returns the status of the lanes
        """
        _header = int(header, 16)

        _laneError   = (_header >> 16) & 0xFF
        _laneTimeout = (_header >>  8) & 0xFF
        _laneValid   = (_header >>  0) & 0xFF

        self.laneError   = [(_laneError >> i) & 1 == 1 for i in range(self._numOfLanes)]
        self.laneTimeout = [(_laneTimeout >> i) & 1 == 1 for i in range(self._numOfLanes)]
        self.laneValid   = [(_laneValid >> i) & 1 == 1 for i in range(self._numOfLanes)]

        self.headerErr  = _laneError > 0 or _laneTimeout > 0

        if (self.headerErr and self._verbose > 0) or self._verbose > 1:
            _format = 'LaneError={0:08b}           LaneTimeout={1:08b}           LaneValid={2:08b}'
            print(f"~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=")
            print(_format.format(_laneError, _laneTimeout, _laneValid))
            print(f"~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=")
            if self.headerErr:
                click.secho(f"~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)
                click.secho(f"[ERROR]: Header Error!", bg='red', blink=True)
                click.secho(f"~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)
    #################################################################

    #################################################################
    def trailerEval(self, trailer):
        """
        Parses in the trailer
        """
        _trailer   = int(trailer, 16)
        _pix2pgpId = (_trailer >>  0) & 0xFFFFFFFFFFFFFFFF

        if pix2pgp.Tools.toAscii(_pix2pgpId) != "pix2pgp":
            self.trailerErr = True

        if (self.trailerErr and self._verbose > 0) or self._verbose > 1:
            print(f"")
            print(f"-=-=-=-=-=-=-=-=-=-=-=-=-=-=- Pix2Pgp Frame End -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=")
            print(f"")
            if self.trailerErr:
                click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)
                click.secho(f"[ERROR]: Trailer Error!", bg='red', blink=True)
                click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)
    #################################################################

    #################################################################
    def extractLaneData(self, laneSel):
        """
        Extracts lane data from the lane decoder into the AsicData class arrays.
        """
        if laneSel < self._numOfLanes:

            # ~~~~~~~~~~~~~~~~~~~~~~~~~
            # header data
            # ~~~~~~~~~~~~~~~~~~~~~~~~~
            # flags are cumulative in case we are in pause
            self.laneGlblOverOcc[laneSel]    = (self.laneGlblOverOcc[laneSel] or
                                               copy.deepcopy(self.laneDecoder.overOcc))
            self.laneGlblPause[laneSel]      = (self.laneGlblPause[laneSel] or
                                               copy.deepcopy(self.laneDecoder.pause))
            self.laneGlblColErr[laneSel]     = (self.laneGlblColErr[laneSel] or
                                               copy.deepcopy(self.laneDecoder.colErr))
            self.laneGlblPauseErr[laneSel]   = (self.laneGlblPauseErr[laneSel] or
                                               copy.deepcopy(self.laneDecoder.pauseErr))
            self.laneGlblDummy[laneSel]      = (self.laneGlblDummy[laneSel] or
                                               copy.deepcopy(self.laneDecoder.dummy))
            self.laneGlblColTimeout[laneSel] = (self.laneGlblColTimeout[laneSel] or
                                               copy.deepcopy(self.laneDecoder.timeout))

            # column bitmask is cumulative
            _bmsk = copy.deepcopy(self.laneDecoder.colBitmask)
            self.laneColBitmask[laneSel] = [
                value or _bmsk[idx] for idx, value in enumerate(self.laneColBitmask[laneSel])
            ]

            # gets the last trgCnt (hopefully does not change within pauses)
            self.laneGlblTrgCnt[laneSel] = copy.deepcopy(self.laneDecoder.trgCnt)

            # ~~~~~~~~~~~~~~~~~~~~~~~~~
            # column metadata
            # ~~~~~~~~~~~~~~~~~~~~~~~~~
            # individual column flags are cumulative in case we are in pause
            _ooc = copy.deepcopy(self.laneDecoder.colOverOcc)
            self.laneColOverOcc[laneSel] = [
                value or _ooc[idx] for idx, value in enumerate(self.laneColOverOcc[laneSel])
            ]

            _pause = copy.deepcopy(self.laneDecoder.colPause)
            self.laneColPause[laneSel] = [
                value or _pause[idx] for idx, value in enumerate(self.laneColPause[laneSel])
            ]

            # gets the last colId (hopefully does not change within pauses)
            self.laneColId[laneSel]      = copy.deepcopy(self.laneDecoder.colId)
            # gets the last trgCnt (hopefully does not change within pauses)
            self.laneColTrgCnt[laneSel]  = copy.deepcopy(self.laneDecoder.colTrgCnt)

            # increments the column Length
            _len = copy.deepcopy(self.laneDecoder.colLen)
            self.laneColLen[laneSel] = [
                value + _len[idx] for idx, value in enumerate(self.laneColLen[laneSel])
            ]

            # gets the last flags
            self.laneHeaderErr[laneSel]  = copy.deepcopy(self.laneDecoder.headerErr)
            self.laneDecErr[laneSel]     = copy.deepcopy(self.laneDecoder.decErr)
            self.laneIsEmpty[laneSel]    = copy.deepcopy(self.laneDecoder.isEmpty)

            # actual hits
            if not self.laneIsEmpty[laneSel]:
                for colIdx in range(self._numOfCols):
                    self.asicHits[laneSel][colIdx].extend(
                        copy.deepcopy(self.laneDecoder.laneHits[colIdx]))
    #################################################################

    #################################################################
    def eventParseFsm(self, frame, size):
        """
        Parsing the data in stages
        Fist is the preamble
        Then the FPGA-generated header
        Then the Lane Contents, where a sub-class is used
        Then the trailer
        """

        state   = "preamble_s"
        index   = 0
        laneSel = 0
        pause   = False

        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        while index < size:
            # --------------------------------------------------------------------------------------
            if state == "preamble_s":
                laneSel = 0

                wordHex = ''.join(format(x, '02x') for x in frame[index:index + self._preambleLen])
                self.preambleEval(wordHex)

                index += self._preambleLen
                state = "header_s"

            # --------------------------------------------------------------------------------------
            elif state == "header_s":

                wordHex = ''.join(format(x, '02x') for x in frame[index:index + self._headerLen])
                self.headerEval(wordHex)

                index += self._headerLen

                if any(self.laneValid):
                    state = "laneValidCheck_s"
                else:
                    state = "trailer_s"

            # --------------------------------------------------------------------------------------
            elif state == "laneValidCheck_s":

                if laneSel < self._numOfLanes:
                    if self.laneValid[laneSel]:
                        state = "lane_s"
                    else:
                        laneSel += 1
                else:
                    state = "trailer_s"

            # --------------------------------------------------------------------------------------
            elif state == "lane_s":

                self.laneDecoder.dataIndexStartSet(dataIndexStart=index)
                self.laneDecoder.laneIdSet(laneId=laneSel)
                self.laneDecoder.formatter(data=frame, dataLen=size)

                while not(self.laneDecoder.done):
                    time.sleep(0.1) # crude; sleep before checking again

                # get the index and the pause
                index = self.laneDecoder.dataIndexEnd
                pause = self.laneDecoder.pause

                self.extractLaneData(laneSel=laneSel)
                self.laneDecoder.reset()

                # check if this was a pause; if not, done with lane
                if not(pause):
                    laneSel += 1
                    state = "laneValidCheck_s"
                else:
                    # in pause, more data for this lane -> re-evaluate
                    state = "lane_s"

            # --------------------------------------------------------------------------------------
            elif state == "trailer_s":

                wordHex = ''.join(format(x, '02x') for x in frame[index:index + self._trailerLen])
                self.trailerEval(wordHex)
                index += self._trailerLen

                # will re-evaluate the preamble if there are more data
                state = "preamble_s"
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        if index >= size:
            for lane in range(self._numOfLanes): self.asicDataPrinter(laneSel=lane)
            self.done = True

    ################################################################

    #################################################################
    def asicDataPrinter(self, laneSel):
        """
        Prints out all the data
        """
        if laneSel < self._numOfLanes and self._verbose > 2:
            print(f"self.laneGlblOverOcc[{laneSel}]    = {self.laneGlblOverOcc[laneSel]}")
            print(f"self.laneGlblPause[{laneSel}]      = {self.laneGlblPause[laneSel]}")
            print(f"self.laneGlblColErr[{laneSel}]     = {self.laneGlblColErr[laneSel]}")
            print(f"self.laneGlblPauseErr[{laneSel}]   = {self.laneGlblPauseErr[laneSel]}")
            print(f"self.laneGlblDummy[{laneSel}]      = {self.laneGlblDummy[laneSel]}")
            print(f"self.laneGlblColTimeout[{laneSel}] = {self.laneGlblColTimeout[laneSel]}")
            print(f"self.laneGlblTrgCnt[{laneSel}]     = {self.laneGlblTrgCnt[laneSel]}")
            print(f"self.laneColBitmask[{laneSel}]     = {self.laneColBitmask[laneSel]}")

            # column metadata
            print(f"self.laneColOverOcc[{laneSel}] = {self.laneColOverOcc[laneSel]}")
            print(f"self.laneColPause[{laneSel}]   = {self.laneColPause[laneSel]}")
            print(f"self.laneColId[{laneSel}]      = {self.laneColId[laneSel]}")
            print(f"self.laneColTrgCnt[{laneSel}]  = {self.laneColTrgCnt[laneSel]}")
            print(f"self.laneColLen[{laneSel}]     = {self.laneColLen[laneSel]}")

            # lane-decoder-assigned flags
            print(f"self.laneHeaderErr[{laneSel}] = {self.laneHeaderErr[laneSel]}")
            print(f"self.laneDecErr[{laneSel}]    = {self.laneDecErr[laneSel]}")
            print(f"self.laneIsEmpty[{laneSel}]   = {self.laneIsEmpty[laneSel]}")

            # actual hits
            if not self.laneIsEmpty[laneSel]:
                print(f"self.asicHits[{laneSel}] = {self.asicHits[laneSel]}")
    #################################################################