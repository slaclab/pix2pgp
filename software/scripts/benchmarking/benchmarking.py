import math
import json
import argparse
import sys
import click
import matplotlib.pyplot as plt
import matplotlib.transforms as mtransforms
import numpy as np
import json

# ---------------------------------------------------------

# Set the argument parser
parser = argparse.ArgumentParser()

parser.add_argument(
    "--asicType",
    type     = str,
    required = False,
    default  = 'SparkPixS',
    help     = "options: SparkPixS, SparkPixT, Thriglav",
)

parser.add_argument(
    "--pgpClkPeriod",
    type     = float,
    required = False,
    default  = 5.384,
    help     = "Pix2Pgp Reference clock frequency (in ns)",
)

parser.add_argument(
    "--matrixClkPeriod",
    type     = float,
    required = False,
    default  = 10.768,
    help     = "Matrix Reference clock frequency (in ns)",
)

parser.add_argument(
    "--cols",
    type     = int,
    required = False,
    default  = 24,
    help     = "Number of Columns per Lane",
)

parser.add_argument(
    "--rows",
    type     = int,
    required = False,
    default  = 612,
    help     = "Number of Rows",
)

parser.add_argument(
    "--pauseHitLimit",
    type     = int,
    required = False,
    default  = 14,
    help     = "Number of hits (per-column) before pause kicks in",
)

parser.add_argument(
    "--wordWidth",
    type     = int,
    required = False,
    default  = 32,
    help     = "Width of data word (in bits)",
)

parser.add_argument(
    "--verbose",
    action = 'store_true',
    default = False)

parser.add_argument(
    "--getHitArray",
    action = 'store_true',
    default = False)

parser.add_argument(
    "--updateJson",
    action = 'store_true',
    default = False)
# ---------------------------------------------------------

# Get the arguments
args = parser.parse_args()

# ---------------------------------------------------------
def errorOut(msg='errorOut(msg=default)'):
    click.secho(f"[ERROR:] Invalid {msg} format. Exiting...", bg='red')
    sys.exit()

def roundUp(n, decimals=0):
    """Rounds a number up to a specified number of decimal places.

    Args:
        n: The number to round up.
        decimals: The number of decimal places (default is 0, which rounds to the nearest integer).

    Returns:
        The rounded-up number.
    """
    multiplier = 10 ** decimals
    return math.ceil(n * multiplier) / multiplier

def toFreq(periodIn, MHz=True):
    '''
    Input period in nanoseconds, output frequency in MHz
    '''
    if MHz:
        _scaleFactor = 1e3
        _roundFactor = 6
    else:
        _scaleFactor = 1e6 # kHz
        _roundFactor = 4

    return round(float((1.0/float(periodIn))*_scaleFactor), _roundFactor)

def hitsToTotalHits(hits, cols):
    '''
    Translates hits to bits
    '''
    return int(int(hits)*int(cols))

def pix2pgpFramePayload(hits, cols, wordWidth, numOfChunks=1):
    '''
    Returns the number of bits that yield hit data,
    and the number of bits of the entire frame (i.e. data + metadata/overhead)
    The overhead is affected by over how many pix2pgp frames are the data transmitted;
    i.e. if a pause-frame, the data will be mediated over many chunks/frames
    it is assumed that all columns are active for each chunk;
    this might not be the case for ASICs with very low occupancy
    '''
    _hitPayload      = hits*wordWidth
    _metadataPayload = cols*(wordWidth)*2*numOfChunks

    _totalPayload = _hitPayload + _metadataPayload + wordWidth*2*numOfChunks

    return _hitPayload, _totalPayload

def pgp4FrameEff(bitCount, numOfChunks=1):
    '''
    Assuming PGP4TxLite transmits data in 64-bit chunks
    '''

    _frameCnt = int(roundUp(bitCount/64))

    _data     = 64*_frameCnt
    _payload  = 66*_frameCnt
    _overhead = 2*66*numOfChunks # sof/eof

    return round(_data/(_payload+_overhead), 3)

# ---------------------------------------------------------
# ---------------------------------------------------------
# ---------------------------------------------------------
if __name__ == "__main__":
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    _pgpClkPeriod    = args.pgpClkPeriod
    _matrixClkPeriod = args.matrixClkPeriod
    _cols            = args.cols
    _rows            = args.rows
    _asicType        = args.asicType
    _getHitArray     = args.getHitArray
    _updateJson      = args.updateJson
    _verbose         = args.verbose
    _wordWidth       = args.wordWidth
    _pauseHitLimit   = args.pauseHitLimit
    _pgpClkFreq      = toFreq(_pgpClkPeriod)
    _matrixClkFreq   = toFreq(_matrixClkPeriod)
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    jsonPath = f"asics/{_asicType}.json"
    try:
        with open(jsonPath, 'r') as f:
            data = json.load(f)
    except FileNotFoundError:
        errorOut("Json file not found!")
        exit()

    occArray     = []
    colHitArray  = []
    allHitArray  = []
    colBusy      = []
    superBusy    = []
    totalLatency = []
    frameSize    = []

    for item in data:
        occArray.append(item.get("occ"))
        colHitArray.append(item.get("colHits"))
        allHitArray.append(item.get("allHits"))
        colBusy.append(item.get("colBusy"))
        superBusy.append(item.get("superBusy"))
        totalLatency.append(item.get("totalLatency"))
        frameSize.append(item.get("frameSize"))

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    if _getHitArray:

        _colHitArray = []
        _allHitArray = []

        for i in range(len(occArray)):

            _colHit = math.ceil(_rows * occArray[i] * 0.01)
            _colHitArray.append(_colHit)
            _allHitArray.append(hitsToTotalHits(_colHit, _cols))

        print(f"_colHitArray = {_colHitArray}")
        print(f"_allHitArray = {_allHitArray}")

        if _updateJson:
            for i in range(len(data)):
                data[i]['colHits'] = _colHitArray[i]
                data[i]['allHits'] = _allHitArray[i]

            # Write the updated data back to the JSON file
            with open(jsonPath, 'w') as f:
                json.dump(data, f, indent=2)  # Use indent for pretty formatting

            print(f"[INFO]: Successfully updated {jsonPath} with colHits and allHits!")

        sys.exit()
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    _len               = len(occArray)
    _maxRateKHzArray   = []
    _maxRateMHzArray   = []
    _bottleneckBusy    = []
    _hitPayloadArray   = []
    _totalPayloadArray = []
    _overallEffArray   = []
    _reqBandwidthArray = []

    for i in range(_len):
        _numOfChunks = int(roundUp(colHitArray[i]/_pauseHitLimit))
        _hitP, _allP = pix2pgpFramePayload(allHitArray[i], _cols, _wordWidth, _numOfChunks)
        _hitPayloadArray.append(_hitP)
        _totalPayloadArray.append(_allP)

        _pix2pgpEff = round(_hitP/_allP, 3)
        _overallEff = _pix2pgpEff*pgp4FrameEff(_allP, _numOfChunks)

        _overallEffArray.append(round(_overallEff*100, 3))

        totalLatency[i] = round((totalLatency[i]*_pgpClkPeriod/1e3), 2)

        # convert to bits
        frameSize[i] = round(frameSize[i]*8, 2)

        _bottleneckBusy.append(max(superBusy[i], colBusy[i]))
        _maxRateKHzArray.append(toFreq(_bottleneckBusy[i]*_pgpClkPeriod, False))
        _maxRateMHzArray.append(toFreq(_bottleneckBusy[i]*_pgpClkPeriod, True))

        _gbps = round(frameSize[i]*_maxRateKHzArray[i]/1e6, 3)

        _reqBandwidthArray.append(_gbps)

    if _verbose:
        print(f"---------- Verbose Mode -----------------")
        print("")
        print(f"occArray (%)                 = {occArray} ")
        print("")
        print(f"colHitArray (hits-per-col)   = {colHitArray} ")
        print("")
        print(f"allHitArray (hits-per-lane)  = {allHitArray} ")
        print("")
        print(f"hitPayloadArray              = {_hitPayloadArray} ")
        print("")
        print(f"totalPayloadArray            = {_totalPayloadArray} ")
        print("")
        print(f"Data Transfer Efficiency (%) = {_overallEffArray} ")
        print("")
        print(f"totalLatency (us)            = {totalLatency} ")
        print("")
        print(f"Frame Size (bits)            = {frameSize} ")
        print("")
        print(f"Required Bandwidth (Gb/s)    = {_reqBandwidthArray} ")
        print("")
        print(f"_maxRateKHzArray (kHz)       = {_maxRateKHzArray} ")
        print("")
        print(f"_maxRateMHzArray (MHz)       = {_maxRateMHzArray} ")
        print("")
        print(f"---------- INFO -----------------")
        print(f"Pix2Pgp Clock Period    = {_pgpClkPeriod} ns")
        print(f"Pix2Pgp Clock Frequency = {_pgpClkFreq} MHz")
        print(f"Matrix Clock Period     = {_matrixClkPeriod} ns")
        print(f"Matrix Clock Frequency  = {_matrixClkFreq} MHz")
        print(f"---------------------------------")

    ################################################################################################

    ################################################################################################

    # Create the plot
    plt.figure(figsize=(10, 6))
    plt.subplots_adjust(bottom=0.2)  # Keep this to manage overall layout

    # Set y-axis to logarithmic scale
    plt.yscale('log')

    # Plot superBusy as a smooth line
    plt.plot(occArray, [toFreq(x * _pgpClkPeriod, False) for x in superBusy], color='tab:orange', linestyle='-', linewidth=2, label='Pix2Pgp Max Rate')  # Changed color and linestyle

    # Plot data with a larger marker size
    plt.plot(occArray, _maxRateKHzArray, marker='o', color='tab:blue', linestyle='-', linewidth=2, markersize=8, label='True Max Rate')

    plt.legend(loc='upper right', fontsize=12, frameon=True, fancybox=True, shadow=True, borderpad=1) # add a legend

    # Set grid
    plt.grid(True, which='both', linestyle='--', linewidth=1)

    # Customize x and y labels
    plt.ylabel("Max Triggering Rate (kHz)", fontsize=14, weight='bold', color='darkslategray')

    # Set title
    plt.title(f"{_asicType} Occupancy vs Max Triggering Rate - Matrix Clock Freq = {_matrixClkFreq} MHz; Pix2Pgp/PGP Clock Freq = {_pgpClkFreq} MHz", fontsize=14, weight='bold', color='navy')

    # Select custom x-ticks, skipping the range from 2.0 to 10.0
    xticks = np.concatenate([np.arange(0.5, 1.0, 0.5), np.arange(5.0, 101, 5)])

    # Apply the custom xticks to the plot
    plt.xticks(xticks, rotation=45, fontsize=10, weight='bold', color='darkred')  # Font size kept at 10

    # Set y-ticks
    plt.yticks(fontsize=12, weight='bold', color='darkred')

    # Add markers to each data point
    for x, y in zip(occArray, _maxRateKHzArray):
        if x in xticks:
            plt.text(x + 1, y * 1.1, f"{y:.1f}", fontsize=10, color='black', ha='center', weight='bold', va='bottom')

    # Adjust Total Hits labels
    # increase offset to move the totalHit labels UP
    _offset=1.2
    for x, total_hits in zip(occArray, allHitArray):
        if x in xticks:
            plt.text(x-2, _offset, f"Total Hits = {total_hits}", rotation=45, ha='center', va='bottom', fontsize=9, color='darkgreen', weight='bold')

    # Set axis limits
    plt.xlim(-1, 105)
    plt.ylim(4, max(_maxRateKHzArray) * 1.5)  # Adjust upper limit

    ax = plt.gca()
    trans = mtransforms.blended_transform_factory(ax.transAxes, ax.transAxes)  # Use relative coords
    ax.text(0.5, -0.2, "Occupancy (%)", fontsize=12, weight='bold', color='darkslategray', ha='center', va='top', transform=trans)

    # Show the plot
    plt.tight_layout()
    plt.show()

    # ---------------------------------------

    plt.figure(figsize=(8, 6))

    plt.yscale('log')

    plt.plot(occArray, totalLatency, marker='x', linestyle='--', linewidth=2, color='red', label='System Latency', markersize=8)

    xticks = np.concatenate([np.arange(0.5, 1.0, 0.5), np.arange(5.0, 101, 5)])
    plt.xticks(xticks, rotation=45, fontsize=10, weight='bold', color='darkred')

    plt.title(f"{_asicType} Occupancy vs ASIC-FPGA Frame Output Latency - Pix2Pgp/PGP Clock Freq = {_pgpClkFreq} MHz", fontsize=14, weight='bold', color='navy')

    plt.ylabel("System Latency (us)", fontsize=14, weight='bold', color='darkslategray')

    # Add markers to each data point
    for x, y in zip(occArray, totalLatency):
        if x in xticks:
            plt.text(x*1.01-0.8, y*1.05, f"{y:.1f}", fontsize=10, color='black', ha='center', weight='bold', va='bottom')

    # increase offset to move the totalHit labels UP
    _offset=0.75
    for x, total_hits in zip(occArray, allHitArray):
        if x in xticks:
            plt.text(x-2, _offset, f"Total Hits = {total_hits}", rotation=45, ha='center', va='bottom', fontsize=9, color='darkgreen', weight='bold')

    plt.grid(True, which='both', linestyle='--', linewidth=1)
    ax = plt.gca()
    trans = mtransforms.blended_transform_factory(ax.transAxes, ax.transAxes)  # Use relative coords
    ax.text(0.5, -0.2, "Occupancy (%)", fontsize=12, weight='bold', color='darkslategray', ha='center', va='top', transform=trans)

    for label in ax.get_yticklabels():
        label.set_weight('bold')
        label.set_color('darkred')
        label.set_fontsize(10)

    plt.tight_layout() # Adjusts the plot to make sure everything fits
    plt.show()

    # ---------------------------------------

    plt.figure(figsize=(8, 6))

    #plt.yscale('log')

    plt.bar(occArray, _reqBandwidthArray, color='red', label='Required Back-End Bandwidth', width=0.3)

    xticks = np.concatenate([np.arange(0.5, 1.0, 0.5), np.arange(5.0, 101, 5)])
    plt.xticks(xticks, rotation=45, fontsize=10, weight='bold', color='darkred')

    plt.title(f"{_asicType} Occupancy vs Required Back-End Bandwidth - Pix2Pgp/PGP Clock Freq = {_pgpClkFreq} MHz", fontsize=14, weight='bold', color='navy')

    plt.ylabel("Required Bandwidth (Gb/s)", fontsize=14, weight='bold', color='darkslategray')

    # increase offset to move the totalHit labels UP
    # _offset=-4.5
    # for x, total_hits in zip(occArray, allHitArray):
    #     if x in xticks:
    #         plt.text(x-2, _offset, f"Total Hits = {total_hits}", rotation=45, ha='center', va='bottom', fontsize=9, color='darkgreen', weight='bold')

    plt.grid(True, which='both', linestyle='--', linewidth=1)
    ax = plt.gca()
    # trans = mtransforms.blended_transform_factory(ax.transAxes, ax.transAxes)  # Use relative coords
    plt.xlabel("Occupancy (%)", fontsize=14, weight='bold', color='darkslategray')

    for label in ax.get_yticklabels():
        label.set_weight('bold')
        label.set_color('darkred')
        label.set_fontsize(10)

    plt.show()