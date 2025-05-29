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
import json
import sys
import pix2pgp

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

        # populated by asicSet() (parameters have _ prefix)
        self.numOfCols = None
        self.wordLen   = None

        # asic-specific formats
        self.asicParams        = None
        self.headerFormat      = None
        self.colMetadataFormat = None
        self.dataFormat        = None

        # initialize the values
        self.asicSet()

        # header contents
        self.overOcc    = False
        self.pause      = False
        self.colErr     = False
        self.pauseErr   = False
        self.dummy      = False
        self.timeout    = False
        self.colBitmask = [False] * self.numOfCols
        self.trgCnt     = 0

        # column metadata
        self.colOverOcc = [False] * self.numOfCols
        self.colPause   = [False] * self.numOfCols
        self.colId      = [0]     * self.numOfCols
        self.colTrgCnt  = [0]     * self.numOfCols
        self.colLen     = [0]     * self.numOfCols
        self.currColLen = [0]     * self.numOfCols

        # lane hits
        self.laneHits = [[] for _ in range(self.numOfCols)]

        # evaluated by this class
        self.headerErr = False
        self.decErr    = False

        # data index
        self.dataIndexStart = 0
        self.dataIndexEnd   = 0

        # empty event
        self.hasData = False

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

        # Convert input data to 64-bit unsigned integers for consistent processing;
        # Parse them in
        self.eventParseFsm(frame=np.array(data), size=dataLen)
    #################################################################

    #################################################################
    def dataIndexStartSet(self, dataIndexStart):
        """
        Externally set the data index
        """
        self.dataIndexStart = dataIndexStart
    #################################################################

    #################################################################
    def verboseSet(self, verbose):
        """
        Externally set the verbosity level
        """
        self._verbose = verbose
    #################################################################

    #################################################################
    def dataTypeSet(self, dataType):
        """
        Externally set the data type;
        It is either gonna be asicData=True or False
        """
        self._asicData = dataType
    #################################################################

    #################################################################
    def laneIdSet(self, laneId):
        """
        Externally set the data index
        """
        self._laneId = laneId
    #################################################################

    #################################################################
    def asicSet(self):
        """
        Sets the parameters depending on the ASIC type
        """
        if self._asicTypeSet == 'SparkPixS':
            self.asicParams        = pix2pgp.SparkPixSParameters()
            self.headerFormat      = pix2pgp.SparkPixSHeaderFormat()
            self.colMetadataFormat = pix2pgp.SparkPixSColMetadataFormat()
            self.dataFormat        = pix2pgp.SparkPixSDataFormat()

        elif self._asicTypeSet == 'SparkPixT':
            self.asicParams        = pix2pgp.SparkPixTParameters()
            self.headerFormat      = pix2pgp.SparkPixTHeaderFormat()
            self.colMetadataFormat = pix2pgp.SparkPixTColMetadataFormat()
            self.dataFormat        = pix2pgp.SparkPixTDataFormat()

        else:
            click.secho(f"[ERROR]: asicType parameter not set properly! options: SparkPixS, SparkPixT", bg='red')
            sys.exit()

        self.numOfCols = self.asicParams.asicParamExtract()['numOfCols']
        self.wordLen   = self.asicParams.asicParamExtract()['wordLen']
    #################################################################

    #################################################################
    def headerEval(self, header):
        """
        Parses-in the header and determines if there is an error or not
        Also prints-out the header metadata if needed
        """
        _colBitmask = 0
        _dict = self.headerFormat.headerDecoder(header=header)

        self.overOcc  = _dict['overOcc']
        self.pause    = _dict['pause']
        self.pauseErr = _dict['pauseErr']
        self.colErr   = _dict['colErr']
        self.dummy    = _dict['dummy']
        self.timeout  = _dict['timeout']
        _colBitmask   = _dict['colBitmask']
        self.trgCnt   = _dict['trgCnt']

        self.colBitmask = [(_colBitmask >> i) & 1 == 1 for i in range(self.numOfCols)]

        if _colBitmask != 0:
            self.hasData = True

        self.headerErr = bool(self.colErr or self.timeout)

        if self.headerErr and self._verbose > 1:
            pix2pgp.Tools.printError('Lane Header')
        if self.pauseErr and self._verbose > 2:
            pix2pgp.Tools.printWarning('Pause-Error')

    #################################################################

    #################################################################
    def colMetaEval(self, colBmskId, colMeta):
        """
        Parses-in the column metadata
        """
        _dict = self.colMetadataFormat.colMetadataDecoder(colMeta=colMeta)

        self.colOverOcc[colBmskId] = _dict['colOverOcc']
        self.colPause[colBmskId]   = _dict['colPause']
        self.colId[colBmskId]      = _dict['colId']
        self.colTrgCnt[colBmskId]  = _dict['colTrgCnt']

        self.currColLen[colBmskId] = _dict['colLen']
        self.colLen[colBmskId]     = self.currColLen[colBmskId] + self.colLen[colBmskId]

        if self.colId[colBmskId] != colBmskId:
            self.decErr = True
            if self._verbose > 1:
                print(f"self.colId[{colBmskId}] = {self.colId[colBmskId]}")
                print(f"colBmskId = {colBmskId}")
                pix2pgp.Tools.printError('Column ID Decoding')

        if self.colTrgCnt[colBmskId] != self.trgCnt and self._verbose > 2:
            print(f"self.colTrgCnt[{colBmskId}] = {self.colTrgCnt[colBmskId]}")
            print(f"self.trgCnt = {self.trgCnt}")
            pix2pgp.Tools.printWarning('Trigger Counter Mismatch')
    #################################################################

    #################################################################
    def hitAlloc(self, colBmskId, hitData, hitLen):
        """
        Populates the associated data type with the hits
        """
        _hit0, _hit1 = self.dataFormat.dataDecoder(hitData=hitData,
                                                   hitLen=hitLen,
                                                   asicData=self._asicData,
                                                   fpgaTbData=self._fpgaTbData)

        if hitLen > 1:
            self.laneHits[colBmskId].append(_hit0)
            self.laneHits[colBmskId].append(_hit1)
        else:
            self.laneHits[colBmskId].append(_hit0)

    #################################################################

    #################################################################
    def headerPrinter(self):
        _colBitmask = sum((1 << i) for i, bit in enumerate(self.colBitmask) if bool(bit))
        _lanePrint  = f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ LaneId = {self._laneId} ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

        _bitmaskPadding = int(self.numOfCols/4)
        _printPadding = (" " * abs(36 - _bitmaskPadding))

        # Change to True/False format
        _flags = 'OverOcc,  Pause,  ColErr,  PauseErr,  Timeout     =    0x{0:<01X}, 0x{1:<01X}, 0x{2:<01X}, 0x{3:<01X}, 0x{4:<01X}'
        _bmskTrg = f'ColumnBitmask = 0x{{0:0{_bitmaskPadding}X}} {{1}} AsicTiggerCounter = {{2:<d}}'

        print(_lanePrint)
        print(_flags.format(self.overOcc, self.pause, self.colErr, self.pauseErr, self.timeout))
        print(_bmskTrg.format(_colBitmask, _printPadding, self.trgCnt))
        print(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
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

        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        while index < size and not(self.done):
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            # --------------------------------------------------------------------------------------
            if state == "header_s":

                wordHex = ''.join(format(x, '02x') for x in frame[index:index + self.wordLen])
                self.headerEval(wordHex)

                index += self.wordLen

                if self.hasData and self.dummy == False:
                    state = "bitmaskCheck_s"
                else:
                    self.done = True

            # --------------------------------------------------------------------------------------
            elif state == "bitmaskCheck_s":
                if colSel < self.numOfCols:
                    if self.colBitmask[colSel]:
                        state = "colMetaParse_s"
                    else:
                        colSel += 1
                else:
                    self.done = True

            # --------------------------------------------------------------------------------------
            elif state == "colMetaParse_s":

                wordHex = ''.join(format(x, '02x') for x in frame[index:index + self.wordLen])
                self.colMetaEval(colSel, wordHex)

                index += self.wordLen

                subLen = self.currColLen[colSel]

                # check this! there is a chance that after a post-pause-release,
                # a column does not have more hits and writes dataLen = 0
                if subLen > 0:
                    state = "parseHits_s"
                else:
                    colSel += 1
                    state = "bitmaskCheck_s"

            # --------------------------------------------------------------------------------------
            elif state == "parseHits_s":

                wordHex = ''.join(format(x, '02x') for x in frame[index:index + self.wordLen])
                self.hitAlloc(colSel, wordHex, subLen)

                index += self.wordLen

                subLen -= 2

                if subLen <= 0:
                    colSel += 1
                    subLen = 0
                    state  = "bitmaskCheck_s"

        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

        if index >= size:
            self.done = True

        if self.done:
            self.laneDataPrinter()
            self.dataIndexEnd = index
    #################################################################

    #################################################################
    def laneDataPrinter(self):
        """
        Prints out all the data
        """
        if self._verbose > 2:
            self.headerPrinter()

        if self._verbose == 6:
            for name, value in self.__dict__.items():
                print(f"self.laneDecoder.{name} = {value}")
    #################################################################
