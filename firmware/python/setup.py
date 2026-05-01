from setuptools import setup, Extension, find_packages

try:
    from Cython.Build import cythonize
    import numpy as np

    extensions = cythonize(
        [Extension(
            "pix2pgp._fast_parse",
            sources=["pix2pgp/_fast_parse.pyx"],
            include_dirs=[np.get_include()],
            extra_compile_args=["-O3"],
        )],
        language_level=3,
    )
except ImportError:
    extensions = []

setup(
    packages=find_packages(),
    ext_modules=extensions,
)
