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
                 asicType = "SparkPixS",
                 verbose  = False,
                 **kwargs):

        """
        Class for the lane/serializer data
        """

        self.reset(asicType=asicType, verbose=verbose)


    #################################################################
    def reset(self, asicType, verbose):
        """
        Easily accesible
        """

        # class parameters (parameters have _ prefix)
        self._asicTypeSet = asicType
        self._verbose     = verbose

        # header contents
        self.overOcc        = False
        self.pause          = False
        self.colErr         = False
        self.pauseErr       = False
        self.dummy          = False
        self.timeout        = False
        self.trgCnt         = 0

        # populated by asicParamSet() (parameters have _ prefix)
        self._numOfCols     = None
        self._dataLen       = None

        # initialize the values
        self.asicParamSet()

        self.colBitmask     = [False] * self._numOfCols
        self.colOverOcc     = [False] * self._numOfCols
        self.colPause       = [False] * self._numOfCols
        self.colId          = [0]     * self._numOfCols
        self.colTrgCnt      = [0]     * self._numOfCols
        self.colLen         = [0]     * self._numOfCols
        self.laneHits       = [None]  * self._numOfCols

        # evaluated by this class
        self.headerErr      = False
        self.decErr         = False

        # data index
        self.dataIndexStart = 0
        self.dataIndexEnd   = 0

        # flag indicating that we are done processing
        self.done           = False

    #################################################################

    #################################################################
    def formatter(self, data):
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

        # Determine the total number of words (64-bit entries) in the frame
        self.wordSize = len(dat)

        # Parse them in
        self.eventParseFsm(frame=dat, size=self.wordSize)
    #################################################################

    #################################################################
    def dataIndexStartSet(self, dataIndex):
        """
        Externally set the data index
        """
        self.dataIndexStart = dataIndex
    #################################################################

    #################################################################
    def asicParamSet(self):
        """
        Sets the parameters of the frame length depending on the ASIC type
        """
        if self._asicTypeSet == 'SparkPixS':
            self._numOfCols = 24
            self._dataLen   = 5
        elif self._asicTypeSet == 'SparkPixT':
            self._numOfCols = 24
            self._dataLen   = 8
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
        _dummyPrint = "~~~~~~~~~~~~~~~~~~~~~~~~~~~ Dummy Header ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

        # there's gotta be a better way to code this...
        if self._asicTypeSet == 'SparkPixS':
            self.overOcc  = (_header >> 39) & 0x1
            self.pause    = (_header >> 38) & 0x1
            self.colErr   = (_header >> 37) & 0x1
            self.pauseErr = (_header >> 36) & 0x1
            self.dummy    = (_header >> 35) & 0x1
            self.timeout  = (_header >> 34) & 0x1
            _colBitmask   = (_header >>  8) & 0xFFFFFF
            self.trgCnt   = (_header >>  0) & 0xFF
        elif self._asicTypeSet == 'SparkPixT':
            self.overOcc  = (_header >> 63) & 0x1
            self.pause    = (_header >> 62) & 0x1
            self.colErr   = (_header >> 61) & 0x1
            self.pauseErr = (_header >> 60) & 0x1
            self.dummy    = (_header >> 59) & 0x1
            self.timeout  = (_header >> 58) & 0x1
            _colBitmask   = (_header >>  8) & 0xFFFFFF
            self.trgCnt   = (_header >>  0) & 0xFF

        self.colBitmask = [(_colBitmask >> i) & 1 == 1 for i in range(self._numOfCols)]

        self.headerErr = self.colErr or self.pauseErr or self.timeout

        if self.preambleErr or self._verbose:
            _format = 'OverOcc={0:<1} Pause={1:<1} ColumnError={2:<1} PauseError={3:<1} Timeout={4:<1} Bitmask={5:<%24x} Trigger={6:<4}'
            print(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
            if not(self.dummy):
                print(_format.format(self.overOcc, self.pause, self.colErr, self.pauseErr, self.timeout, _colBitmask, self.trgCnt))
            else:
                print(_dummyPrint)
            print(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
        if self.preambleErr:
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

        if _colTrgCnt != self.colTrgCnt
            _mismatch = True

        self.colOverOcc[colBmskId] = bool(_colOverOcc)
        self.colPause[colBmskId]   = bool(_colPause)
        self.colId[colBmskId]      = _colId
        self.colTrgCnt[colBmskId]  = _colTrgCnt
        self.colLen[colBmskId]     = _colLen

        if self.decErr:
            click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)
            click.secho(f"[ERROR]: Column ID Decoding Error!", bg='red', blink=True)
            click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)

        if _mismatch:
            click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~", bg='yellow')
            click.secho(f"[WARNING]: Column Trigger Counter Mismatch!", bg='yellow')
            click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~", bg='yellow')
    #################################################################

    #################################################################
    def hitAlloc(self, colBmskId, hitData, hitLen):
        """
        Populates the associated data type with the hits
        What happens to those hits and how they are decoded is determined later
        """
        if self._asicTypeSet == 'SparkPixS':
            hit0 = (hitData >> 20) & 0xFFFFF
            hit1 = (hitData >> 0)  & 0xFFFFF
        elif self._asicTypeSet == 'SparkPixT':
            hit0 = (hitData >> 32) & 0xFFFFFFFF
            hit1 = (hitData >> 0)  & 0xFFFFFFFF

        self.laneHits[colBmskId].append(hit0)

        if hitLen > 1:
            self.laneHits[colBmskId].append(hit1)

    #################################################################

    #################################################################
    # def HitPrinter(self, header, sampleMatrix):
    #     _format = 'AsicID={0:<%d} FrameCnt={1:<%d} SampleID={2:<%d} ChannelID={3:<%d} ADC={4:<%d} {5:<%d}' % (2, 11, 3, 3, 5, 5)

    #     _asicId   = (header >> np.uint8(48)) & np.uint16(0xFFFF)
    #     _frameCnt = (header >> np.uint8( 0)) & np.uint32(0xFFFFFFFF)

    #     for row in range(64):
    #         for col in range(32):
    #             _channelId = row
    #             _sampleId  = col
    #             _sample = sampleMatrix[row][col]
    #             print(_format.format(_asicId, _frameCnt, _sampleId, _channelId, str(int(str(_sample), 16)), "(" + "0x"+str(_sample)) + ")")
    #         print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
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

        state    = "header_s"
        index    = self.dataIndexStart
        subIndex = 0
        colSel   = 0
        subLen   = 0
        word     = []

        while index < size and not(self.done):
            # --------------------------------------------------------------------------------------
            if state == "header_s":
                # accumulate the entire header
                while subIndex < self._dataLen:
                    word.append(frame[index])
                    subIndex += 1
                    index    += 1

                headerHex = ''.join(format(x, '02x') for x in word)
                self.headerEval(headerHex)

                word.clear() # clear and reset
                subIndex = 0

                if self.colBitmask != 0 and self.dummy == False:
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
                # accumulate the entire column metadata word
                while subIndex < self._dataLen:
                    word.append(frame[index])
                    subIndex += 1
                    index    += 1

                colMetaHex = ''.join(format(x, '02x') for x in word)
                self.colMetaEval(colSel, colMetaHex)

                word.clear() # clear and reset
                subIndex = 0

                subLen = self.colLen[colSel]

                # check this! there is a chance that after a post-pause-release,
                # a column does not have more hits and writes dataLen = 0
                if subLen > 0:
                    state = "parseHits_s"
                else:
                    colSel += 1
                    state = "bitmaskCheck_s"

            # --------------------------------------------------------------------------------------
            elif state == "parseHits_s"
                # accumulate the entire column data word
                while subIndex < self._dataLen:
                    word.append(frame[index])
                    subIndex += 1
                    index    += 1

                dataHex = ''.join(format(x, '02x') for x in word)
                self.hitAlloc(colSel, dataHex, subLen)

                word.clear() # clear and reset
                subIndex = 0

                subLen -= 2

                if subLen <= 0 and colSel < self._numOfCols:
                    colSel += 1
                    subLen = 0
                    state  = "bitmaskCheck_s"

            #################################################################

        if self.done:
            self.dataIndexEnd = index

        if self.done and self._verbose and not(self.dummy):
            print(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
            print(f"Trigger = {self.trgCnt} decoding Done. Next Event...")
            print(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")

    #################################################################
