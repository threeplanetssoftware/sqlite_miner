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
$FUN_STUFF_REGEX      = 3;

# Hash of things to look for
%fun_stuff;

# Compressed formats that we may want to decompress
add_fun_thing_to_hash('7ZIP',     0, '7z',   '377abcaf271c%');
add_fun_thing_to_hash('BZIP',     1, 'bz2',  '425a68%');
add_fun_thing_to_hash('GZIP',     1, 'gz',   '1f8b%');
add_fun_thing_to_hash('LZ4',      1, 'lz4',  '04224d18%');
add_fun_thing_to_hash('RAR',      0, 'rar',  '526172211a0700%');
add_fun_thing_to_hash('RAR_5.0',  0, 'rar',  '526172211a070100%');
add_fun_thing_to_hash('ZIP',      1, 'zip',  '504b0304%');
add_fun_thing_to_hash('ZIP_EMPTY',1, 'zip',  '504b0506%');
add_fun_thing_to_hash('ZIP_SPAN', 1, 'zip',  '504b0708%');
add_fun_thing_to_hash('ZLIB_LOW', 1, 'zlib', '7801%');
add_fun_thing_to_hash('ZLIB',     1, 'zlib', '789c%');
add_fun_thing_to_hash('ZLIB_MAX', 1, 'zlib', '78da%');

# Possible property files
add_fun_thing_to_hash('BPLIST', 0, 'bplist', '62706c697374%');
add_fun_thing_to_hash('XML',    0, 'xml',    '3c3f786d6c20%');

# Images
add_fun_thing_to_hash('BMP',      0, 'bmp', '424d%');
add_fun_thing_to_hash('JPEG_RAW', 0, 'jpg', 'ffd8ffdb%');
add_fun_thing_to_hash('JPEG_JFIF',0, 'jpg', 'ffd8ffe0____4a4649460001%');
add_fun_thing_to_hash('JPEG_EXIF',0, 'jpg', 'ffd8ffe1____457869660000%');
add_fun_thing_to_hash('GIF',      0, 'gif', '474946383_61%');
add_fun_thing_to_hash('PNG',      0, 'png', '89504e470d0a1a0a%');
add_fun_thing_to_hash('WEBP',     0, 'webp','52494646________57454250%');

# Media
add_fun_thing_to_hash('MP3',    0, 'mp3',  'fffb%');
add_fun_thing_to_hash('MP3_ID3',0, 'mp3',  '494433%');
add_fun_thing_to_hash('OGG',    0, 'ogg',  '4f676753%');
add_fun_thing_to_hash('WAV',    0, 'wav',  '52494646________57415645%');
add_fun_thing_to_hash('FLAC',   0, 'flac', '664c6143%');

# Documents
add_fun_thing_to_hash('PDF',   0, 'pdf',  '25504446%');
add_fun_thing_to_hash('RTF',   0, 'rtf',  '7b5c72746631%');
add_fun_thing_to_hash('iNote', 0, 'note', '080012%');

# Executables
add_fun_thing_to_hash('DALVIK_EXECUTABLE', 0, 'dex', '6465780a30333500%');

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
  $file_type          = @_[$FUN_STUFF_FILE_TYPE];
  $file_is_compressed = @_[$FUN_STUFF_COMPRESSED];
  $file_regex         = @_[$FUN_STUFF_REGEX];
  $file_extension     = @_[$FUN_STUFF_EXTENSION];

  if(exists($fun_stuff{$file_type})) {
    print "Fun Stuff Hash Error: A file type called $file_type already exists, ignoring this\n";
  } else {
    $fun_stuff{$file_type} = {'compression' => $file_is_compressed,
                              'regex'       => $file_regex,
                              'extension'   => $file_extension};
    if($verbose) {
      print "Fun Stuff: Adding $file_type\n";
      print "\tCompressed: $file_is_compressed\n";
      print "\tREGEX: $file_regex\n";
      print "\tExtension: $file_extension\n";
    }
  }
}
