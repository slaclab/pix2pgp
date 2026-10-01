.. _how_to_rogue_stream:

============================================
How to Use Pix2PgpSparseProcessor with Rogue
============================================

For real hardware runs, data are usually captured via
`ROGUE <https://slaclab.github.io/rogue/>`_. The Pix2PGP Python suite
provides a rogue stream processor class,
``pix2pgp.Pix2PgpSparseProcessor``, that consumes a live rogue AXI-Stream
and yields decoded data through the same containers as the offline parser.

Prerequisites
=============

* Rogue environment set up (see :ref:`setup_rogue_setup`)
* Pix2PGP Python package on ``PYTHONPATH`` (add
  ``firmware/python/`` — or install the package into the rogue environment)

Example
=======

The following example replays a captured stream dump through
``Pix2PgpSparseProcessor`` and pickles the resulting event containers to
disk for offline analysis:

.. code-block:: python

   import os
   import sys
   import rogue
   rogue.Version.minVersion('6.1.0')
   import pyrogue as pr
   import pyrogue.utilities.fileio
   import pickle
   import pix2pgp

   dataFilePath = 'data.dat'

   dataReader = rogue.utilities.fileio.StreamReader()

   dataProcessor = pix2pgp.Pix2PgpSparseProcessor(
       rawData  = False,
       maxAsics = 4,
       verbose  = 1,
       asicType = 'SparkPixS'
   )

   dataProcessor << dataReader

   dataReader.open(dataFilePath)
   dataReader.closeWait()

   dataDict = {
       'asicId'        : dataProcessor.asicId,
       'asicLaneValid' : dataProcessor.asicLaneValid,
       'asicHits'      : dataProcessor.asicHits,
       'asicTrgCnt'    : dataProcessor.asicTrgCnt,
   }

   with open('pickleData.pkl', 'wb') as f:
       pickle.dump(dataDict, f)

Constructor Arguments
=====================

* ``rawData``  — pass through un-decoded hit words (``True``) or fully
  unpack into ``{col, row, adc, ...}`` dicts (``False``)
* ``maxAsics`` — maximum number of ASICs to buffer in parallel (relevant
  for multi-ASIC FPGA receivers)
* ``verbose`` — verbosity level (0 = silent, higher = more diagnostics)
* ``asicType`` — must match the ASIC that produced the stream

For online use, connect ``Pix2PgpSparseProcessor`` directly to a rogue
stream tap (e.g. a PGP RX channel), rather than to a ``StreamReader``.
