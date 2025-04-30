# -------------------------------------------------------------------------------
# -- This file is part of 'Pix2Pgp'.
# -- It is subject to the license terms in the LICENSE.txt file found in the
# -- top-level directory of this distribution and at:
# --    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# -- No part of 'Pix2Pgp', including this file,
# -- may be copied, modified, propagated, or distributed except according to
# -- the terms contained in the LICENSE.txt file.
# -------------------------------------------------------------------------------

class Pix2PgpFpgaRxDataFormatBase:
    '''
    Base class for Pix2Pgp FPGA Receiver logic
    every FPGA class should have:
    * a fpgaPreambleDecoder() method, same as this base class
    * a fpgaHeaderDecoder() method, same as this base class
    * a fpgaTrailerDecoder() method, same as this base class
    '''
    def fpgaParamExtract(self):
        raise NotImplementedError("This method should be overridden by subclasses")
    def fpgaPreambleDecoder(self, preamble):
        raise NotImplementedError("This method should be overridden by subclasses")
    def fpgaHeaderDecoder(self, header):
        raise NotImplementedError("This method should be overridden by subclasses")
    def fpgaTrailerDecoder(self, trailer):
        raise NotImplementedError("This method should be overridden by subclasses")

class FpgaRxDataFormat(Pix2PgpFpgaRxDataFormatBase):
    '''
    FPGA Receiver
    '''
    def fpgaParamExtract(self):
        '''
        Parameter dictionary
        '''
        param_dict = {'preambleLen' : 20,
                      'headerLen'   : 3,
                      'trailerLen'  : 8}

        return param_dict

    def fpgaPreambleDecoder(self, preamble):
        '''
        FPGA Preamble Decoder
        '''
        _preamble = int(preamble, 16)

        preamble_dict = {'pix2pgpId'  : (_preamble >> 96) & 0xFFFFFFFFFFFFFFFF,
                         'asicType'   : (_preamble >> 64) & 0xFFFFFFFF,
                         'asicId'     : (_preamble >> 32) & 0xFFFFFFFF,
                         'fpgaId'     : (_preamble >> 16) & 0xFFFF,
                         'fpgaTrgCnt' : (_preamble >>  0) & 0xFFFF}

        return preamble_dict

    def fpgaHeaderDecoder(self, header):
        '''
        FPGA Header Decoder
        '''
        _header = int(header, 16)

        header_dict = {'laneError'   : (_header >> 16) & 0xFF,
                       'laneTimeout' : (_header >>  8) & 0xFF,
                       'laneValid'   : (_header >>  0) & 0xFF}

        return header_dict

    def fpgaTrailerDecoder(self, trailer):
        '''
        FPGA Trailer Decoder
        '''
        _trailer = int(trailer, 16)

        trailer_dict = {'pix2pgpId' : (_trailer >>  0) & 0xFFFFFFFFFFFFFFFF}

        return trailer_dict

