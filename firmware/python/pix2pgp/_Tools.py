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
