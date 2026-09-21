#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# pix2pgp documentation build configuration file.
#

import subprocess
import breathe

# -- General configuration ------------------------------------------------

extensions = [
    'sphinx.ext.autodoc',
    'sphinx.ext.doctest',
    'sphinx.ext.intersphinx',
    'sphinx.ext.todo',
    'sphinx.ext.coverage',
    'sphinx.ext.mathjax',
    'sphinx.ext.ifconfig',
    'sphinx.ext.viewcode',
    'sphinx.ext.githubpages',
    'sphinx.ext.napoleon',
    'breathe',
]

templates_path = ['_templates']
source_suffix = '.rst'
master_doc = 'index'

project = 'pix2pgp'
copyright = '2026, SLAC National Accelerator Laboratory'
author = 'SLAC TID-ID-ES'

try:
    release = subprocess.check_output(["git", "describe", "--always"]).strip().decode()
except Exception:
    release = 'unknown'

language = None

exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store']

pygments_style = 'sphinx'

todo_include_todos = True


# -- Options for HTML output ----------------------------------------------

html_theme = 'sphinx_rtd_theme'
html_static_path = ['_static']


# -- Options for HTMLHelp output ------------------------------------------

htmlhelp_basename = 'pix2pgpdoc'


# -- Options for LaTeX output ---------------------------------------------

latex_elements = {}

latex_documents = [
    (master_doc, 'pix2pgp.tex', 'pix2pgp Documentation',
     'TID-ID-ES', 'manual'),
]


# -- Options for manual page output ---------------------------------------

man_pages = [
    (master_doc, 'pix2pgp', 'pix2pgp Documentation',
     [author], 1)
]


# -- Options for Texinfo output -------------------------------------------

texinfo_documents = [
    (master_doc, 'pix2pgp', 'pix2pgp Documentation',
     author, 'pix2pgp', 'A sparse readout DAQ framework for detector ASICs.',
     'Miscellaneous'),
]

intersphinx_mapping = {'python': ('https://docs.python.org/', None)}

# Breathe configuration
breathe_projects = {'pix2pgp': '../build/doxyxml'}
breathe_default_project = 'pix2pgp'
