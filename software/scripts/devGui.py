#-----------------------------------------------------------------------------
# This file is part of the 'pix2pgp-emu'. It is subject to
# the license terms in the LICENSE.txt file found in the top-level directory
# of this distribution and at:
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# No part of the 'pix2pgp-emu', including this file, may be
# copied, modified, propagated, or distributed except according to the terms
# contained in the LICENSE.txt file.
#-----------------------------------------------------------------------------
import setupLibPaths
import sys

import argparse
import pyrogue.pydm
import pyrogue.gui
import pix2pgp as pix2pgpEmu

from PyQt5 import QtCore, QtWidgets

#################################################################

# Set the argument parser
parser = argparse.ArgumentParser()

# Convert str to bool
argBool = lambda s: s.lower() in ['true', 't', 'yes', '1']

# Add arguments
parser.add_argument(
    "--dev",
    type     = str,
    required = False,
    default  = '/dev/datadev_0',
    help     = "path to PCIe device or sim",
)

parser.add_argument(
    "--defaultFile",
    type     = str,
    required = False,
    default  = 'config/defaults.yml',
    help     = "default configuration file to be loaded at startup",
)

parser.add_argument(
    "--emuMode",
    type     = argBool,
    required = False,
    default  = False,
    help     = "Enables the emulation mode configuration",
)

parser.add_argument(
    "--pollEn",
    type     = argBool,
    required = False,
    default  = False,
    help     = "Enable auto-polling",
)

parser.add_argument(
    "--initRead",
    type     = argBool,
    required = False,
    default  = False,
    help     = "Enable read all variables at start",
)

parser.add_argument(
    "--linkRate",
    type     = int,
    required = False,
    default  = 512,
    help     = "In units of Mbps",
)

parser.add_argument(
    "--viewer",
    action   ="store_true",
    help     = "Bring-up the online viewer",
)

parser.add_argument(
    "--tcpPort",
    type     = int,
    required = False,
    default  = 11000,
    help     = "same port defined in the vhdl testbench",
)

# Get the arguments
args = parser.parse_args()

#################################################################

app = QtWidgets.QApplication(sys.argv)
guiTop = pyrogue.gui.GuiTop(group = 'Pix2PgpEmu GUI')

# Pix2PgpEmuBoard = pix2pgpEmu.Root(
#         dev         = args.dev,
#         defaultFile = args.defaultFile,
#         emuMode     = args.emuMode,
#         pollEn      = args.pollEn,
#         initRead    = args.initRead,
#         linkRate    = args.linkRate,
#         viewer      = args.viewer,
#         tcpPort     = args.tcpPort,
#     )

Pix2PgpEmuBoard.start()

pyrogue.pydm.runPyDM(
    root  = Pix2PgpEmuBoard,
    sizeX = 800,
    sizeY = 800,
)

#################################################################
