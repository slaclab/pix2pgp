#-----------------------------------------------------------------------------
# This file is part of the 'pix2pgp'. It is subject to
# the license terms in the LICENSE.txt file found in the top-level directory
# of this distribution and at:
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# No part of the 'pix2pgp', including this file, may be
# copied, modified, propagated, or distributed except according to the terms
# contained in the LICENSE.txt file.
#-----------------------------------------------------------------------------

import rogue.interfaces.stream as ris
import pyrogue as pr
import numpy as np

import pix2pgp

import copy

import rogue
rogue.Version.minVersion('6.1.0')

# Example Class for handling data
class Pix2PgpSparseProcessor(pr.DataReceiver):
    # Init method must call the parent class init
    def __init__(self,
                 verbose=1,
                 maxAsics=4,
                 asicType='SparkPixS',
                 rawData=False,
                 enableOnStart=True,
                 oldFormat=False,
                 hideData=True,
                 hidden=True,
                 **kwargs):

        pr.DataReceiver.__init__(self,
                                 enableOnStart=enableOnStart,
                                 hideData=hideData,
                                 hidden=hidden,
                                 **kwargs)

        self._rawData   = rawData
        self._verbose   = verbose
        self._maxAsics  = maxAsics
        self._asicType  = asicType
        self._oldFormat = oldFormat

        self.asicId        = []
        self.asicLaneValid = [[] for _ in range(maxAsics)]
        self.asicHits      = [[] for _ in range(maxAsics)]
        self.asicTrgCnt    = [[] for _ in range(maxAsics)]

        self.asicDecoder = pix2pgp.AsicData(asicType=self._asicType,
                                            oldFormat=self._oldFormat,
                                            rawData=self._rawData,
                                            verbose=self._verbose)

    # Method which is called when a frame is received
    def _acceptFrame(self, frame):

        # First it is good practice to hold a lock on the frame data.
        with frame.lock():

            # Parse the frame and update the local data containers
            _frame = frame.getNumpy(0, frame.getPayload())
            _dataLen = len(_frame)
            _startIndex = 0

            while _startIndex < _dataLen:

                # Call formatter to start parsing
                self.asicDecoder.formatter(data=_frame,
                                           dataLen=_dataLen,
                                           startIndex=_startIndex)

                # Get the ASIC ID and append it to a local list if not seen before
                _id = self.asicDecoder.asicId

                if _id not in self.asicId:
                    self.asicId.append(_id)

                # Accumulate the data
                self.asicLaneValid[_id].append(self.asicDecoder.laneValid.copy())
                self.asicHits[_id].append(self.asicDecoder.asicHits.copy())
                self.asicTrgCnt[_id].append(self.asicDecoder.asicGlblTrgCnt.copy())

                # Update startIndex for the next iteration
                _startIndex = self.asicDecoder.currentIndex
