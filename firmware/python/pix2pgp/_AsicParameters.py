# -------------------------------------------------------------------------------
# -- This file is part of 'Pix2Pgp'.
# -- It is subject to the license terms in the LICENSE.txt file found in the
# -- top-level directory of this distribution and at:
# --    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# -- No part of 'Pix2Pgp', including this file,
# -- may be copied, modified, propagated, or distributed except according to
# -- the terms contained in the LICENSE.txt file.
# -------------------------------------------------------------------------------

class AsicParameterBase:
    '''
    Base class for ASIC Paramters
    every ASIC class should have:
    * a asicParamExtract() method, same as this base class
    '''
    asicTypeDict = {
        0: "SparkPixS",
        1: "SparkPixT",
        2: "Thriglav",
        3: "SparkPixSv2"}

    @classmethod
    def setParams(self):
        self.asicParams = {
            'SparkPixS'   : SparkPixSParameters,
            'SparkPixSv2' : SparkPixSv2Parameters,
            'SparkPixT'   : SparkPixTParameters,
            'Thriglav'    : ThriglavParameters}

    def asicParamExtract(self):
        raise NotImplementedError("This method should be overridden by subclasses")

class SparkPixSParameters(AsicParameterBase):
    '''
    SparkPix-S Parameters
    '''
    @property
    def asicTypeId(self):
        for key, value in AsicParameterBase.asicTypeDict.items():
            if value == "SparkPixS":
                return key
        raise ValueError("ASIC type not found in asicTypeDict!")

    def asicParamExtract(self):
        '''
        Parameter dictionary
        '''

        param_dict = {'asicTypeId' : self.asicTypeId,
                      'asicType'   : AsicParameterBase.asicTypeDict[self.asicTypeId],
                      'numOfLanes' : 8,
                      'numOfCols'  : 24,
                      'wordLen'    : 5,
                      'headerLen'  : 5}

        return param_dict

class SparkPixSv2Parameters(AsicParameterBase):
    '''
    SparkPix-Sv2 Parameters
    '''
    @property
    def asicTypeId(self):
        for key, value in AsicParameterBase.asicTypeDict.items():
            if value == "SparkPixSv2":
                return key
        raise ValueError("ASIC type not found in asicTypeDict!")

    def asicParamExtract(self):
        '''
        Parameter dictionary
        '''

        param_dict = {'asicTypeId' : self.asicTypeId,
                      'asicType'   : AsicParameterBase.asicTypeDict[self.asicTypeId],
                      'numOfLanes' : 8,
                      'numOfCols'  : 24,
                      'wordLen'    : 5,
                      'headerLen'  : 5}

        return param_dict


class SparkPixTParameters(AsicParameterBase):
    '''
    SparkPix-T Parameters
    '''
    @property
    def asicTypeId(self):
        for key, value in AsicParameterBase.asicTypeDict.items():
            if value == "SparkPixT":
                return key
        raise ValueError("ASIC type not found in asicTypeDict!")

    def asicParamExtract(self):
        '''
        Parameter dictionary
        '''

        param_dict = {'asicTypeId' : self.asicTypeId,
                      'asicType'   : AsicParameterBase.asicTypeDict[self.asicTypeId],
                      'numOfLanes' : 8,
                      'numOfCols'  : 24,
                      'wordLen'    : 8,
                      'headerLen'  : 8}

        return param_dict


class ThriglavParameters(AsicParameterBase):
    '''
    Thriglav Parameters
    '''
    @property
    def asicTypeId(self):
        for key, value in AsicParameterBase.asicTypeDict.items():
            if value == "Thriglav":
                return key
        raise ValueError("ASIC type not found in asicTypeDict!")

    def asicParamExtract(self):
        '''
        Parameter dictionary
        '''

        param_dict = {'asicTypeId' : self.asicTypeId,
                      'asicType'   : AsicParameterBase.asicTypeDict[self.asicTypeId],
                      'numOfLanes' : 2,
                      'numOfCols'  : 50,
                      'wordLen'    : 8,
                      'headerLen'  : 8}

        return param_dict

AsicParameterBase.setParams()
