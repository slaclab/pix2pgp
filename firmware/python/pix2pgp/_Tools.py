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
import inspect

class Tools:

    @staticmethod
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    def toAscii(inputArg):
        n = (inputArg.bit_length() + 7) // 8 or 1
        return inputArg.to_bytes(n, 'big').decode('latin-1')
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
        n = len(inList)
        _inListSwap = list(inList)
        for i in range(0, n, groupSize):
            _inListSwap[i:i + groupSize] = _inListSwap[i:i + groupSize][::-1]
        return _inListSwap
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    @staticmethod
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    def rawPrint(enable, label, hexData):
        if enable:
            _toPrint = hexData

            if isinstance(hexData, list):
                _toPrint = "".join(f"{x:02x}" for x in hexData)

            click.secho(f"{label}: {_toPrint}")

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
