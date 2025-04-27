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
                 asicType   = "SparkPixS",
                 asicData   = False,
                 fpgaTbData = False,
                 verbose    = 0,
                 laneId     = 0,
                 **kwargs):

        """
        Class for the lane/serializer data
        """

        # class parameters (parameters have _ prefix)
        self._asicTypeSet = asicType
        self._asicData    = asicData
        self._fpgaTbData  = fpgaTbData
        self._verbose     = verbose
        self._laneId      = laneId

        # the real initialization method
        self.reset()


    #################################################################
    def reset(self):
        """
        Reset Class variables
        """

        # populated by asicParamSet() (parameters have _ prefix)
        self._numOfCols     = None
        self._dataLen       = None

        # data format
        self.dataFormat     = None

        # initialize the values
        self.asicParamSet()

        # header contents
        self.overOcc        = False
        self.pause          = False
        self.colErr         = False
        self.pauseErr       = False
        self.dummy          = False
        self.timeout        = False
        self.colBitmask     = [False] * self._numOfCols
        self.trgCnt         = 0

        # column metadata
        self.colOverOcc     = [False] * self._numOfCols
        self.colPause       = [False] * self._numOfCols
        self.colId          = [0]     * self._numOfCols
        self.colTrgCnt      = [0]     * self._numOfCols
        self.colLen         = [0]     * self._numOfCols

        # lane hits
        self.laneHits       = [[] for _ in range(self._numOfCols)]

        # evaluated by this class
        self.headerErr      = False
        self.decErr         = False

        # data index
        self.dataIndexStart = 0
        self.dataIndexEnd   = 0

        # empty event
        self.isEmpty        = False

        # flag indicating that we are done processing
        self.done           = False
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
    def laneIdSet(self, laneId):
        """
        Externally set the data index
        """
        self._laneId = laneId
    #################################################################

    #################################################################
    def asicParamSet(self):
        """
        Sets the parameters of the frame length depending on the ASIC type
        """
        if self._asicTypeSet == 'SparkPixS':
            self._numOfCols = 24
            self._dataLen   = 5
            self.dataFormat = pix2pgp.SparkPixSDataFormat()
        elif self._asicTypeSet == 'SparkPixT':
            self._numOfCols = 24
            self._dataLen   = 8
            self.dataFormat = pix2pgp.SparkPixTDataFormat()
        else:
            click.secho(f"[ERROR]: asicType parameter not set properly! options: SparkPixS, SparkPixT", bg='red')
            sys.exit()
    #################################################################

    #################################################################
    def headerEval(self, header):
        """
        Parses-in the header and determines if there is an error or not
        Also prints-out the header metadata if needed
        """
        _header     = int(header, 16)
        _colBitmask = 0
        _lanePrint  = f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ LaneId = {self._laneId} ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

        # there's gotta be a better way to code this...
        if self._asicTypeSet == 'SparkPixS':
            self.overOcc  = bool((_header >> 39) & 0x1)
            self.pause    = bool((_header >> 38) & 0x1)
            self.colErr   = bool((_header >> 37) & 0x1)
            self.pauseErr = bool((_header >> 36) & 0x1)
            self.dummy    = bool((_header >> 35) & 0x1)
            self.timeout  = bool((_header >> 34) & 0x1)
            _colBitmask   = (_header >>  8) & 0xFFFFFF
            self.trgCnt   = (_header >>  0) & 0xFF
        elif self._asicTypeSet == 'SparkPixT':
            self.overOcc  = bool((_header >> 63) & 0x1)
            self.pause    = bool((_header >> 62) & 0x1)
            self.colErr   = bool((_header >> 61) & 0x1)
            self.pauseErr = bool((_header >> 60) & 0x1)
            self.dummy    = bool((_header >> 59) & 0x1)
            self.timeout  = bool((_header >> 58) & 0x1)
            _colBitmask   = (_header >>  8) & 0xFFFFFF
            self.trgCnt   = (_header >>  0) & 0xFF

        self.colBitmask = [(_colBitmask >> i) & 1 == 1 for i in range(self._numOfCols)]

        if _colBitmask == 0:
            self.isEmpty = True

        self.headerErr = bool(self.colErr or self.pauseErr or self.timeout)

        if ((self.headerErr and self._verbose > 0) or self._verbose > 1) and not(self.dummy):
            _format = 'OverOcc={0:<%d} Pause={1:<%d} ColError={2:<%d} PauseError={3:<%d} Timeout={4:<%d} Bitmask={5:<%02x} Trigger={6:<%d}' % (1, 1, 1, 1, 1, 8, 8)
            print(_lanePrint)
            print(_format.format(self.overOcc, self.pause, self.colErr, self.pauseErr, self.timeout, hex(_colBitmask).lower(), self.trgCnt))
            print(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
        if self.headerErr and self._verbose > 0:
            click.secho(f"~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)
            click.secho(f"[ERROR]: Header Error!", bg='red', blink=True)
            click.secho(f"~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)

    #################################################################

    #################################################################
    def colMetaEval(self, colBmskId, colMeta):
        """
        Parses-in the column metadata
        To-Do: *not* asic-specific for the time being
        """
        _colMeta    = int(colMeta, 16)
        _colOverOcc = 0
        _colPause   = 0
        _colId      = 0
        _colTrgCnt  = 0
        _colLen     = 0
        _mismatch   = False

        _colOverOcc = (_colMeta >> 25) & 0x1
        _colPause   = (_colMeta >> 24) & 0x1
        _colId      = (_colMeta >> 16) & 0xFF
        _colTrgCnt  = (_colMeta >>  8) & 0xFF
        _colLen     = (_colMeta >>  0) & 0xFF

        if _colId != colBmskId:
            self.decErr = True

        if _colTrgCnt != self.trgCnt:
            _mismatch = True

        self.colOverOcc[colBmskId] = bool(_colOverOcc)
        self.colPause[colBmskId]   = bool(_colPause)
        self.colId[colBmskId]      = _colId
        self.colTrgCnt[colBmskId]  = _colTrgCnt
        self.colLen[colBmskId]     = _colLen

        if self.decErr and self._verbose > 0:
            print(f"_colId = {_colId}")
            print(f"colBmskId = {colBmskId}")
            click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)
            click.secho(f"[ERROR]: Column ID Decoding Error!", bg='red', blink=True)
            click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)

        if _mismatch and self._verbose > 0:
            print(f"_colTrgCnt = {_colTrgCnt}")
            print(f"self.trgCnt = {self.trgCnt}")
            click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~", bg='yellow')
            click.secho(f"[WARNING]: Column Trigger Counter Mismatch!", bg='yellow')
            click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~", bg='yellow')
    #################################################################

    #################################################################
    def hitAlloc(self, colBmskId, hitData, hitLen):
        """
        Populates the associated data type with the hits
        """
        _hitData = int(hitData, 16)

        if self._asicTypeSet == 'SparkPixS':
            hit0 = (_hitData >> 20) & 0xFFFFF
            hit1 = (_hitData >>  0) & 0xFFFFF
        elif self._asicTypeSet == 'SparkPixT':
            hit0 = (_hitData >> 32) & 0xFFFFFFFF
            hit1 = (_hitData >>  0) & 0xFFFFFFFF

        self.laneHits[colBmskId].append(self.dataFormat(hit0=hit0,
                                                        hit1=hit1,
                                                        hitLen=hitLen,
                                                        asicData=self._asicData,
                                                        fpgaTbData=self._fpgaTbData))

    #################################################################

    #################################################################
    def eventParseFsm(self, frame, size):
        """
        Parsing the data in stages
        Fist is the ASIC-generated header
        if that header indicates that some columns have hits,
        the FSM will parse in the column Metadata and the associated hit data;
        for all columns with hits
        """

        state  = "header_s"
        index  = self.dataIndexStart
        colSel = 0
        subLen = 0

        while index < size and not(self.done):
            # --------------------------------------------------------------------------------------
            if state == "header_s":

                wordHex = ''.join(format(x, '02x') for x in frame[index:index + self._dataLen])
                self.headerEval(wordHex)

                index += self._dataLen

                if not(self.isEmpty) and self.dummy == False:
                    state = "bitmaskCheck_s"
                else:
                    self.done = True

            # --------------------------------------------------------------------------------------
            elif state == "bitmaskCheck_s":
                if colSel < self._numOfCols:
                    if self.colBitmask[colSel]:
                        state = "colMetaParse_s"
                    else:
                        colSel += 1
                else:
                    self.done = True

            # --------------------------------------------------------------------------------------
            elif state == "colMetaParse_s":

                wordHex = ''.join(format(x, '02x') for x in frame[index:index + self._dataLen])
                self.colMetaEval(colSel, wordHex)

                index += self._dataLen

                subLen = self.colLen[colSel]

                # check this! there is a chance that after a post-pause-release,
                # a column does not have more hits and writes dataLen = 0
                if subLen > 0:
                    state = "parseHits_s"
                else:
                    colSel += 1
                    state = "bitmaskCheck_s"

            # --------------------------------------------------------------------------------------
            elif state == "parseHits_s":

                wordHex = ''.join(format(x, '02x') for x in frame[index:index + self._dataLen])
                self.hitAlloc(colSel, wordHex, subLen)

                index += self._dataLen

                subLen -= 2

                if subLen <= 0:
                    colSel += 1
                    subLen = 0
                    state  = "bitmaskCheck_s"
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        if index >= size:
            self.done = True

        if self.done:
            self.dataIndexEnd = index
            self.laneDataPrinter()
            self.done = True

    #################################################################
    def laneDataPrinter(self):
        """
        Prints out all the data
        """
        if self._verbose > 3:
            print(f"self.laneDecoder.overOcc    = {self.overOcc}")
            print(f"self.laneDecoder.pause      = {self.pause}")
            print(f"self.laneDecoder.colErr     = {self.colErr}")
            print(f"self.laneDecoder.pauseErr   = {self.pauseErr}")
            print(f"self.laneDecoder.dummy      = {self.dummy}")
            print(f"self.laneDecoder.timeout    = {self.timeout}")
            print(f"self.laneDecoder.colBitmask = {self.colBitmask}")

            # column metadata
            print(f"self.laneDecoder.colOverOcc = {self.colOverOcc}")
            print(f"self.laneDecoder.colPause   = {self.colPause}")
            print(f"self.laneDecoder.colId      = {self.colId}")
            print(f"self.laneDecoder.colTrgCnt  = {self.colTrgCnt}")
            print(f"self.laneDecoder.colLen     = {self.colLen}")

            # flags
            print(f"self.laneDecoder.headerErr = {self.headerErr}")
            print(f"self.laneDecoder.decErr    = {self.decErr}")
            print(f"self.laneDecoder.isEmpty   = {self.isEmpty}")

            # indices
            print(f"self.laneDecoder.dataIndexStart = {self.dataIndexStart}")
            print(f"self.laneDecoder.dataIndexEnd   = {self.dataIndexEnd}")

            # actual hits
            if not self.isEmpty:
                print(f"self.laneDecoder.laneHits = {self.laneHits}")
    #################################################################
