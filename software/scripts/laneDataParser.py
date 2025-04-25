import sys
import os
import click
import argparse

import setupLibPaths
import pix2pgp

# Set the argument parser
parser = argparse.ArgumentParser()

parser.add_argument(
    "--dataFile",
    type     = str,
    required = False,
    default  = '../firmware/ghdl/pix2pgpRxDataDump.dat',
    help     = "Default data file",
)

parser.add_argument(
    "--hitDecode",
    action   ="store_true",
    help     = "Set to true if data in testbench have upper 10 bits is ColID and lower as a cnt",
)

parser.add_argument(
    "--asicType",
    type     = str,
    required = False,
    default  = 'SparkPixS',
    help     = "options: SparkPixS, SparkPixT",
)

# Get the arguments
args = parser.parse_args()

#################################################################
if __name__ == "__main__":
    _file = args.dataFile

    if not(os.path.isfile(_file)):
        click.secho(f"[ERROR]: {_file} not found!", bg='red')
        sys.exit()

    if args.asicType != "SparkPixS" and args.asicType != "SparkPixT":
        click.secho(f"[ERROR]: asicType flag not set properly! options: SparkPixS, SparkPixT", bg='red')
        sys.exit()

    with open(_file) as f:
        _dataArray = [int(line.rstrip('\n'), 16) for line in f]

    _dataArrayBytes = []

    for word in _dataArray:
        for i in range(5):  # 5 bytes in a 40-bit word
            byte = (word >> (8 * (4 - i))) & 0xFF
            _dataArrayBytes.append(byte)

    _eventSize   = len(_dataArrayBytes)
    currentIndex = 0

    laneDecoder = pix2pgp.LaneData(asicType=args.asicType, verbose=True)

    while _eventSize > currentIndex:
        laneDecoder.dataIndexStartSet(dataIndexStart=currentIndex)
        laneDecoder.formatter(data=_dataArrayBytes, dataLen=_eventSize)

        while not(laneDecoder.done):
            time.sleep(0.1) # crude; sleep before checking again

        currentIndex = laneDecoder.dataIndexEnd
        laneDecoder.reset()
