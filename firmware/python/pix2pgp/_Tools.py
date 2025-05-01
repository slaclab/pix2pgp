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

        asciiChars = []

        # first convert to hex (and remove the "0x" prefix)
        hexString = hex(inputArg)[2:]

        # ensure the hex string length is even
        if len(hexString) % 2 != 0:
            hexString = '0' + hexString

        for i in range(0, len(hexString), 2):
            _byteHex = hexString[i:i+2]
            _byteInt = int(_byteHex, 16)
            _char    = chr(_byteInt)
            asciiChars.append(_char)

        retString = ''.join(asciiChars)

        return retString
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
