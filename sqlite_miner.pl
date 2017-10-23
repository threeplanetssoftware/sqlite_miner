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
use File::Path;
use File::Spec::Functions;
use Getopt::Long qw(:config no_auto_abbrev);
use IO::Uncompress::AnyUncompress qw(anyuncompress $AnyUncompressError);
use POSIX qw(strftime);
use Time::HiRes qw(time);
use File::Find;

my $version = "1.0.0";

# Set up initial variables
my $start_time = time;
our $verbose = 0;
our $very_verbose = 0;
my $original_file = 0;
my $input_directory = 0;
my $help = 0;
my $decompress = 0;
my $export_files = 0;
#my $output_file = 0;

# Set up variables for what we mine
my $total_identified_blobs = 0;
my %mined_blobs;
my $results_file = 0;
$total_files = 0;

# Set up file system variables
my $export_directory;
my $base_directory = File::Spec->rel2abs(File::Spec->curdir());
my $output_directory = catdir($base_directory,'output');

# Read in options
GetOptions('file=s'       => \$original_file,
           'dir=s'        => \$input_directory,
           'decompress'   => \$decompress,
           'export'       => \$export_files,
           'verbose'      => \$verbose,
           'very-verbose' => \$very_verbose,
           'output=s'     => \$output_directory,
           'help'         => \$help);

# Set verbose if very-verbose was chosen
$verbose = $verbose || $very_verbose;

print_copyright();

# Set other files to read in
my $fun_stuff_file = "fun_stuff.pl";

# Import our hash of Fun Stuff to look for
require $fun_stuff_file;

# Ensure we have a file to work on
if($help || (!$original_file && !$input_directory)) {
  print_usage();
  exit();
}

# See if we have a directory to work on
if($input_directory) {

  # Make directory absolute
  $input_directory = File::Spec->rel2abs($input_directory);

  # Check to make sure the directory exists
  if(! -d $input_directory) {
    die "Directory $input_directory does not exist\n";
  }

  # Tell the user what we're doing
  print "Search Directory: $input_directory\n";

  # Capture the lowest level folder name for the output directory
  my $tmp_folder_name = "folder_search";
  if($input_directory =~ /([^\\\/]+)$/) {
    $tmp_folder_name = $1;
  }

  $output_directory = create_run_output_directory($output_directory, $tmp_folder_name, 1);
  $results_file = create_results_file($output_directory);

  # Pull out all potential SQLite files (based on file itself)
  my @files_to_mine;
  find(
    sub {
      if(! -d $_ && file_is_sqlite($_)) {
        my $tmp_filepath = $File::Find::name;
        print "Found SQLite: $tmp_filepath!\n" if $verbose;
        push(@files_to_mine, $tmp_filepath);
      }
    },
    $input_directory
  );
  print "\n" if $verbose;
  foreach $tmp_file (sort(@files_to_mine)){
    
    # Remember how many blobs we're currently at
    my $current_blob_count = $total_identified_blobs;

    # Run the parsing and store the export folder
    my $tmp_run_folder = mine_file($output_directory, $tmp_file, $results_file, 1);

    # Remove the copied files if we didn't actually do any work with them
    if($total_identified_blobs == $current_blob_count) {
      File::Path->remove_tree(File::Spec->abs2rel($tmp_run_folder)) or die "Can't remove $tmp_run_folder - $!\n";
    }
  }
}

# See if we have a file to work on
if($original_file) {
  # Check to ensure the file actually exists
  if(! -f $original_file) {
    die "File $original_file does not exist\n";
  }

  $output_directory = create_run_output_directory($output_directory, $original_file, 1);

  $results_file = create_results_file($output_directory);

  # Do work, son
  mine_file($output_directory, $original_file, $results_file, 0);
}

# Finish up the timing
my $end_time = time;
my $run_time = sprintf("%.4f", $end_time - $start_time);

# Give the user some feedback
print_final_results();

exit;

####################
# Functions follow #
####################

# Function that identifies a SQLite file
# Function expects a path
# Function returns a boolean
sub file_is_sqlite {
  my $file_path = @_[0];
  my $tmp_header;
  my $to_return = 0;

  # Open the file in binary mode
  open(TMP_INPUT, "<$file_path");
  binmode(TMP_INPUT);

  # Read in the first 16 bytes to find SQLite 3 format
  read TMP_INPUT, $tmp_header, 15;
  if($tmp_header =~ /^SQLite format 3$/) {
    $to_return = 1;
  }
  close(TMP_INPUT);
  return $to_return;
}

# Function to create the result file
# Function requires a path to the run folder and that's it
sub create_results_file {
  my $run_folder = @_[0];

  # Create the output file and spit the head to it
  my $output_file = File::Spec->catfile($run_folder, "results.csv");
  open(RESULT_OUTPUT, ">$output_file") or die "Can't open $output_file to write results\n";
  print RESULT_OUTPUT "\"Directory\",\"Database\",\"Table\",\"Column\",\"Primary Key Column\",\"Index\",\"File Type\"";
  if($export_files) {
    print RESULT_OUTPUT ",\"Export Filename\"";
  }
  if($decompress) {
    print RESULT_OUTPUT ",\"Decompressed?\"";
  }
  print RESULT_OUTPUT "\n";
  return $output_file;
}

# Function to handle mining one file
# Function expects the output directory and original filename
# Function returns the run folder
sub mine_file {
  my $output_directory = @_[0];
  my $original_file    = @_[1];
  my $output_file      = @_[2];
  my $is_directory_run = @_[3];

  $total_files += 1;

  # Create the output directory
  my $run_folder = $output_directory;

  if($is_directory_run) {  
    $run_folder = create_run_output_directory($output_directory, $original_file, 0);
  }

  if(!$output_file) {
    $output_file = create_results_file($run_folder);
  }

  # Make sure we don't mess up our original
  (my $original_file_volume, my $original_file_directory, my $original_file_name) = File::Spec->splitpath($original_file);
  $output_db_file = $original_file_name;
  $output_db_file =~ s/\.investigated//g;
  if($output_db_file =~ s/(\.[^.]*)$/.investigated$1/) {
    #$output_db_file =~ s/(\.[^.]*)$/.investigated$1/;
  } else {
    $output_db_file .= ".investigated";
  }
  my $output_db_file = File::Spec->catfile($run_folder,$output_db_file);
  copy($original_file, $output_db_file) or die "Can't copy $original_file to $output_db_file - $!\n";
  print "SQLite file: ".File::Spec->abs2rel($output_db_file)."\n" if $verbose;

  # Make a folder to export files to, if desired
  if($export_files) {
    $export_directory = File::Spec->catdir($run_folder, "exports");
    mkdir $export_directory;
    print "Export folder: ".File::Spec->abs2rel($export_directory)."\n" if $verbose;
  }

  # Set up database connection
  my $dsn = "DBI:SQLite:dbname=$output_db_file";
  my $dbh = DBI->connect($dsn) or die "Cannot open $output_db_file\n";

  print "Mining: ".File::Spec->abs2rel($output_db_file)."\n";

  print "\n" if $verbose;

  # Fetch the table information
  my %table_information = get_table_information($dbh);

  # Identify possibly interesting blob columns
  foreach $table (sort(keys(%table_information))) {
    print "Investigating $table\n" if $verbose;

    # Break this table out into schema and table name
    (my $schema, my $table_name) = normalize_table_name($table);

    # Figure out what the primary keys are for the table
    my @primary_key_columns = $dbh->primary_key('', $schema, $table_name);
    
    # Get a summary of each blob that may contain Fun Stuff
    my %tmp_table = %{$table_information{$table}};
    foreach $column (keys(%tmp_table)) {
      if($table_information{$table}{$column} eq "BLOB") {
        check_column_for_fun($dbh, $output_db_file, $table, $column, @primary_key_columns);
      }
    }
  }

  return $run_folder;
}

# Function to register a blob in our overall total
# Function takes the file_name, table_name, column_name, and file_type
# Function returns nothing (yet)
sub count_mined_blob {
  my $file_name   = @_[0];
  my $table_name  = @_[1];
  my $column_name = @_[2];
  my $file_type   = @_[3];

  # Ensure file exists
  if(!exists($mined_blobs{$file_name})) {
    $mined_blobs{$file_name} = {};
  }

  # Ensure table exists
  if(!exists($mined_blobs{$file_name}{$table_name})) {
    $mined_blobs{$file_name}{$table_name} = {};
  }

  # Ensure column exists
  if(!exists($mined_blobs{$file_name}{$table_name}{$column_name})) {
    $mined_blobs{$file_name}{$table_name}{$column_name} = {};
  }

  # Ensure file_type exists
  if(!exists($mined_blobs{$file_name}{$table_name}{$column_name}{$file_type})) {
    $mined_blobs{$file_name}{$table_name}{$column_name}{$file_type} = 0;
  }
  
  $mined_blobs{$file_name}{$table_name}{$column_name}{$file_type} += 1;
}


# Function to pull out interesting values in blobs
# Function needs to be provided a database handle, table name, column name, and array of primary keys
# Function will return nothing (yet)
sub check_column_for_fun {
  my $local_dbh   = @_[0];
  my $file_name   = @_[1];
  my $table_name  = @_[2];
  my $column_name = @_[3];
  my @primary_keys = @_[4];
        
  # Get the real table name
  (my $tmp_schema, my $tmp_table_name) = normalize_table_name($table_name);

  # Remember if we decompressed anything to go back and check again for more goodies
  my $decompressed_anything = 0;

  # Figure out our primary key
  my $primary_key_column;
  if(scalar(@primary_keys) >= 1) {
    $primary_key_column = @primary_keys[0];
  }

  # Build base query to get Fun Stuff
  my $base_query = "SELECT ";
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
      print "\t$file_type: Possibly found in $column_name " if $verbose;
      $total_identified_blobs += 1;
      count_mined_blob(File::Spec->abs2rel($file_name), $tmp_table_name, $column_name, $file_type);

      if($primary_key_column) {
        print "when $primary_key_column=$tmp_primary_key\n" if $verbose;
      } else {
        print "(no primary key)\n" if $verbose;
      }

      # Print out to the target CSV file
      (my $tmp_volume_for_output, my $tmp_directory_for_output, my $tmp_filename_for_output) = File::Spec->splitpath($file_name);
      print RESULT_OUTPUT "\"".File::Spec->abs2rel($tmp_directory_for_output)."\",".
                          "\"$tmp_filename_for_output\",".
                          "\"$tmp_table_name\",".
                          "\"$column_name\",".
                          "\"$primary_key_column\",".
                          "\"$tmp_primary_key\",".
                          "\"$file_type\"";

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
        (my $tmp_export_volume_for_output, my $tmp_export_directory_for_output, my $tmp_export_filename_for_output) = File::Spec->splitpath($tmp_export_file_path);
        print "\tExporting file as $tmp_export_filename_for_output\n" if $very_verbose;
        open(OUTPUT, ">$tmp_export_file_path");
        binmode(OUTPUT);
        print OUTPUT $tmp_data_blob;
        close(OUTPUT);
        print RESULT_OUTPUT ",\"$tmp_export_filename_for_output\"";
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
          print "\tUpdated $column_name in $table_name with decompressed data when $primary_key_column=$tmp_primary_key\n" if $very_verbose;
          $decompressed_anything = 1;
        } elsif(length($tmp_new_blob) > 0 and !$tmp_primary_key) {
          my $tmp_update_query = "UPDATE $table_name SET $column_name=?";
          my $tmp_update_query_handler = $local_dbh->prepare($tmp_update_query);
          $tmp_update_query_handler->execute($tmp_new_blob);
          print "\tUpdated $column_name in $table_name with decompressed data (no primary key)\n" if $very_verbose;
          $decompressed_anything = 1;
        } else {
          print "\tNot updating $column_name in $table_name with decompressed data due to likely bad decompression\n" if $very_verbose;
        }
        print RESULT_OUTPUT ",\"Decompressed\"";
      }
  
      # Close the line in the output file
      print RESULT_OUTPUT "\n";
    }
    
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

# Function to create the output directory. 
# Needs to know the starting directory and target filename
# Returns a string representing the output directory
sub create_run_output_directory {
  my $output_directory = @_[0];
  my $original_file    = @_[1];
  my $prepend_date     = @_[2]; # Boolean, 1 indicates we'll embed the date in front of this

  (my $tmp_volume, my $tmp_directory, my $tmp_filename) = File::Spec->splitpath($original_file);

  # Check to make sure the overall output folder exists
  if(! -e $output_directory) {
    print "Output folder: ".File::Spec->abs2rel($output_directory)."\n" if $verbose;
    mkdir $output_directory;
  }

  # Create a folder for this run's output
  my $base_run_folder = $tmp_filename;
  if($prepend_date) {
    $base_run_folder = strftime("%Y_%m_%d_$tmp_filename",localtime);
  }
  my $run_folder = File::Spec->catdir($output_directory,$base_run_folder);

  # Check to see if that folder already exists
  if(! -e $run_folder) {
    mkdir $run_folder;
    print "Output folder: ".File::Spec->abs2rel($run_folder)."\n" if $verbose;
  } else {
    my $tmp_counter = 1;
    while(-e $run_folder) {
      $tmp_counter += 1;
      $run_folder = File::Spec->catdir($output_directory, $base_run_folder."_".$tmp_counter);
    }
    mkdir $run_folder;
    print "Output folder: ".File::Spec->abs2rel($run_folder)."\n" if $verbose;
  }

  return $run_folder;
}

# Function to print our run results
sub print_final_results {

  # Tell the user what we did
  my $identify_stats = "$total_identified_blobs potential blob file";
  if($total_identified_blobs > 1) {
    $identify_stats .= "s identified";
  }
  if($export_files && $decompress) {
    $identify_stats .= ", decompressed, and exported";
  } elsif($export_files) {
    $identify_stats .= " and exported";
  } elsif($decompress) {
    $identify_stats .= " and decompressed";
  }

  my $stat_line = "$total_files SQLite file";
  if($total_files >= 1) {
    $stat_line .= "s";
  }

  print "\n#######################################################\n";
  print "$stat_line mined, $identify_stats in $run_time seconds.\n";
  print "Result file: ".File::Spec->abs2rel($results_file)."\n";

  # Loop over all files
  foreach $file_name (sort(keys(%mined_blobs))) {
    print "\n$file_name\n";
    foreach $table_name (sort(keys(%{$mined_blobs{$file_name}}))) {
      print "\t$table_name table:\n";
      foreach $column_name (keys(%{$mined_blobs{$file_name}{$table_name}})) {
        print "\t\t$column_name column: ";
        my $file_types = 0;
        foreach $file_type (keys(%{$mined_blobs{$file_name}{$table_name}{$column_name}})) {
          $count = $mined_blobs{$file_name}{$table_name}{$column_name}{$file_type};
          print ", " if $file_types;
          print "$count $file_type";
          $file_types += 1;
        }
        print "\n";
      }
    }
  }
  print "#######################################################\n";
}

# Function to print run header
sub print_copyright {
  print "SQLite Miner $version - Copyright (C) 2017 Jon Baumann, Ciofeca Forensics (https://www.ciofecaforensics.com)\n";
  print "\tThis program comes with ABSOLUTELY NO WARRANTY;\n";
  print "\tThis is free software, and you are welcome to redistribute it under certain conditions.\n";
  print "\tSee http://www.gnu.org/licenses/\n\n";
}

# Function to print usage instructions
sub print_usage {
  print "Usage:\n";
  print "\tperl sqlite_miner.pl --file=<path to database>|--dir=<path to directory> [--decompress] [--export] [--help] [--output=<path to output dir>] [--verbose|--very-verbose]\n";
  print "\nRequired Options (one of):\n";
  print "\t--file=<path>: Identifies the sqlite file to work on\n";
  print "\t--dir=<path>: Identifies a directory to recursively search to find SQLite files to work on.\n";
  print "\nOptional Options:\n";
  print "\t--decompress: If set, will decompress recognized and supported compressed blobs, replacing the original blob contents on the working copy\n";
  print "\t\tNote: Decompress gets very slow in a database with large compressed objects. Expect this to take a few seconds to run.\n";
  print "\t--export: If set, will rip all identified files out of blobs and save them in the output directory.\n";
  print "\t\tNote: Especially when used in conjunction with --decompress, this could get big.\n";
  print "\t--help: Prints this message\n";
  print "\t--output=<path>: If set, will store the results in the designated folder, vice the default 'output' folder\n";
  print "\t--verbose: If set, will give much more feedback to the user\n";
  print "\t--very-verbose: Similar to verbose, but more so\n";
  print "\nExamples:\n";
  print "\tperl sqlite_miner.pl --file=NoteStore.sqlite --decompress\n";
  print "\tperl sqlite_miner.pl --file=\"C:\\Users\\Test\\Desktop\\mailstore.sauronsmotherinlaw@gmail.com.db\" --export --verbose\n";
  print "\tperl sqlite_miner.pl --dir=\"/home/testbed/phone_rips/backup/apps/\" --export --verbose --decompress\n";
  return 1;
}
