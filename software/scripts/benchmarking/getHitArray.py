import measurements
import argparse

# Set the argument parser
parser = argparse.ArgumentParser()

parser.add_argument(
    "--rows",
    type     = int,
    required = False,
    default  = 640,
    help     = "Number of Rows",
)

# Get the arguments
args = parser.parse_args()

# ---------------------------------------------------------
# ---------------------------------------------------------
# ---------------------------------------------------------
if __name__ == "__main__":

    print("hitArray = [")

    for i in range(len(measurements.occArray)):

        _extraStr = ','
        if i+1 == len(measurements.occArray):
          _extraStr = ']'

        print("    " + str(int(args.rows*measurements.occArray[i]*0.01)) + _extraStr + "   # " + str(measurements.occArray[i]))