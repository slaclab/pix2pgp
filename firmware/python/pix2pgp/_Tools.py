# -------------------------------------------------------------------------------
# -- This file is part of 'Pix2Pgp'.
# -- It is subject to the license terms in the LICENSE.txt file found in the
# -- top-level directory of this distribution and at:
# --    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# -- No part of 'Pix2Pgp', including this file,
# -- may be copied, modified, propagated, or distributed except according to
# -- the terms contained in the LICENSE.txt file.
# -------------------------------------------------------------------------------
import click
import numpy as np

class Tools:

    @staticmethod
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    def toAscii(inputArg):
        hexString = format(int(inputArg), 'x')
        if len(hexString) % 2:
            hexString = '0' + hexString
        return bytes.fromhex(hexString).decode('ascii', errors='replace')
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    @staticmethod
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    def bytesToInt(data, byteorder='big'):
        '''
        Convert a numpy array/list of bytes to a Python integer.
        Explicit element iteration — avoids buffer protocol issues with numpy slices.
        '''
        if byteorder == 'big':
            result = 0
            for b in data:
                result = (result << 8) | int(b)
            return result
        else:
            result = 0
            for i, b in enumerate(data):
                result |= int(b) << (8 * i)
            return result

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    @staticmethod
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    def printError(inputArg):

        errorString = f"[ERROR]: {inputArg} Error!"
        _     = "~"
        delim = "~" * (len(errorString)-1) + _

        click.secho(delim,       bg='red', blink=True)
        click.secho(errorString, bg='red', blink=True)
        click.secho(delim,       bg='red', blink=True)
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    @staticmethod
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    def printWarning(inputArg):

        warningString = f"[WARNING]: {inputArg}!"
        _     = "~"
        delim = "~" * (len(warningString)-1) + _

        click.secho(delim,         bg='yellow')
        click.secho(warningString, bg='yellow')
        click.secho(delim,         bg='yellow')
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    @staticmethod
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    def wordSwap(inList, groupSize):
        '''
        Swap the endianness on a per-group basis;
        i.e. if inList = [0, 1, 2, 3, 4];
           _inListSwap = [2, 1, 0, 4, 3];
           (for groupSize = 3)
        '''
        arr = np.asarray(inList)
        n = len(arr)
        fullGroups = n // groupSize
        remainder = n % groupSize

        if fullGroups > 0:
            main = arr[:fullGroups * groupSize].reshape(fullGroups, groupSize)[:, ::-1].ravel()
        else:
            main = np.array([], dtype=arr.dtype)

        if remainder > 0:
            tail = arr[fullGroups * groupSize:][::-1]
            return np.concatenate([main, tail])

        return main
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    @staticmethod
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    def rawPrint(label, hexData):
        if isinstance(hexData, (list, np.ndarray)):
            _toPrint = "".join(f"{x:02x}" for x in hexData)
        else:
            _toPrint = hexData

        click.secho(f"{label}: {_toPrint}")

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    @staticmethod
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    def printStatistics(frameCnts, asicStats):
        '''
        Print the frame counters, and for each ASIC, the number of
        events in which each flag was set, per lane.
        Frame counter percentages are relative to the first entry of frameCnts.
        All other percentages are relative to the number of events of that ASIC.
        '''
        flags = ('laneValid', 'laneDecError', 'lanePauseError', 'laneFull',
                 'laneTimeout', 'laneDown', 'overOcc', 'pause')

        pct = lambda n, d: 100.0 * n / d if d else 0.0

        print("=" * 60)
        ref = next(iter(frameCnts.values()), 0)
        for label, cnt in frameCnts.items():
            print(f"{label:<26}: {cnt} ({pct(cnt, ref):.2f}%)")

        for asicId, s in sorted(asicStats.items()):
            nEvents = len(s['eventValid'])
            nValid  = sum(s['eventValid'])
            nRej    = nEvents - nValid
            nHits   = sum(len(h) for h in s['hits'])

            print("-" * 60)
            print(f"ASIC {asicId}: events = {nEvents}, hits = {nHits}, "
                  f"hits/valid event = {nHits / nValid if nValid else 0:.2f}")
            print(f"  {'valid':<15}: {nValid} ({pct(nValid, nEvents):.2f}%)")
            print(f"  {'rejected':<15}: {nRej} ({pct(nRej, nEvents):.2f}%)")

            for flag in flags:
                perLane = [sum(lane) for lane in zip(*s[flag])]
                txt = ", ".join(f"{n} ({pct(n, nEvents):.2f}%)" for n in perLane)
                print(f"  {flag:<15}: [{txt}]")

        print("=" * 60)
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    @staticmethod
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    def intToBits(value, width):
        '''
        Convert an integer bitmask to a list of bools, LSB first;
        i.e. intToBits(0b0101, 4) = [True, False, True, False]
        '''
        return [(value >> i) & 1 == 1 for i in range(width)]
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    @staticmethod
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    def orAccumulate(prev, new):
        '''
        Element-wise OR of two lists; None in prev is treated as False;
        i.e. orAccumulate([None, True, False], [False, False, True]) = [False, True, True]
        '''
        return [bool(p) or bool(n) for p, n in zip(prev, new)]
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
