import sys
import os
import click
import argparse
import binascii
import numpy as np
import time

# Set the argument parser
parser = argparse.ArgumentParser()

parser.add_argument(
    "--dataFile",
    type     = str,
    required = False,
    default  = '../firmware/ghdl/pix2pgpArbDataDump.dat',
    help     = "Default data file",
)

parser.add_argument(
    "--hitDecode",
    action   ="store_true",
    help     = "Set to true if data in testbench have upper 10 bits is ColID and lower as a cnt",
)

# Get the arguments
args = parser.parse_args()

def headerEval(header):
    empty  = True
    bitmask = []
    trigger = 0

    _overOcc = (header >> np.uint8(39)) & np.uint8(0x01)
    _dataFull = (header >> np.uint8(38)) & np.uint8(0x01)
    _statusFull = (header >> np.uint8(37)) & np.uint8(0x01)
    _alignError = (header >> np.uint8(36)) & np.uint8(0x01)
    _dummyHeader = (header >> np.uint8(35)) & np.uint8(0x01)
    # some reserved bits
    _bitmask = (header >> np.uint8(8)) & np.uint32(0xFFFFFF)
    _trigger = (header >> np.uint8(0)) & np.uint8(0xFF)

    _format = 'OverOcc={0:<%d} DataFull={1:<%d} StatusFull={2:<%d} AlignError={3:<%d} dummyHeader={4:<%d} Bitmask={5:<%02x} Trigger={6:<%d}' % (1, 1, 1, 1, 1, 8, 8)
    print(_format.format(_overOcc, _dataFull, _statusFull, _alignError, _dummyHeader, hex(_bitmask).upper(), _trigger))

    if not(_bitmask == 0):
        empty = False
        bitmask = _bitmask
        trigger = _trigger

    return empty, bitmask, trigger

def _hitPrinter(hits, decode):
    hit0 = (hits >> np.uint8(20)) & np.uint32(0xFFFFF)
    hit1 = (hits >> np.uint8(0)) & np.uint32(0xFFFFF)

    if decode:
        hitCnt0 = (hit0 >> np.uint8(0)) & np.uint8(0xFF)
        colId0  = (hit0 >> np.uint8(8)) & np.uint8(0xFF)
        hitCnt1 = (hit1 >> np.uint8(0)) & np.uint8(0xFF)
        colId1  = (hit1 >> np.uint8(8)) & np.uint8(0xFF)
        _format = 'ColId0={0:<%d} HitCnt0={1:<%d} ColId1={2:<%d} HitCnt1={3:<%d}' % (4, 4, 4, 4)
        print(_format.format(colId0, hitCnt0, colId1, hitCnt1))
    else:
        _format = 'Hit={0:<%d} Hit={1:<%d}' % (10, 10)
        print(_format.format(hit0, hit1))


def bitmaskCheck(bitmask, colSel):
    hasData = False
    if bitmask >> np.uint8(colSel) & np.uint8(0x01) == 1:
        hasData = True
    return hasData

#################################################################
if __name__ == "__main__":
    _file = args.dataFile

    if not(os.path.isfile(_file)):
        click.secho(f"[ERROR]: {_file} not found!", bg='red')
        sys.exit()

    with open(_file) as f:
        _lineArray = [int(line.rstrip('\n'), 16) for line in f]

    _line    = 0
    _isEmpty = False
    _len     = 0
    _lenCnt  = 0
    _colSel  = 0
    _bitmask = []
    _trigger = 0
    state    = "header_s"

    while _line < len(_lineArray):
        match state:
            ########################################################################################
            case "header_s":
                _colSel = 0
                _isEmpty, _bitmask, _trigger = headerEval(_lineArray[_line])
                _line += 1
                if not(_isEmpty):
                    state = "bitmaskCheck_s"
            ########################################################################################
            case "bitmaskCheck_s":
                # time.sleep(0.2)
                if _colSel < 24:
                    if bitmaskCheck(_bitmask, _colSel):
                        state = "lenParse_s"
                    else:
                        _colSel += 1
                else:
                    print(f"Trigger = {_trigger} decoding Done. Next Event...")
                    state = "header_s"
            ########################################################################################
            case "lenParse_s":
                # time.sleep(0.2)
                _len = _lineArray[_line]
                print(f"================================================")
                print(f"Length of Hits = {_len} for Col = {_colSel}")
                _lenCnt = _len
                state = "hitDecode_s"
                _line += 1
            ########################################################################################
            case "hitDecode_s":
                # time.sleep(0.2)
                _hitPrinter(_lineArray[_line], args.hitDecode)
                _lenCnt = _lenCnt - 2
                _line += 1
                if _lenCnt <= 0:
                    _colSel += 1
                    state = "bitmaskCheck_s"
                    print(f"================================================")
