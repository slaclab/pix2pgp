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
        byte_len = (inputArg.bit_length() + 7) // 8 or 1
        return inputArg.to_bytes(byte_len, byteorder='big').decode('ascii', errors='replace')
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
    def rawPrint(enable, label, hexData):
        if enable:
            if isinstance(hexData, (list, np.ndarray)):
                _toPrint = "".join(f"{x:02x}" for x in hexData)
            else:
                _toPrint = hexData

            click.secho(f"{label}: {_toPrint}")

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
