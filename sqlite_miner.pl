#   SQLite Miner is a short script to mine potentially overlooked data from SQLite databases
#   Copyright (C) 2017 Jon Baumann

#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.

#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.

#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

use Data::Dumper;
use DBI;
use File::Copy;
use File::Spec::Functions;
use Getopt::Long qw(:config no_auto_abbrev);
use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
use POSIX qw(strftime);

# Set up initial variables
our $verbose = 0;
my $original_file = 0;
my $help = 0;
my $decompress = 0;
my $export_files = 0;
my $output_file = 0;

# Set up file system variables
my $export_directory;
my $base_directory = File::Spec->rel2abs(File::Spec->curdir());
my $output_directory = catdir($base_directory,'output');

# Set other files to read in
my $fun_stuff_file = "fun_stuff.pl";

# Import our hash of Fun Stuff to look for
require $fun_stuff_file;

# Read in options
GetOptions('file=s'     => \$original_file,
           'decompress' => \$decompress,
           'export'     => \$export_files,
           'verbose'    => \$verbose,
           'output=s'   => \$output_directory,
           'help'       => \$help);

# Ensure we have a file to work on
if($help || !$original_file) {
  print_usage();
  exit();
}

# Check to ensure the file actually exists
if(! -f $original_file) {
  die "File $original_file does not exist\n";
}

##########################
# Preparation of Folders #
##########################

# Create the output directory
my $run_folder = create_run_output_directory($output_directory, $original_file);
print "Saving files in $run_folder\n";

# Make sure we don't mess up our original
(my $original_file_volume, my $original_file_directory, my $original_file_name) = File::Spec->splitpath($original_file);
$output_db_file = $original_file_name;
$output_db_file =~ s/(\.[^.]*)/.investigated$1/;
my $output_db_file = File::Spec->catfile($run_folder,$output_db_file);
copy($original_file, $output_db_file);
print "Copying original file to preserve it, working from $output_db_file\n" if $verbose;

# Create the output file and spit the head to it
$output_file = File::Spec->catfile($run_folder, "results.csv");
open(RESULT_OUTPUT, ">$output_file") or die "Can't open result file to write\n";
print RESULT_OUTPUT "\"Database\",\"Table\",\"Column\",\"Primary Key Column\",\"Index\",\"File Type\",\"Export Filename\",\"Compression\"\n";

# Make a folder to export files to, if desired
if($export_files) {
  $export_directory = File::Spec->catdir($run_folder, "exports");
  mkdir $export_directory;
  print "Creating folder for file exports: $export_directory\n";# if $verbose;
}

##################
# Database Time! #
##################

# Set up database connection
my $dsn = "DBI:SQLite:dbname=$output_db_file";
my $dbh = DBI->connect($dsn) or die "Cannot open $output_db_file\n";

print "Opening $output_db_file to search for buried treasure\n";

# Fetch the table information
my %table_information = get_table_information($dbh);

# Identify possibly interesting blob columns
foreach $table (sort(keys(%table_information))) {
  print "Investigating $table\n" if $verbose;

  # Break this table out into schema and table name
  (my $schema, my $table_name) = normalize_table_name($table);

  # Figure out what the primary keys are for the table
  @primary_key_columns = $dbh->primary_key('', $schema, $table_name);
  
  # Get a summary of each blob that may contain Fun Stuff
  my %tmp_table = %{$table_information{$table}};
  foreach $column (keys(%tmp_table)) {
    if($table_information{$table}{$column} eq "BLOB") {
      check_column_for_fun($dbh, $table, $column, @primary_key_columns);
    }
  }
}

# Clean up nicely
$dbh->disconnect();
close(RESULT_OUTPUT);

####################
# Functions follow #
####################

# Function to pull out interesting values in blobs
# Function needs to be provided a database handle, table name, column name, and array of primary keys
# Function will return nothing (yet)
sub check_column_for_fun {
  my $local_dbh   = @_[0];
  my $table_name  = @_[1];
  my $column_name = @_[2];
  my @primary_keys = @_[3];

        
  # Get the real table name
  (my $tmp_schema, my $tmp_table_name) = normalize_table_name($table_name);

  # Remember if we decompressed anything to go back and check again for more goodies
  my $decompressed_anything = 0;

  # Figure out our primary key
  $primary_key_column;
  if(scalar(@primary_keys) >= 1) {
    $primary_key_column = @primary_keys[0];
  }

  # Build base query to get Fun Stuff
  $base_query = "SELECT ";
  if($primary_key_column) {
    $base_query .= "$primary_key_column, ";
  }
  $base_query .= "$column_name FROM $table_name ";

  # Use the base query to loop over all the things we're looking for
  foreach $file_type (sort(keys(%fun_stuff))) {
    my $tmp_query = $base_query . "WHERE hex($column_name) LIKE '".$fun_stuff{$file_type}{'regex'}."'";

    # Build and execute query
    my $tmp_query_handler = $local_dbh->prepare($tmp_query);
    $tmp_query_handler->execute();

    # Loop over all rows returned
    while(my @tmp_row = $tmp_query_handler->fetchrow_array()) {
      my $tmp_primary_key;
      my $tmp_data_blob;

      # Rip out the data
      if($primary_key_column) {
        $tmp_primary_key = $tmp_row[0];
        $tmp_data_blob = $tmp_row[1];
      } else {
        $tmp_data_blob = $tmp_row[0];
      }

      # Display output, if relevant
      print "\t$file_type: Possibly found in $column_name ";
      if($primary_key_column) {
        print "when $primary_key_column=$tmp_primary_key\n";
      } else {
        print "(no primary key)\n";
      }

      # Print out to the target CSV file
      print RESULT_OUTPUT "\"$original_file_name\",\"$tmp_table_name\",\"$column_name\",\"$primary_key_column\",\"$tmp_primary_key\",\"$file_type\",";

      # Save out the blob if we're exporting files
      if($export_files) {

        # Build the export filename (TABLE_COLUMN_[PRIMARYKEYCOLUMN_PRIMARYKEY].blob.EXTENSION)
        my $tmp_export_file_name = $tmp_table_name."-".$column_name;
        if($tmp_primary_key) {
          $tmp_export_file_name .= "-".$primary_key_column."-".$tmp_primary_key;
        }
        $tmp_export_file_name .= ".blob.".$fun_stuff{$file_type}{'extension'};
        $tmp_export_file_path = File::Spec->catfile($export_directory, $tmp_export_file_name);
        $tmp_export_file_counter = 1;
        
        # Keep looping until we're sure we have a unique file path
        while(-e $tmp_export_file_path) {
          $tmp_export_file_counter += 1;
          $tmp_export_file_path = File::Spec->catfile($export_directory, $tmp_export_file_name."_".$tmp_export_file_counter);
        }

        # Export the file        
        print "Exporting file as $tmp_export_file_path\n" if $verbose;
        open(OUTPUT, ">$tmp_export_file_path");
        binmode(OUTPUT);
        print OUTPUT $tmp_data_blob;
        close(OUTPUT);
        print RESULT_OUTPUT "\"$tmp_export_file_path\",";
      } else {
        print RESULT_OUTPUT ",";
      }

      # Update the database if we're decompressing values
      if($decompress and $fun_stuff{$file_type}{'compression'}) {
        $tmp_new_blob;

        # Decompress the blob
        anyuncompress(\$tmp_data_blob => \$tmp_new_blob);

        # Build and execute our query to update the database
        if(length($tmp_new_blob) > 0 and $tmp_primary_key) {
          my $tmp_update_query = "UPDATE $table_name SET $column_name=? WHERE $primary_key_column=?";
          my $tmp_update_query_handler = $local_dbh->prepare($tmp_update_query);
          $tmp_update_query_handler->execute($tmp_new_blob, $tmp_primary_key);
          print "\tUpdated $column_name in $table_name with decompressed data when $primary_key_column=$tmp_primary_key\n" if $verbose;
          $decompressed_anything = 1;
        } elsif(length($tmp_new_blob) > 0 and !$tmp_primary_key) {
          my $tmp_update_query = "UPDATE $table_name SET $column_name=?";
          my $tmp_update_query_handler = $local_dbh->prepare($tmp_update_query);
          $tmp_update_query_handler->execute($tmp_new_blob);
          print "\tUpdated $column_name in $table_name with decompressed data (no primary key)\n" if $verbose;
          $decompressed_anything = 1;
        } else {
          print "\tNot updating $column_name in $table_name with decompressed data due to likely bad decompression\n";
        }
        print RESULT_OUTPUT "\"Decompressed\"\n";
      } else {
        print RESULT_OUTPUT "\n";
      }
    }
    
  }

  # Kick off this same column again if we decompressed anything
  if($decompressed_anything) {
    check_column_for_fun($local_dbh, $table_name, $column_name, @primary_keys);
  }
}

# Function normalizes a table name
# Expects a table name
# Returns a nicer one, if it exists
sub normalize_table_name {
  my $original_table = @_[0];

  my $table_name;
  my $schema;

  # Turn "main"."TableName" into just TableName
  if($original_table =~ /^"(.*)"\."(.*)"$/) {
    $schema = $1;
    $table_name = $2;
  }
  return ($schema, $table_name);
}

# Function to determine the names of tables, and each table's column names and types
# Needs to get a database handle returns a hash of hashes, indexed by the table name
sub get_table_information {
  # Only argument should be the database handle
  my $local_dbh = @_[0];
  my %table_columns;

  # Fetch a list of table names
  my @tables = $local_dbh->tables('', '%', '%', 'TABLE');

  # Iterate over the tables, pulling one row out of each and using that to find the column names and types
  foreach $table (sort(@tables)) {
    $table_columns{$table} = {};

    # Set up the query to pull on row from this specific table
    my $table_query = "SELECT * FROM $table LIMIT 1";
    my $table_query_handler = $local_dbh->prepare($table_query);
    $table_query_handler->execute();

    # Snag a row and the arrays for types and names
    my $row = $table_query_handler->fetchrow_hashref();
    @types = @{$table_query_handler->{'TYPE'}};
    @names = @{$table_query_handler->{'NAME_uc'}};

    # Loop over the types and names, inserting them into the overall hash
    while(scalar(@types) > 0) {
      my $tmp_type = shift @types;
      my $tmp_name = shift @names;
      $table_columns{$table}{$tmp_name} = $tmp_type;
    }
  }
  return %table_columns;
}

# Function to print usage instructions
sub print_usage {
  print "Need to finish this\n";
}

# Function to create the output directory. 
# Needs to know the starting directory and target filename
# Returns a string representing the output directory
sub create_run_output_directory {
  my $output_directory = @_[0];
  my $original_file = @_[1];

  (my $tmp_volume, my $tmp_directory, my $tmp_filename) = File::Spec->splitpath($original_file);

  # Check to make sure the overall output folder exists
  if(! -e $output_directory) {
    print "Creating output folder: $output_directory\n" if $verbose;
    mkdir $output_directory;
  }

  # Create a folder for this run's output
  my $base_run_folder = strftime("%Y_%m_%d_%H:%M_$tmp_filename",localtime);
  my $run_folder = File::Spec->catdir($output_directory,$base_run_folder);

  # Check to see if that folder already exists
  if(! -e $run_folder) {
    mkdir $run_folder;
    print "Creating output folder for this run: $run_folder\n" if $verbose;
  } else {
    my $tmp_counter = 1;
    while(-e $run_folder) {
      $tmp_counter += 1;
      $run_folder = File::Spec->catdir($output_directory, $base_run_folder."_".$tmp_counter);
    }
    mkdir $run_folder;
    print "Creating output folder for this run: $run_folder\n" if $verbose;
  }

  return $run_folder;
}
