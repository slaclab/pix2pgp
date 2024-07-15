# Define Firmware Version: v1.0.0.0
export PRJ_VERSION = 0x01000000

# # Define the Microblaze source path
# export SDK_SRC_PATH = $(PROJ_DIR)/../../shared/src

# COMMON_NAME is defined by application
export COMMON_NAME = Pix2PgpEmu

# COMM_TYPE is defined by application
export COMM_TYPE = pgp4
export INCLUDE_PGP4_6G = 1

# Define if you want to build the user Microblaze core
export BUILD_MB_CORE = 0

# Define if you want to build the DDR MIG core
export BUILD_MIG_CORE = 0

# Define if this is FSBL PROM address
export PROM_FSBL = 1

# Define target part
export PRJ_PART = XCKU035-SFVA784-1-C

# Setup for releases.yaml
export RELEASE = Pix2PgpEmu

# Define target output
target: prom
