import argparse
import random
import sys
import os

# Set the argument parser
parser = argparse.ArgumentParser()

parser.add_argument(
    "--fileDump",
    type     = str,
    required = False,
    default  = './foo.dat',
    help     = "Default data file",
)

parser.add_argument(
    "--newFile",
    action   ="store_true",
    help     = "delete file and then start appending again",
)

parser.add_argument(
    "--numOfLanes",
    type     = int,
    required = False,
    default  = 8,
    help     = "number of lanes",
)

parser.add_argument(
    "--numOfCols",
    type     = int,
    required = False,
    default  = 24,
    help     = "number of lanes",
)

parser.add_argument(
    "--minRange",
    type     = int,
    required = False,
    default  = 0,
    help     = "minimum hitLen value",
)

parser.add_argument(
    "--maxRange",
    type     = int,
    required = False,
    default  = 4,
    help     = "maximum hitLen value",
)

parser.add_argument(
    "--clkWait",
    type     = int,
    required = False,
    default  = 93,
    help     = "Clock Cycles to Wait",
)

parser.add_argument(
    "--laneEnable",
    type=str,
    required=False,
    default="1,1,1,1,1,1,1,1",
    help="Comma-separated list of ones and zeros, set to 1 enable a lane",
)

def genHitLines(minRange, maxRange, numOfLanes, numOfCols, laneEnable, clkWait):
    result = []
    result.append(f"")
    result.append(f"-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
    result.append(f"wait for CLK_PERIOD_SPARSE_C*{clkWait};")
    result.append(f"-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")

    for lane in range(numOfLanes):
        result.append(f"---------------------------------------")
        for col in range(numOfCols):
            rand_value = random.randint(minRange, maxRange)
            if laneEnable[lane] == '0':
                rand_value = 0
            result.append(f"   hitLen({lane})({col}) <= toSlv({rand_value}, hitLen(0)(0)'length);")
        result.append(f"---------------------------------------")

    result.append(f"-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
    result.append(f"sro  <= '1';")
    result.append(f"wait for CLK_PERIOD_SPARSE_C*2;")
    result.append(f"sro  <= '0';")
    result.append(f"-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
    result.append(f"")

    return result

# Get the arguments
args = parser.parse_args()

#################################################################
if __name__ == "__main__":

    _laneEnable = args.laneEnable.split(',')

    if len(_laneEnable) != args.numOfLanes:
        print("ERROR: laneEnable length does not match the number of lanes")
        sys.exit()

    if args.newFile and os.path.exists(args.fileDump):
        os.remove(args.fileDump)
        print(f"Deleted existing file: {args.fileDump}")

    _hitLines = genHitLines(minRange=args.minRange,
                            maxRange=args.maxRange,
                            numOfLanes=args.numOfLanes,
                            numOfCols=args.numOfCols,
                            laneEnable=_laneEnable,
                            clkWait=args.clkWait)

    # Write the lines to the specified file
    with open(args.fileDump, 'a') as file:
        for line in _hitLines:
            file.write(line + '\n')

    for line in _hitLines:
        print(line)