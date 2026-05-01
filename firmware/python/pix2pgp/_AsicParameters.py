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
        1: "SparkPixS",
        2: "SparkPixT",
        3: "Thriglav",
        4: "SparkPixSv2"}

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
    _asicTypeId = None
    _params = None

    @property
    def asicTypeId(self):
        if SparkPixSParameters._asicTypeId is None:
            for key, value in AsicParameterBase.asicTypeDict.items():
                if value == "SparkPixS":
                    SparkPixSParameters._asicTypeId = key
                    break
            else:
                raise ValueError("ASIC type not found in asicTypeDict!")
        return SparkPixSParameters._asicTypeId

    def asicParamExtract(self):
        if SparkPixSParameters._params is None:
            SparkPixSParameters._params = {
                'asicTypeId' : self.asicTypeId,
                'asicType'   : AsicParameterBase.asicTypeDict[self.asicTypeId],
                'numOfLanes' : 8,
                'numOfCols'  : 24,
                'wordLen'    : 5}
        return SparkPixSParameters._params

class SparkPixSv2Parameters(AsicParameterBase):
    '''
    SparkPix-Sv2 Parameters
    '''
    _asicTypeId = None
    _params = None

    @property
    def asicTypeId(self):
        if SparkPixSv2Parameters._asicTypeId is None:
            for key, value in AsicParameterBase.asicTypeDict.items():
                if value == "SparkPixSv2":
                    SparkPixSv2Parameters._asicTypeId = key
                    break
            else:
                raise ValueError("ASIC type not found in asicTypeDict!")
        return SparkPixSv2Parameters._asicTypeId

    def asicParamExtract(self):
        if SparkPixSv2Parameters._params is None:
            SparkPixSv2Parameters._params = {
                'asicTypeId' : self.asicTypeId,
                'asicType'   : AsicParameterBase.asicTypeDict[self.asicTypeId],
                'numOfLanes' : 8,
                'numOfCols'  : 24,
                'wordLen'    : 5}
        return SparkPixSv2Parameters._params


class SparkPixTParameters(AsicParameterBase):
    '''
    SparkPix-T Parameters
    '''
    _asicTypeId = None
    _params = None

    @property
    def asicTypeId(self):
        if SparkPixTParameters._asicTypeId is None:
            for key, value in AsicParameterBase.asicTypeDict.items():
                if value == "SparkPixT":
                    SparkPixTParameters._asicTypeId = key
                    break
            else:
                raise ValueError("ASIC type not found in asicTypeDict!")
        return SparkPixTParameters._asicTypeId

    def asicParamExtract(self):
        if SparkPixTParameters._params is None:
            SparkPixTParameters._params = {
                'asicTypeId' : self.asicTypeId,
                'asicType'   : AsicParameterBase.asicTypeDict[self.asicTypeId],
                'numOfLanes' : 8,
                'numOfCols'  : 24,
                'wordLen'    : 8}
        return SparkPixTParameters._params


class ThriglavParameters(AsicParameterBase):
    '''
    Thriglav Parameters
    '''
    _asicTypeId = None
    _params = None

    @property
    def asicTypeId(self):
        if ThriglavParameters._asicTypeId is None:
            for key, value in AsicParameterBase.asicTypeDict.items():
                if value == "Thriglav":
                    ThriglavParameters._asicTypeId = key
                    break
            else:
                raise ValueError("ASIC type not found in asicTypeDict!")
        return ThriglavParameters._asicTypeId

    def asicParamExtract(self):
        if ThriglavParameters._params is None:
            ThriglavParameters._params = {
                'asicTypeId' : self.asicTypeId,
                'asicType'   : AsicParameterBase.asicTypeDict[self.asicTypeId],
                'numOfLanes' : 2,
                'numOfCols'  : 50,
                'wordLen'    : 8}
        return ThriglavParameters._params

AsicParameterBase.setParams()
