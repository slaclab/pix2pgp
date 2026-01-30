import sys
import os
import click
import argparse
import time
import numpy as np

import pyrogue as pr
import pyrogue.utilities.fileio

import copy

import rogue
rogue.Version.minVersion('6.1.0')

top_level = os.path.realpath(__file__).split('software')[0]
sys.path.append(top_level+'firmware/python/')

import rogue.interfaces.stream as ris

import pix2pgp

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
_dataFilePath='/sdf/group/faders/users/ruckman/project/3d-integrated-lgad-gen2/software/data/extSmaStopExample.dat'
_verbosity = 4
_accum     = False
_maxAsics  = 1
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# set to true to see printout of sparkpix-s example
sparkPixExample = False
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


if sparkPixExample:

    # Class for handling data
    class SparseProcessor(pr.DataReceiver):
        # Init method must call the parent class init
        def __init__(self,
                     verbose=3,
                     maxAsics=1,
                     rawData=False,
                     hidden=True,
                     accum=False,
                     **kwargs):

            pr.Device.__init__(self, hidden=hidden, **kwargs)
            ris.Slave.__init__(self)
            pr.DataReceiver.__init__(self, enableOnStart=True, hideData=True, hidden=hidden, **kwargs)

            self._verbose = verbose
            self._rawData = rawData
            self._accum   = accum

            self.asicLaneValid = [[] for _ in range(maxAsics)]
            self.asicHits      = [[] for _ in range(maxAsics)]
            self.asicTrgCnt    = [[] for _ in range(maxAsics)]

            self.asicDecoder = pix2pgp.AsicData(asicType='Thriglav',
                                                rawData=self._rawData,
                                                verbose=self._verbose)
            # self.RxEnable.set(value=True)

        # Method which is called when a frame is received
        def _acceptFrame(self, frame):

            # First it is good practice to hold a lock on the frame data.
            with frame.lock():

                _channel = frame.getChannel()

                # Parse the frame and update the local data containers
                _frame = frame.getNumpy(0, frame.getPayload())
                _dataLen = len(_frame)

                self.asicDecoder.reset()

                self.asicDecoder.formatter(_frame, _dataLen)

                while not(self.asicDecoder.done):
                    time.sleep(0.1) # crude; sleep before checking again

                _asicId = copy.deepcopy(self.asicDecoder.asicId)

                if self._accum:
                    self.asicLaneValid[_asicId].append(copy.deepcopy(self.asicDecoder.laneValid))
                    self.asicHits[_asicId].append(copy.deepcopy(self.asicDecoder.asicHits))
                    self.asicTrgCnt[_asicId].append(copy.deepcopy(self.asicDecoder.asicGlblTrgCnt))
                else:
                    self.asicLaneValid[_asicId] = copy.deepcopy(self.asicDecoder.laneValid)
                    self.asicHits[_asicId]      = copy.deepcopy(self.asicDecoder.asicHits)
                    self.asicTrgCnt[_asicId]    = copy.deepcopy(self.asicDecoder.asicGlblTrgCnt)

    dataReader = rogue.utilities.fileio.StreamReader()

    dataProcessor = SparseProcessor(
                        rawData     = False,
                        maxAsics    = _maxAsics,
                        verbose     = _verbosity,
                        hidden      = True,
                        accum       = _accum,
                    )

    dataProcessor << dataReader

    dataReader.open(_dataFilePath)

    dataReader.closeWait()

else:

    dbgFile   = False
    pixelTOA  = []
    pixelTOT  = []
    frameData = pix2pgp.AsicData(asicType='Thriglav',verbose=_verbosity)

    # Open the data file
    with pr.utilities.fileio.FileReader(files=_dataFilePath) as fd:

        # Loop through the file data
        for header,data in fd.records():

            # Look at record header data if debugging or error detected
            if dbgFile or (header.error>0):

                print(f"Processing record. Total={fd.totCount}, Current={fd.currCount}")
                print(f"Record size    = {header.size}")
                print(f"Record channel = {header.channel}")
                print(f"Record flags   = {header.flags:#x}")
                print(f"Record error   = {header.error:#x}")

            # Check for TDC stream data channel
            if header.channel == 0:
                # Process the data
                # frameData.reset()

                frameData.formatter(np.frombuffer(data, dtype=np.uint8), len(data))

                # Get a useful pointer
                hits = frameData.asicHits

                if hits:
                    for hit in hits:
                        # Fill the data array
                        pixelTOA.append(hits[0]['toa'])
                        pixelTOT.append(hits[0]['tot'])
