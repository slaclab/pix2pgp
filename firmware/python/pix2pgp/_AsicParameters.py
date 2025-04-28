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

class AsicParametersBase:
    '''
    Base class for ASIC Paramters
    every ASIC class should have:
    * a paramExtract() method, same as this base class
    '''
    def paramExtract(self):
        raise NotImplementedError("This method should be overridden by subclasses")

class SparkPixSParameters(AsicParametersBase):
    '''
    SparkPix-S Parameters
    '''
    def paramExtract(self):
        '''
        Parameter dictionary
        '''

        param_dict = {'asicId'     : 0,
                      'numOfLanes' : 8,
                      'numOfCols'  : 24,
                      'dataLen'    : 5}

        return param_dict

class SparkPixTParameters(AsicParametersBase):
    '''
    SparkPix-T Parameters
    '''
    def paramExtract(self):
        '''
        Parameter dictionary
        '''

        param_dict = {'asicId'     : 1,
                      'numOfLanes' : 8,
                      'numOfCols'  : 24,
                      'dataLen'    : 8}

        return param_dict
