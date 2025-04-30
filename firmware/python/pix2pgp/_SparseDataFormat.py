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

class SparseDataFormatBase:
    '''
    Base class for sparse data
    every ASIC class should have:
    * a dataDecoder() method, same as this base class
    '''
    def dataDecoder(self, hitData, hitLen=2, asicData=False, fpgaTbData=False):
        raise NotImplementedError("This method should be overridden by subclasses")

class SparkPixSDataFormat(SparseDataFormatBase):
    '''
    SparkPix-S Data Format
    '''
    def dataDecoder(self, hitData, hitLen=2, asicData=False, fpgaTbData=False):
        '''
        Hit data mapping and decoding
        '''
        _hitData = int(hitData, 16)
        hit0     = (_hitData >> 20) & 0xFFFFF
        hit1     = (_hitData >>  0) & 0xFFFFF

        if asicData:
            _hitData0_dict = {'row'    : (hit0 >>  0) & 0x3FF,
                              'addr'   : (hit0 >> 10) & 0xFFFFF}

            _hitData1_dict = {'row'    : (hit1 >>  0) & 0x3FF,
                              'addr'   : (hit1 >> 10) & 0xFFFFF}
        elif fpgaTbData:
            _hitData0_dict = {'hitCnt' : (hit0 >>  0) & 0x3FF,
                              'colId'  : (hit0 >> 10) & 0x3F,
                              'hitTrg' : (hit0 >> 16) & 0x0F}

            _hitData1_dict = {'hitCnt' : (hit1 >>  0) & 0x3FF,
                              'colId'  : (hit1 >> 10) & 0x3F,
                              'hitTrg' : (hit1 >> 16) & 0x0F}
        else:
            _hitData0_dict = {'raw'    : hit0}
            _hitData1_dict = {'raw'    : hit1}

        return _hitData0_dict, _hitData1_dict

class SparkPixTDataFormat(SparseDataFormatBase):
    '''
    SparkPix-T Data Format
    '''
    def dataDecoder(self, hitData, hitLen=2, asicData=False, fpgaTbData=False):
        '''
        Hit data mapping and decoding
        '''
        _hitData = int(hitData, 16)
        hit0 = (_hitData >> 32) & 0xFFFFFFFF
        hit1 = (_hitData >>  0) & 0xFFFFFFFF

        if asicData:
            _hitData0_dict = {'toaF'   : (hit0 >>  0) & 0x7F,
                              'toaC'   : (hit0 >>  8) & 0xFF,
                              'tot'    : (hit0 >> 16) & 0xFF,
                              'row'    : (hit0 >> 24) & 0xFF}

            _hitData1_dict = {'toaF'   : (hit1 >>  0) & 0x7F,
                              'toaC'   : (hit1 >>  8) & 0xFF,
                              'tot'    : (hit1 >> 16) & 0xFF,
                              'row'    : (hit1 >> 24) & 0xFF}
        elif fpgaTbData:
            _hitData0_dict = {'hitCnt' : (hit0 >>  0) & 0x1FF,
                              'colId'  : (hit0 >> 10) & 0x3F,
                              'hitTrg' : (hit0 >> 16) & 0x3FF}

            _hitData1_dict = {'hitCnt' : (hit1 >>  0) & 0x1FF,
                              'colId'  : (hit1 >> 10) & 0x3F,
                              'hitTrg' : (hit1 >> 16) & 0x3FF}
        else:
            _hitData0_dict = {'raw'    : hit0}
            _hitData1_dict = {'raw'    : hit1}

        return _hitData0_dict, _hitData1_dict