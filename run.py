import sys
import config
from processor import process_all

# If user runs with --dry-run, do not copy files.
if "--dry-run" in sys.argv:
    config.DRY_RUN = True
    print("DRY RUN MODE: Files will not be copied.")

# Process all files in the input folder.
process_all()

    
