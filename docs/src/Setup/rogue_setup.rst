.. _setup_rogue_setup:

====================
Rogue Software Setup
====================

The ``Pix2PgpSparseProcessor`` rogue-based wrapper (used to process a live
rogue data stream through the Pix2PGP Python decoder) requires the
`ROGUE <https://slaclab.github.io/rogue/>`_ environment.

If you are on the SLAC SDF network
==================================

Source the packaged setup script:

.. code-block:: bash

   $ cd pix2pgp/software
   $ source setup_env_slac.sh

This activates a preconfigured conda environment (``rogue_v5.18.4`` as of
this writing) that provides rogue, pyrogue, and the associated Python
dependencies.

If you are NOT on the SLAC SDF network
======================================

Follow the "Install Rogue with Miniforge" guide:

   https://slaclab.github.io/rogue/installing/miniforge.html

After the Miniforge install, activate the rogue conda environment:

.. code-block:: bash

   # Setup conda
   $ source /path/to/my/miniforge3/etc/profile.d/conda.sh

   # Activate the rogue environment (adjust name to your local install)
   $ conda activate rogue_v6.15.0

Non-Rogue Usage
===============

If the user only intends to use the Pix2PGP Python decoder in a standalone
fashion (i.e. without rogue), the ``Pix2PgpSparseProcessor`` class is
optional. The core decoding classes (``AsicData``, ``LaneData``,
``AsicParameters``, header/metadata/data format classes) do not depend on
pyrogue and can be imported directly:

.. code-block:: python

   import pix2pgp
