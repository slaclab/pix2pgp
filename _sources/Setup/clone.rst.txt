.. _setup_clone:

===================================
How to Clone the pix2pgp Repository
===================================

Pix2PGP relies on git submodules for its external dependencies (SURF and
Ruckus). Clone the repository with ``--recurse-submodules``:

.. code-block:: bash

   $ git clone --recurse-submodules https://github.com/slaclab/pix2pgp.git

If the submodules were not fetched at clone time, they can be initialized
afterwards:

.. code-block:: bash

   $ cd pix2pgp
   $ git submodule update --init --recursive
