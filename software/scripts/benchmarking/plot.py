import measurements
import argparse
import sys
import click
import matplotlib.pyplot as plt
import numpy as np

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
    "--clkPeriod",
    type     = float,
    required = False,
    default  = 5.384,
    help     = "Reference clock frequency (in ns)",
)

parser.add_argument(
    "--cols",
    type     = int,
    required = False,
    default  = 24,
    help     = "Number of Columns",
)

parser.add_argument(
    "--maxHits",
    type     = int,
    required = False,
    default  = 13,
    help     = "Max Hits Per Frame",
)

parser.add_argument(
    "--verbose",
    action = 'store_true',
    default = False)

parser.add_argument(
    "--plotMaxRate",
    action = 'store_true',
    default = False)

# ---------------------------------------------------------

# Get the arguments
args = parser.parse_args()

# ---------------------------------------------------------
def errorOut(msg='errorOut(msg=default)'):
    click.secho(f"[ERROR:] Invalid {msg} format. Exiting...", bg='red')
    sys.exit()

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

# ---------------------------------------------------------
# ---------------------------------------------------------
# ---------------------------------------------------------
if __name__ == "__main__":
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    _clkPeriod   = args.clkPeriod
    _cols        = args.cols
    _maxHits     = args.maxHits
    _plotMaxRate = args.plotMaxRate
    _asicType    = args.asicType
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    occArray     = measurements.occArray
    hitArray     = measurements.hitArray
    colBusy      = measurements.colBusy
    superBusy    = measurements.superBusy

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    _clkFreq   = toFreq(_clkPeriod)
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    if len(occArray) == len(hitArray)     and \
       len(occArray) == len(colBusy)      and \
       len(occArray) == len(superBusy):
       print("Lengths Good.")
    else:
        errorOut("Array Length")

    _len             = len(occArray)
    _totalHitArray   = []
    _maxRateKHzArray = []
    _maxRateMHzArray = []


    for i in range(_len):
        _totalHitArray.append(hitsToTotalHits(hitArray[i], _cols))

        if hitArray[i] < _maxHits:
            _maxRateKHzArray.append(toFreq(superBusy[i]*_clkPeriod, False))
            _maxRateMHzArray.append(toFreq(superBusy[i]*_clkPeriod, True))
        else:
            _maxRateKHzArray.append(toFreq(colBusy[i]*_clkPeriod, False))
            _maxRateMHzArray.append(toFreq(colBusy[i]*_clkPeriod, True))

    if args.verbose:
        print(f"---------- Verbose Mode -----------------")
        print(f"occArray               = {occArray} ")
        print(f"hitArray               = {hitArray} ")
        print(f"_totalHitArray         = {_totalHitArray} ")
        print(f"_maxRateKHzArray (kHz) = {_maxRateKHzArray} ")
        print(f"_maxRateMHzArray (MHz) = {_maxRateMHzArray} ")

    print(f"---------- INFO -----------------")
    print(f"Clock Period    = {_clkPeriod} ns")
    print(f"Clock Frequency = {_clkFreq} MHz")
    print(f"---------------------------------")

    ################################################################################################

    if _plotMaxRate:
        # Create the plot
        plt.figure(figsize=(10, 6))

        # Plot data with a larger marker size
        plt.plot(occArray, _maxRateKHzArray, marker='o', color='tab:blue', linestyle='-', linewidth=2, markersize=10)

        # Set grid
        plt.grid(True, which='both', linestyle='--', linewidth=0.7)

        # Customize x and y labels (Increased labelpad for more space)
        plt.xlabel("Occupancy (%)", fontsize=14, weight='bold', color='darkslategray', labelpad=80)
        plt.ylabel("Max Triggering Rate (kHz)", fontsize=14, weight='bold', color='darkslategray')

        # Set title
        plt.title(f"Occupancy vs Max Triggering Rate - {_asicType}", fontsize=16, weight='bold', color='navy')

        # Select custom x-ticks, skipping the range from 2.0 to 10.0
        xticks = np.concatenate([np.arange(0.5, 1.0, 0.5), np.arange(5.0, 101, 5)])

        # Apply the custom xticks to the plot
        plt.xticks(xticks, rotation=45, fontsize=12, weight='bold', color='darkred')

        # Set y-ticks
        plt.yticks(fontsize=12, weight='bold', color='darkred')

        # Add markers to each data point with adjusted annotation positions
        for x, y in zip(occArray, _maxRateKHzArray):
            # Display the text label only if the x value is in the selected range
            if x in xticks:
                plt.text(x+1, y+15, f"{y:.1f}", fontsize=10, color='black', ha='center', weight='bold', va='bottom')

        # Add extra labels for the Total Hits below the x-axis ticks
        # Adjusting the vertical placement to avoid overlap
        for x, total_hits in zip(occArray, _totalHitArray):
            # Place total hits labels below the x-axis with some spacing, but only for selected x-values
            if x in xticks:
                plt.text(x, -100, f"Total Hits = {total_hits}", rotation=45, ha='center', va='top', fontsize=9, color='darkgreen', weight='bold')

        # Set axis limits (ranges)
        plt.xlim(-1, 105)  # Set the x-axis range from 0 to 100
        plt.ylim(-20, 1200)  # Set the y-axis range (example: from 0 to 1200)

        # Show the plot
        plt.tight_layout()
        plt.show()
