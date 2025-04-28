# -------------------------------------------------------------------------------
# -- This file is part of 'Pix2Pgp'.
# -- It is subject to the license terms in the LICENSE.txt file found in the
# -- top-level directory of this distribution and at:
# --    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# -- No part of 'Pix2Pgp', including this file,
# -- may be copied, modified, propagated, or distributed except according to
# -- the terms contained in the LICENSE.txt file.
# -------------------------------------------------------------------------------

class SparseColMetadataFormatBase:
    '''
    Base class for sparse data
    every ASIC class should have:
    * a colMetadataDecoder() method, same as this base class
    '''
    def colMetadataDecoder(self, header):
        raise NotImplementedError("This method should be overridden by subclasses")

class SparkPixSColMetaDataFormat(SparseColMetadataFormatBase):
    '''
    SparkPix-S colMetaData Format
    '''
    def colMetadataDecoder(self, colMeta):
        '''
        Column Metadata mapping and decoding
        '''
        _colMeta = int(colMeta, 16)

        colMeta_dict = {'colOverOcc' : bool((_colMeta >> 25) & 0x1),
                        'colPause'   : bool((_colMeta >> 24) & 0x1),
                        'colId'      :      (_colMeta >> 16) & 0xFF,
                        'colTrgCnt'  :      (_colMeta >>  8) & 0xFF,
                        'colLen'     :      (_colMeta >>  0) & 0xFF}

        return colMeta_dict

class SparkPixTColMetaDataFormat(SparseColMetadataFormatBase):
    '''
    SparkPix-T colMetaData Format
    '''
    def colMetadataDecoder(self, colMeta):
        '''
        Column Metadata mapping and decoding
        '''
        _colMeta = int(colMeta, 16)

        colMeta_dict = {'colOverOcc' : bool((_colMeta >> 25) & 0x1),
                        'colPause'   : bool((_colMeta >> 24) & 0x1),
                        'colId'      :      (_colMeta >> 16) & 0xFF,
                        'colTrgCnt'  :      (_colMeta >>  8) & 0xFF,
                        'colLen'     :      (_colMeta >>  0) & 0xFF}

        return colMeta_dict
