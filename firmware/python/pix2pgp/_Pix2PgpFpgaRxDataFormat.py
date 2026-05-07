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
    * a fpgaParamExtract() method used to set the parameters
    * a fpgaPreambleDecoder() method, same as this base class
    * a fpgaHeaderDecoder() method, same as this base class
    * a fpgaTrailerDecoder() method, same as this base class
    '''
    def asicLaneSet(self):
        raise NotImplementedError("This method should be overridden by subclasses")
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
    numOfLanes = 8 # default

    def asicNumOfLanesSet(self, numOfLanes):
        self.numOfLanes = numOfLanes

    def fpgaParamExtract(self):
        '''
        Parameter dictionary;
        note that headerLen is equal to the number of lanes;
        this is because the header has 8 types of bitmasks/status bits;
        and each of these types has a length equal to number of lanes
        '''
        param_dict = {'preambleLen'  : 16,
                      'headerLen'    : self.numOfLanes,
                      'frameSizeLen' : 2,
                      'trailerLen'   : 6}

        return param_dict

    def fpgaPreambleDecoder(self, preamble):
        '''
        FPGA Preamble Decoder
        '''
        _preamble = preamble if isinstance(preamble, int) else int(preamble, 16)

        preamble_dict = {'pix2pgpId'   : (_preamble >> 80) & 0xFFFFFFFFFFFF,
                         'pix2pgpType' : (_preamble >> 64) & 0xFFFF,
                         'asicType'    : (_preamble >> 48) & 0xFFFF,
                         'asicId'      : (_preamble >> 32) & 0xFFFF,
                         'fpgaId'      : (_preamble >> 16) & 0xFFFF,
                         'fpgaTrgCnt'  : (_preamble >>  0) & 0xFFFF}

        return preamble_dict

    def fpgaHeaderDecoder(self, header):
        '''
        FPGA Header Decoder (default is 8xlanes)
        '''
        _header = header if isinstance(header, int) else int(header, 16)

        _bitmask = (1 << self.numOfLanes) - 1

        header_dict = {'laneDecError'   : (_header >> self.numOfLanes*7) & _bitmask,
                       'laneOverOcc'    : (_header >> self.numOfLanes*6) & _bitmask,
                       'lanePause'      : (_header >> self.numOfLanes*5) & _bitmask,
                       'lanePauseError' : (_header >> self.numOfLanes*4) & _bitmask,
                       'laneFull'       : (_header >> self.numOfLanes*3) & _bitmask,
                       'laneTimeout'    : (_header >> self.numOfLanes*2) & _bitmask,
                       'laneDown'       : (_header >> self.numOfLanes*1) & _bitmask,
                       'laneValid'      : (_header >>                 0) & _bitmask}

        return header_dict

    def fpgaTrailerDecoder(self, trailer):
        '''
        FPGA Trailer Decoder
        '''
        _trailer = trailer if isinstance(trailer, int) else int(trailer, 16)

        trailer_dict = {'pix2pgpId' : (_trailer >>  0) & 0xFFFFFFFFFFFF}

        return trailer_dict

