# SQLite Miner
By: Jon Baumann, [Ciofeca Forensics](https://www.ciofecaforensics.com)

## About
This script mines SQLite databases for hidden gems that might be overlooked.

## How It Works
This script 

## Usage
### Base
This script is run by perl on a command line. 

### Options
The required options that are currently supported are (one of):
1. `--file=`: This option tells the script where to find the SQLite you want to mine. If neither --file or --dir are used, the script will not run.
2. `--dir=`: This option tells the script where to find a directory to recursively search for SQLite format 3 database files and to parse each of them as if the --fiile option was called on them above.

The optional arguments are:
2. `--decompress`: This option tells the script to "show its work" and leave the gzipped blobs and gunzipped blobs in the script's directory for the forensics examiner to have better access to them.
3. `--help`: This option prints the usage information.

## Requirements
This script requires the following Perl packages:
1. DBI
2. FILE::Copy
3. IO::Uncompress
4. Getopt


