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

# To do list
# - Flag potentially malicious files to block export
# - Specify file types to export
# - Support magic numbers that aren't at the start of the file

$FUN_STUFF_FILE_TYPE  = 0;
$FUN_STUFF_COMPRESSED = 1;
$FUN_STUFF_EXTENSION  = 2;
$FUN_STUFF_OFFSET     = 3;
$FUN_STUFF_REGEX      = 4;

# Hash of things to look for
%fun_stuff;

# Compressed formats that we may want to decompress
add_fun_thing_to_hash('7ZIP',     0, '7z',   0, '377abcaf271c%');
add_fun_thing_to_hash('BZIP',     1, 'bz2',  0, '425a68%');
add_fun_thing_to_hash('GZIP',     1, 'gz',   0, '1f8b%');
add_fun_thing_to_hash('LZ4',      1, 'lz4',  0, '04224d18%');
add_fun_thing_to_hash('RAR',      0, 'rar',  0, '526172211a0700%');
add_fun_thing_to_hash('RAR_5.0',  0, 'rar',  0, '526172211a070100%');
add_fun_thing_to_hash('TAR',      0, 'tar', 257,'7573746172%');
add_fun_thing_to_hash('ZIP',      1, 'zip',  0, '504b0304%');
add_fun_thing_to_hash('ZIP_EMPTY',1, 'zip',  0, '504b0506%');
add_fun_thing_to_hash('ZIP_SPAN', 1, 'zip',  0, '504b0708%');
add_fun_thing_to_hash('ZLIB_LOW', 1, 'zlib', 0, '7801%');
add_fun_thing_to_hash('ZLIB',     1, 'zlib', 0, '789c%');
add_fun_thing_to_hash('ZLIB_MAX', 1, 'zlib', 0, '78da%');

# Possible property files
add_fun_thing_to_hash('BPLIST', 0, 'bplist', 0, '62706c697374%');
add_fun_thing_to_hash('XML',    0, 'xml',    0, '3c3f786d6c20%');

# Images
add_fun_thing_to_hash('BMP',      0, 'bmp', 0, '424d%');
add_fun_thing_to_hash('JPEG_RAW', 0, 'jpg', 0, 'ffd8ffdb%');
add_fun_thing_to_hash('JPEG_JFIF',0, 'jpg', 0, 'ffd8ffe0____4a4649460001%');
add_fun_thing_to_hash('JPEG_EXIF',0, 'jpg', 0, 'ffd8ffe1____457869660000%');
add_fun_thing_to_hash('GIF',      0, 'gif', 0, '474946383_61%');
add_fun_thing_to_hash('PNG',      0, 'png', 0, '89504e470d0a1a0a%');
add_fun_thing_to_hash('WEBP',     0, 'webp',0, '52494646________57454250%');

# Media
add_fun_thing_to_hash('MP3',    0, 'mp3',  0, 'fffb%');
add_fun_thing_to_hash('MP3_ID3',0, 'mp3',  0, '494433%');
add_fun_thing_to_hash('OGG',    0, 'ogg',  0, '4f676753%');
add_fun_thing_to_hash('WAV',    0, 'wav',  0, '52494646________57415645%');
add_fun_thing_to_hash('FLAC',   0, 'flac', 0, '664c6143%');

# Documents
add_fun_thing_to_hash('PDF',   0, 'pdf',  0, '25504446%');
add_fun_thing_to_hash('RTF',   0, 'rtf',  0, '7b5c72746631%');
add_fun_thing_to_hash('iNote', 0, 'note', 0, '080012%');

# Executables
add_fun_thing_to_hash('DALVIK_EXECUTABLE', 0, 'dex', 0, '6465780a30333500%');

return 1;

####################
# Functions follow #
####################

# Function to add Fun Things to our hash. 
# Function expects:
# A name for the file type (such as GZIP)
# Whether or not this file is compressed
# A regex to find it
# The file extension to be applied if exported
sub add_fun_thing_to_hash {
  my $file_type          = @_[$FUN_STUFF_FILE_TYPE];
  my $file_is_compressed = @_[$FUN_STUFF_COMPRESSED];
  my $file_regex         = @_[$FUN_STUFF_REGEX];
  my $file_extension     = @_[$FUN_STUFF_EXTENSION];
  my $file_offset        = @_[$FUN_STUFF_OFFSET];

  # Add in placeholders for anything that has an offset greater than 0
  while($file_offset) {
    $file_regex = "__".$file_regex;
    $file_offset -= 1;
  }

  # Add the file type to our hash
  if(exists($fun_stuff{$file_type})) {
    print "Fun Stuff Hash Error: A file type called $file_type already exists, ignoring this\n";
  } else {
    $fun_stuff{$file_type} = {'compression' => $file_is_compressed,
                              'regex'       => $file_regex,
                              'extension'   => $file_extension};
    print "Fun Stuff: Adding $file_type\n" if $very_verbose;
    print "\tCompressed: $file_is_compressed\n" if $very_verbose;
    print "\tREGEX: $file_regex\n" if $very_verbose;
    print "\tExtension: $file_extension\n" if $very_verbose;
  }
}
