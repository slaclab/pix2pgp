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
        param_dict = {'preambleLen'  : 20,
                      'headerLen'    : 5,
                      'frameSizeLen' : 2,
                      'trailerLen'   : 8}

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

    def fpgaHeaderDecoder(self, header, numOfLanes=8):
        '''
        FPGA Header Decoder (default is 8xlanes)
        '''
        _header = int(header, 16)

        _bitmask = (1 << numOfLanes) - 1

        header_dict = {'laneDecError'   : (_header >> numOfLanes*4) & _bitmask,
                       'lanePauseError' : (_header >> numOfLanes*3) & _bitmask,
                       'laneFull'       : (_header >> numOfLanes*2) & _bitmask,
                       'laneTimeout'    : (_header >> numOfLanes*1) & _bitmask,
                       'laneValid'      : (_header >>  0) & _bitmask}

        return header_dict

    def fpgaTrailerDecoder(self, trailer):
        '''
        FPGA Trailer Decoder
        '''
        _trailer = int(trailer, 16)

        trailer_dict = {'pix2pgpId' : (_trailer >>  0) & 0xFFFFFFFFFFFFFFFF}

        return trailer_dict

