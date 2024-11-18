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
    default  = '../firmware/ghdl/pix2pgpRxDataDump.dat',
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
    empty   = True
    reverse = False
    bitmask = []
    trigger = 0

    _overOcc     = (header >> np.uint8(39)) & np.uint8(0x01)
    _pause       = (header >> np.uint8(38)) & np.uint8(0x01)
    _columnFull  = (header >> np.uint8(37)) & np.uint8(0x01)
    _pauseError  = (header >> np.uint8(36)) & np.uint8(0x01)
    _dummyHeader = (header >> np.uint8(35)) & np.uint8(0x01)
    _reverseRead = (header >> np.uint8(34)) & np.uint8(0x01)

    # some reserved bits
    _bitmask = (header >> np.uint8(8)) & np.uint32(0xFFFFFF)
    _trigger = (header >> np.uint8(0)) & np.uint8(0xFF)

    _format = 'OverOcc={0:<%d} Pause={1:<%d} ColumnFull={2:<%d} PauseError={3:<%d} DummyHeader={4:<%d} Bitmask={5:<%02x} Trigger={6:<%d}' % (1, 1, 1, 1, 1, 8, 8)
    if _dummyHeader == 0:
        print(f"/////////////////////////////////////////////////////////////////////////")
    print(_format.format(_overOcc, _pause, _columnFull, _pauseError, _dummyHeader, hex(_bitmask).upper(), _trigger))
    if _dummyHeader == 0:
        print(f"/////////////////////////////////////////////////////////////////////////")

    if not(_bitmask == 0) and not(_dummyHeader):
        empty = False
        bitmask = _bitmask
        trigger = _trigger
        reverse = bool(_reverseRead)

    return empty, bitmask, trigger, reverse

def _hitPrinter(hits, decode, length):
    hit0 = (hits >> np.uint8(20)) & np.uint32(0xFFFFF)
    hit1 = (hits >> np.uint8(0)) & np.uint32(0xFFFFF)

    if decode:
        hitCnt0 = (hit0 >> np.uint16(0))  & np.uint16(0x3FF)
        colId0  = (hit0 >> np.uint16(10)) & np.uint16(0x3F)
        hitTrg0 = (hit0 >> np.uint16(16)) & np.uint16(0x0F)
        hitCnt1 = (hit1 >> np.uint16(0))  & np.uint16(0x3FF)
        colId1  = (hit1 >> np.uint16(10)) & np.uint16(0x3F)
        hitTrg1 = (hit1 >> np.uint16(16)) & np.uint16(0x0F)
        _format = 'ColId0={0:<%d} HitCnt0={1:<%d} hitTrg0={2:<%d} ColId1={3:<%d} HitCnt1={4:<%d} hitTrg1={5:<%d}' % (4, 4, 4, 4, 4, 4)
        if length == 1:
            _format = 'ColId0={0:<%d} HitCnt0={1:<%d} hitTrg0={2:<%d}' % (4, 4, 4)
            print(_format.format(colId0, hitCnt0, hitTrg0))
        else:
            print(_format.format(colId0, hitCnt0, hitTrg0, colId1, hitCnt1, hitTrg1))
    else:
        _format = 'Hit={0:<%d} Hit={1:<%d}' % (10, 10)
        if length == 1:
            _format = 'Hit={0:<%d}' % (10)
            print(_format.format(hit0))
        else:
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
    _reverse = 0
    state    = "header_s"

    print(f"/////////////////////////////////////////////////////////////////////////")
    while _line < len(_lineArray):
        ########################################################################################
        if state == "header_s":
            _colSel = 0
            _isEmpty, _bitmask, _trigger, _reverse = headerEval(_lineArray[_line])
            _line += 1
            if _reverse:
                _colSel = 24
            if not(_isEmpty):
                state = "bitmaskCheck_s"
        ########################################################################################
        elif state == "bitmaskCheck_s":
            if (_colSel < 24 and not(_reverse)) or (_colSel >= 0 and _reverse):
                if bitmaskCheck(_bitmask, _colSel):
                    state = "lenParse_s"
                else:
                    if not(_reverse):
                        _colSel += 1
                    else:
                        _colSel -= 1
            else:
                print(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
                print(f"Trigger = {_trigger} decoding Done. Next Event...")
                print(f"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
                state = "header_s"
        ########################################################################################
        elif state == "lenParse_s":
            # time.sleep(0.2)
            _len = _lineArray[_line]
            print(f"=========================================================================")
            print(f"Length of Hits = {_len} for Col = {_colSel}")
            _lenCnt = _len
            # check this! there is a chance that after a post-pause-release a column does
            # not have more hits and writes a dataLen=0
            if _len > 0:
                state = "hitDecode_s"
            else:
                if not(_reverse):
                    _colSel += 1
                else:
                    _colSel -= 1
                state = "bitmaskCheck_s"
            _line += 1
        ########################################################################################
        elif state == "hitDecode_s":
            # time.sleep(0.2)
            _hitPrinter(_lineArray[_line], args.hitDecode, _lenCnt)
            _lenCnt = _lenCnt - 2
            _line += 1
            if _lenCnt <= 0:
                if not(_reverse):
                    _colSel += 1
                else:
                    _colSel -= 1
                state = "bitmaskCheck_s"
                print(f"=========================================================================")
