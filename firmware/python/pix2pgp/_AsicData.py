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

        # the real initialization method
        self.reset()

    #################################################################
    def reset(self):
        """
        Reset Class variables
        """

        # initialize the lane decoding class
        self.laneDecoder = pix2pgp.LaneData(asicType=self._asicTypeSet, verbose=self._verbose)

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

        # call after self.asicParamSet
        # header
        self.headerErr   = False
        self.laneValid   = [None] * self._numOfLanes
        self.laneTimeout = [None] * self._numOfLanes
        self.laneError   = [None] * self._numOfLanes

        # data
        self.asicHits    = [None] * self._numOfLanes

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

        if self.preambleErr or self._verbose:
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

        if self.headerErr or self._verbose:
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

        if self.trailerErr or self._verbose:
            print(f"")
            print(f"-=-=-=-=-=-=-=-=-=-=-=-=-=-=- Pix2Pgp Frame End -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=")
            print(f"")
            if self.trailerErr:
                click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)
                click.secho(f"[ERROR]: Trailer Error!", bg='red', blink=True)
                click.secho(f"~~~~~~~~~~~~~~~~~~~~~~~", bg='red', blink=True)
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
                    state = "bitmaskCheck_s"
                else:
                    state = "trailer_s"

            # --------------------------------------------------------------------------------------
            elif state == "bitmaskCheck_s":

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

                if not(self.laneDecoder.isEmpty):
                    self.asicHits[laneSel] = copy.deepcopy(self.laneDecoder.laneHits)

                index = copy.deepcopy(self.laneDecoder.dataIndexEnd)
                self.laneDecoder.reset()
                laneSel += 1
                state = "bitmaskCheck_s"

            # --------------------------------------------------------------------------------------
            elif state == "trailer_s":

                wordHex = ''.join(format(x, '02x') for x in frame[index:index + self._trailerLen])
                self.trailerEval(wordHex)
                index += self._trailerLen

                # will re-evaluate the preamble if there are more data
                state = "preamble_s"

    ################################################################
