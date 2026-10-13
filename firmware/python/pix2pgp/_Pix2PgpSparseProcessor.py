# -------------------------------------------------------------------------------
# -- This file is part of 'Pix2Pgp'.
# -- It is subject to the license terms in the LICENSE.txt file found in the
# -- top-level directory of this distribution and at:
# --    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# -- No part of 'Pix2Pgp', including this file,
# -- may be copied, modified, propagated, or distributed except according to
# -- the terms contained in the LICENSE.txt file.
# -------------------------------------------------------------------------------
import pyrogue as pr

import pix2pgp

import rogue
rogue.Version.minVersion('6.15.0')


class Pix2PgpSparseProcessor(pr.DataReceiver):

    '''
    Class for Offline processing of Pix2PGP data
    '''

    def __init__(self,
                 verbose=1,
                 maxAsics=4,
                 asicType='SparkPixS',
                 rawData=False,
                 printStats=False,
                 enableOnStart=True,
                 hideData=True,
                 hidden=True,
                 errFields = ('laneDecError', 'lanePauseError', 'laneFull', 'laneTimeout', 'laneDown'),
                 **kwargs):

        pr.DataReceiver.__init__(self,
                                 enableOnStart=enableOnStart,
                                 hideData=hideData,
                                 hidden=hidden,
                                 **kwargs)

        self._rawData    = rawData
        self._verbose    = verbose
        self._maxAsics   = maxAsics
        self._asicType   = asicType
        self._printStats = printStats
        self._errFields  = errFields

        self.asicDecoder = pix2pgp.AsicData(asicType=self._asicType,
                                            rawData=self._rawData,
                                            verbose=self._verbose)

        # frame counters
        self.pix2pgpFrameCnt     = 0
        self.pix2pgpDropFrameCnt = 0
        self.nonPix2pgpFrameCnt  = 0
        self.rejectedFrameCnt    = 0

        n = self._maxAsics

        # per-ASIC containers; one entry per accepted Pix2Pgp frame, index-aligned
        self.asicId         = []
        self.asicEventValid = [[] for _ in range(n)]  # True if hits were kept

        # FPGA lane status
        self.asicLaneValid      = [[] for _ in range(n)]
        self.asicLaneDecError   = [[] for _ in range(n)]
        self.asicLanePauseError = [[] for _ in range(n)]
        self.asicLaneFull       = [[] for _ in range(n)]
        self.asicLaneTimeout    = [[] for _ in range(n)]
        self.asicLaneDown       = [[] for _ in range(n)]

        # ASIC lane-header flags
        self.asicGlblOverOcc  = [[] for _ in range(n)]
        self.asicGlblPause    = [[] for _ in range(n)]
        self.asicGlblPauseErr = [[] for _ in range(n)]
        self.asicTrgCnt       = [[] for _ in range(n)]

        # hits (empty list for rejected frames, see asicEventValid)
        self.asicHits = [[] for _ in range(n)]

    #################################################################
    def _frameHasError(self):
        d = self.asicDecoder
        return any(any(getattr(d, f)) for f in self._errFields)
    #################################################################

    #################################################################
    def _acceptFrame(self, frame):
        '''
        Method which is called when a frame is received
        First it is good practice to hold a lock on the frame data.
        Also serialize our own processing across concurrent stream threads
        so the shared decoder state and per-ASIC counters stay consistent.
        '''
        with frame.lock():

            # Parse the frame and update the local data containers
            _frame      = frame.getNumpy(0, frame.getPayload())
            _dataLen    = len(_frame)
            _startIndex = 0

            while _startIndex < _dataLen:

                self.asicDecoder.formatter(data=_frame,
                                           dataLen=_dataLen,
                                           startIndex=_startIndex)

                _nextIndex = self.asicDecoder.currentIndex

                # guard against a decoder that fails to advance
                if _nextIndex <= _startIndex:
                    break

                dec = self.asicDecoder

                if not dec.streamRxFrame:
                    self.nonPix2pgpFrameCnt += 1
                    break

                if dec.dropFrame:
                    self.pix2pgpDropFrameCnt += 1
                    _startIndex = _nextIndex
                    continue

                self.pix2pgpFrameCnt += 1

                _id = dec.asicId

                if _id not in self.asicId:
                    self.asicId.append(_id)

                _eventValid = not self._frameHasError()

                self.asicEventValid[_id].append(_eventValid)

                # FPGA lane status
                self.asicLaneValid[_id].append(list(dec.laneValid))
                self.asicLaneDecError[_id].append(list(dec.laneDecError))
                self.asicLanePauseError[_id].append(list(dec.lanePauseError))
                self.asicLaneFull[_id].append(list(dec.laneFull))
                self.asicLaneTimeout[_id].append(list(dec.laneTimeout))
                self.asicLaneDown[_id].append(list(dec.laneDown))

                # ASIC lane-header flags
                self.asicGlblOverOcc[_id].append(list(dec.asicGlblOverOcc))
                self.asicGlblPause[_id].append(list(dec.asicGlblPause))
                self.asicGlblPauseErr[_id].append(list(dec.asicGlblPauseErr))
                self.asicTrgCnt[_id].append(list(dec.asicGlblTrgCnt))

                # hits only for error-free frames
                if _eventValid:
                    self.asicHits[_id].append(list(dec.asicHits))
                else:
                    self.asicHits[_id].append([])
                    self.rejectedFrameCnt += 1

                _startIndex = _nextIndex
    #################################################################

    #################################################################
    def getStatistics(self):
        """
        Returns (frameCnts, asicStats) in the format expected by
        pix2pgp.Tools.printStatistics()
        """
        frameCnts = {
            'Pix2PGP Frames'           : self.pix2pgpFrameCnt,
            'Pix2PGP Drop-frames'      : self.pix2pgpDropFrameCnt,
            'Non-Pix2PGP frames'       : self.nonPix2pgpFrameCnt,
            'Rejected (laneRx errors)' : self.rejectedFrameCnt,
        }

        asicStats = {
            _id: {
                'eventValid'     : self.asicEventValid[_id],
                'hits'           : self.asicHits[_id],
                'laneValid'      : self.asicLaneValid[_id],
                'laneDecError'   : self.asicLaneDecError[_id],
                'lanePauseError' : self.asicLanePauseError[_id],
                'laneFull'       : self.asicLaneFull[_id],
                'laneTimeout'    : self.asicLaneTimeout[_id],
                'laneDown'       : self.asicLaneDown[_id],
                'overOcc'        : self.asicGlblOverOcc[_id],
                'pause'          : self.asicGlblPause[_id],
                'pauseErr'       : self.asicGlblPauseErr[_id],
                'trgCnt'         : self.asicTrgCnt[_id],
            }
            for _id in self.asicId
        }

        return frameCnts, asicStats
    #################################################################

    #################################################################
    def _stop(self):
        if self._printStats:
            frameCnts, asicStats = self.getStatistics()
            pix2pgp.Tools.printStatistics(frameCnts=frameCnts, asicStats=asicStats)
        super()._stop()
    #################################################################