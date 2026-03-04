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
    @classmethod
    def setData(self):
        self.asicData = {
            'SparkPixS'  : SparkPixSDataFormat,
            'SparkPixSv2': SparkPixSDataFormat,
            'SparkPixT'  : SparkPixTDataFormat,
            'Thriglav'   : ThriglavDataFormat}

    def dataDecoder(self, colId=0, hitData=None, rawData=False):
        raise NotImplementedError("This method should be overridden by subclasses")
    def dataPrinter(self, asicHits=None, rawData=False):
        raise NotImplementedError("This method should be overridden by subclasses")

class SparkPixSDataFormat(SparseDataFormatBase):
    '''
    SparkPix-S Data Format
    '''
    def dataDecoder(self, colId=0, hitData=None, rawData=False):
        '''
        Hit data mapping and decoding
        '''
        if hitData is None:
            click.secho("[WARNING]: dataDecoder; Received None for hitData", bg='yellow')
            return

        _hitData = int(hitData, 16)

        _hit = []
        ret  = []

        _hit.append((_hitData >> 20) & 0xFFFFF)
        _hit.append((_hitData >>  0) & 0xFFFFF)

        if rawData:
            ret.append({'col': colId, 'raw': hex(_hit[0]).upper().replace('0X', '0x')})
            ret.append({'col': colId, 'raw': hex(_hit[1]).upper().replace('0X', '0x')})

        else:
            _row = []
            _LR  = []
            _adc = []

            _row.append((_hit[0] >> 10) & 0x1FF)
            _LR.append ((_hit[0] >> 19) & 0x1)
            _adc.append((_hit[0] >>  0) & 0x3FF)

            _row.append((_hit[1] >> 10) & 0x1FF)
            _LR.append ((_hit[1] >> 19) & 0x1)
            _adc.append((_hit[1] >>  0) & 0x3FF)

            ret.append({'col': (2*colId + _LR[0]),
                        'row': _row[0],
                        'adc': _adc[0]})

            ret.append({'col': (2*colId + _LR[1]),
                        'row': _row[1],
                        'adc': _adc[1]})

        return ret

    def dataPrinter(self, asicHits=None, rawData=False):

        if asicHits is None or len(asicHits) == 0:
            click.secho("[INFO]: dataDecoder; Empty event...")
            return

        if rawData:
            _formatRaw = 'Col = {0:<4}  Raw = {1:<24}'

            for hit in asicHits:
                click.secho(_formatRaw.format(hit['col'], str(hit['raw'])))

        else:
            _formatAsic = 'Col = {0:<4} Row = {1:<4} ADC = {2:<8}'

            for hit in asicHits:
                click.secho(_formatAsic.format(hit['col'], hit['row'], hit['adc']))

class SparkPixTDataFormat(SparseDataFormatBase):
    '''
    SparkPix-T Data Format
    '''
    def dataDecoder(self, colId=0, hitData=None, rawData=False):
        '''
        Hit data mapping and decoding
        '''
        if hitData is None:
            click.secho("[WARNING]: dataDecoder; Received None for hitData", bg='yellow')
            return

        _hitData = int(hitData, 16)

        _hit = []
        ret  = []

        _hit.append((_hitData >> 32) & 0xFFFFFFFF)
        _hit.append((_hitData >>  0) & 0xFFFFFFFF)

        if rawData:
            ret.append({'col': colId, 'raw': hex(_hit[0]).upper().replace('0X', '0x')})
            ret.append({'col': colId, 'raw': hex(_hit[1]).upper().replace('0X', '0x')})

        else:
            _row  = []
            _toaF = []
            _toaC = []
            _toa  = []
            _tot  = []

            _row.append ((_hit[0] >> 24) & 0xFF)
            _toaF.append((_hit[0] >>  0) & 0xFF)
            _toaC.append((_hit[0] >>  8) & 0xFF)
            _tot.append( (_hit[0] >> 16) & 0xFF)

            _row.append ((_hit[1] >> 24) & 0xFF)
            _toaF.append((_hit[1] >>  0) & 0xFF)
            _toaC.append((_hit[1] >>  8) & 0xFF)
            _tot.append( (_hit[1] >> 16) & 0xFF)

            _toa.append((_toaC[0] << 8) | _toaF[0])
            _toa.append((_toaC[1] << 8) | _toaF[1])

            ret.append({'col' : colId,
                        'row' : _row[0],
                        'toaC': _toaC[0],
                        'toaF': _toaF[0],
                        'toa' : _toa[0],
                        'tot' : _tot[0]})

            ret.append({'col' : colId,
                        'row' : _row[1],
                        'toaC': _toaC[1],
                        'toaF': _toaF[1],
                        'toa' : _toa[1],
                        'tot' : _tot[1]})

        return ret

    def dataPrinter(self, asicHits=None, rawData=False):

        if asicHits is None or len(asicHits) == 0:
            click.secho("[INFO]: dataDecoder; Empty event...")
            return

        if rawData:
            _formatRaw = 'Col = {0:<4}  Raw = {1:<24}'

            for hit in asicHits:
                click.secho(_formatRaw.format(hit['col'], str(hit['raw'])))

        else:
            _formatAsic = 'Col = {0:<4} Row = {1:<4} ToA = {2:<8} ToAc = {3:<6} ToAf = {4:<6} ToT = {5:<8}'

            for hit in asicHits:
                click.secho(_formatAsic.format(hit['col'], hit['row'], hit['toa'], hit['toaC'], hit['toaF'], hit['tot']))

class ThriglavDataFormat(SparseDataFormatBase):
    '''
    Thriglav Data Format
    '''
    def dataDecoder(self, colId=0, hitData=None, rawData=False):
        '''
        Hit data mapping and decoding
        '''
        if hitData is None:
            click.secho("[WARNING]: dataDecoder; Received None for hitData", bg='yellow')
            return

        _hitData = int(hitData, 16)

        _hit = []
        ret  = []

        _hit.append((_hitData >> 32) & 0xFFFFFFFF)
        _hit.append((_hitData >>  0) & 0xFFFFFFFF)

        if rawData:
            ret.append({'col': colId, 'raw': hex(_hit[0]).upper().replace('0X', '0x')})
            ret.append({'col': colId, 'raw': hex(_hit[1]).upper().replace('0X', '0x')})

        else:
            _toac     = []
            _toaf     = []
            _overflow = []
            _reserved = []
            _tot      = []
            _row      = []

            _tot.append      ((_hit[0] >>  0) & 0xFF)
            _row.append      ((_hit[0] >>  8) & 0xFF)
            _toac.append     ((_hit[0] >> 16) & 0xFF)
            _toaf.append     ((_hit[0] >> 24) & 0x7)
            _overflow.append ((_hit[0] >> 27) & 0x1)
            _reserved.append ((_hit[0] >> 28) & 0xF)

            _tot.append      ((_hit[1] >>  0) & 0xFF)
            _row.append      ((_hit[1] >>  8) & 0xFF)
            _toac.append     ((_hit[1] >> 16) & 0xFF)
            _toaf.append     ((_hit[1] >> 24) & 0x7)
            _overflow.append ((_hit[1] >> 27) & 0x1)
            _reserved.append ((_hit[1] >> 28) & 0xF)

            ret.append({'col'      : colId,
                        'row'      : _row[0],
                        'toac'     : _toac[0],
                        'toaf'     : _toaf[0],
                        'toa'      : _toac[0] << 3 | (7-_toaf[0]),
                        'tot'      : _tot[0],
                        'overflow' : _overflow[0],
                        'reserved' : _reserved[0]})

            ret.append({'col'      : colId,
                        'row'      : _row[1],
                        'toac'     : _toac[1],
                        'toaf'     : _toaf[1],
                        'toa'      : _toac[1] << 3 | (7-_toaf[1]),
                        'tot'      : _tot[1],
                        'overflow' : _overflow[1],
                        'reserved' : _reserved[1]})

        return ret

    def dataPrinter(self, asicHits=None, rawData=False):

        if asicHits is None or len(asicHits) == 0:
            click.secho("[INFO]: dataDecoder; Empty event...")
            return

        if rawData:
            _formatRaw = 'Col = {0:<4}  Raw = {1:<24}'

            for hit in asicHits:
                click.secho(_formatRaw.format(hit['col'], str(hit['raw'])))

        else:
            _formatAsic = 'Col = {0:<4} Row = {1:<4} ToAc = {2:<4} ToAf = {3:<4} ToA = {4:<8} ToT = {5:<8} Overflow = {6:<1}'

            for hit in asicHits:
                click.secho(_formatAsic.format(
                    hit['col'],  hit['row'],  hit['toac'],
                    hit['toaf'], hit['toa'],  hit['tot'], hit['overflow'])
                )


SparseDataFormatBase.setData()
