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
_pix2pgpVerbose = 3
_maxAsics       = 4
_hitPrintout    = True
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# set to true to see printout of SparseProcessor example
UseSparseProcessorExample = True
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
if UseSparseProcessorExample:

    dataReader = rogue.utilities.fileio.StreamReader()

    dataProcessor = pix2pgp.Pix2PgpSparseProcessor(
                        rawData  = False,
                        maxAsics = _maxAsics,
                        verbose  = _pix2pgpVerbose,
                        asicType = 'Thriglav'
                    )

    dataProcessor << dataReader

    dataReader.open(_dataFilePath)

    dataReader.closeWait()

    if _hitPrintout:
        for _asicId in dataProcessor.asicId:
            print(f"[INFO]: ASIC ID = {_asicId}")
            print(f"[INFO]: Number of Triggers: {len(dataProcessor.asicLaneValid[_asicId])=}")
            print(f"[INFO]: All Hits: {dataProcessor.asicHits[_asicId]=}")
            print(f"[INFO]: Trigger Counts of All Lanes: {dataProcessor.asicTrgCnt[_asicId]=}")

else:

    dbgFile   = False
    pixelTOA  = []
    pixelTOT  = []
    frameData = pix2pgp.AsicData(asicType='Thriglav',verbose=_pix2pgpVerbose)

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
