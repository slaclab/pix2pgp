# -------------------------------------------------------------------------------
# -- This file is part of 'Pix2Pgp'.
# -- It is subject to the license terms in the LICENSE.txt file found in the
# -- top-level directory of this distribution and at:
# --    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# -- No part of 'Pix2Pgp', including this file,
# -- may be copied, modified, propagated, or distributed except according to
# -- the terms contained in the LICENSE.txt file.
# -------------------------------------------------------------------------------

class Pix2PgpHeaderFormatBase:
    '''
    Base class for sparse data
    every ASIC class should have:
    * a headerDecoder() method, same as this base class
    '''

    @classmethod
    def setHeader(self):
        self.asicHeader = {
            'SparkPixS'  : SparkPixSHeaderFormat,
            'SparkPixSv2': SparkPixSv2HeaderFormat,
            'SparkPixT'  : SparkPixTHeaderFormat,
            'Thriglav'   : ThriglavHeaderFormat}

    def headerDecoder(self, header):
        raise NotImplementedError("This method should be overridden by subclasses")

class SparkPixSHeaderFormat(Pix2PgpHeaderFormatBase):
    '''
    SparkPix-S Header Format
    '''
    def headerDecoder(self, header):
        '''
        Header mapping and decoding
        '''
        _header = int(header, 16)

        header_dict = {'overOcc'    : bool((_header >> 39) & 0x1),
                       'pause'      : bool((_header >> 38) & 0x1),
                       'colErr'     : bool((_header >> 37) & 0x1),
                       'pauseErr'   : bool((_header >> 36) & 0x1),
                       'dummy'      : bool((_header >> 35) & 0x1),
                       'timeout'    : bool((_header >> 34) & 0x1),
                       'colHitmask' :      (_header >>  8) & 0xFFFFFF,
                       'trgCnt'     :      (_header >>  0) & 0xFF}

        return header_dict

class SparkPixSv2HeaderFormat(Pix2PgpHeaderFormatBase):
    '''
    SparkPix-Sv2 Header Format
    '''
    def headerDecoder(self, header):
        '''
        Header mapping and decoding
        '''
        _header = int(header, 16)

        header_dict = {'overOcc'    : bool((_header >> 39) & 0x1),
                       'pause'      : bool((_header >> 38) & 0x1),
                       'colErr'     : bool((_header >> 37) & 0x1),
                       'pauseErr'   : bool((_header >> 36) & 0x1),
                       'dummy'      : bool((_header >> 35) & 0x1),
                       'timeout'    : bool((_header >> 34) & 0x1),
                       'colHitmask' :      (_header >>  8) & 0xFFFFFF,
                       'trgCnt'     :      (_header >>  0) & 0xFF}

        return header_dict

class SparkPixTHeaderFormat(Pix2PgpHeaderFormatBase):
    '''
    SparkPix-T Header Format
    '''
    def headerDecoder(self, header):
        '''
        Header mapping and decoding
        '''
        _header = int(header, 16)

        header_dict = {'overOcc'    : bool((_header >> 63) & 0x1),
                       'pause'      : bool((_header >> 62) & 0x1),
                       'colErr'     : bool((_header >> 61) & 0x1),
                       'pauseErr'   : bool((_header >> 60) & 0x1),
                       'dummy'      : bool((_header >> 59) & 0x1),
                       'timeout'    : bool((_header >> 58) & 0x1),
                       'colHitmask' :      (_header >>  8) & 0xFFFFFF,
                       'trgCnt'     :      (_header >>  0) & 0xFF}

        return header_dict

class ThriglavHeaderFormat(Pix2PgpHeaderFormatBase):
    '''
    Thriglav Header Format
    '''
    def headerDecoder(self, header):
        '''
        Header mapping and decoding
        '''
        _header = int(header, 16)

        header_dict = {'overOcc'    : bool((_header >> 63) & 0x1),
                       'pause'      : bool((_header >> 62) & 0x1),
                       'colErr'     : bool((_header >> 61) & 0x1),
                       'pauseErr'   : bool((_header >> 60) & 0x1),
                       'dummy'      : bool((_header >> 59) & 0x1),
                       'timeout'    : bool((_header >> 58) & 0x1),
                       'colHitmask' :      (_header >>  7) & 0x3FFFFFFFFFFFF,
                       'trgCnt'     :      (_header >>  0) & 0x7F}

        return header_dict

Pix2PgpHeaderFormatBase.setHeader()