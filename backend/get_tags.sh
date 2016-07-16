#!/bin/bash

# Usage: get_tags.sh [FILENAME]
#
# This script reads id3v2 tags from mp3 files, and prints the results to your console.
# 

read_bytes(){
	# Read some bytes from the given file using "od" starting at an offset
	# and continuing for some number of bytes.  Why use "od" instead of "hd"
	# or "xxd"?  Because (no shit) I want this to be able to run on IRIX.

	FILENAME=$1
	OFFSET=$2
	LENGTH=$3

	od -An -v -t x1 -j $OFFSET -N $LENGTH "$FILENAME" | sed -e 's/ //g' | tr --delete "\n"
}

asciify(){ 
	# Read a byte at a time on stdin and print it out doing \xHH -> C

	while read -n 2 CHAR
	do
		printf "\x${CHAR}"
	done
}

unsync_size(){
	# This craziness takes the 7 lowest bits of each byte, shifts it left
	# some number of bits, adds them together, then shifts the whole results
	# right four bits, resulting in a 28 bit number, which is the size of
	# the tag. It seems like this is necessary to distinguish this data from
	# syncrhonization data later in the file.
	#
	# Ultimately, what we're doing looks like this:
        # 0AAAAAAA0BBBBBBB0CCCCCCC0DDDDDDD->AAAAAAABBBBBBBCCCCCCCDDDDDDD0000->
        # 0000AAAAAAABBBBBBBCCCCCCCDDDDDDD->Decimal
        HEX=$1

        printf "%d" $(( ( ( ( 0x${HEX:0:2} & 0x7f) << 25 ) + ( ( 0x${HEX:2:2} & 0x7f ) << 18 ) + ( ( 0x${HEX:4:2} & 0x7f ) << 11 ) + ( ( 0x${HEX:6:2} & 0x7f ) << 4 ) ) >> 4 ))
}

FILE=$1

# Set some critical parameters based on tag version
# FNAME_SIZE = size of the frame name, in bytes
# FSIZE_SIZE = size of the frame size, in bytes
# HSIZE = size of the header.  Sadly, not just FNAME_SIZE+FSIZE_SIZE.  ID3v2.3
# includes two extra bytes for flags that are missing in ID3v2.2
# Also, we'll set the format of our sqlite query here, since the tag
# names are the keys for our associative array, and tag names are 3 or 4
# characters, depending on version.

VERSION=$( read_bytes "$FILE" 3 1 )

case $VERSION in
	02)
		FNAME_SIZE=3
		FSIZE_SIZE=3
		HSIZE=6
		;;
	03|04)
		FNAME_SIZE=4
		FSIZE_SIZE=4
		HSIZE=10
		;;
	*)
		echo "Unknown ID3v2 tag minor version.  Exiting."
		exit 1
		;;
esac

# Read the size of the tag from the tag header.  This info is located starting
# at byte 6 of the tag, and is 4 bytes long.  See "unsync_size" above for more
# details on this insanity.

TAG_SIZE=$( unsync_size $( read_bytes "$FILE" 6 4 ) )

# We have all the info we need from the first 10 bytes, so we'll
# fast forward to the first frame's header

POINTER=10

# Read in data until we reach the end of the tag or we reach
# a frame with zero size.  I'm assuming this means we have reached
# the last tag.  Let's hope that I don't make an ASS out of U and ME ^_^

while [ $POINTER -lt $TAG_SIZE ]
do
	# Get our frame size first.  Version 4 stores the size of the frames the same
	# way that all the tags store the overall tag size.  Versions .2 and .3 just
	# store the frame sizes as 24 and 32 bit integers, respectively.
        if [ $VERSION = "04" ]
        then
                FSIZE=$( unsync_size $( read_bytes "$FILE" $(( $POINTER + $FNAME_SIZE )) $FSIZE_SIZE ) )
        else
                FSIZE=$( printf "%d" 0x$( read_bytes "$FILE" $(( $POINTER + $FNAME_SIZE )) $FSIZE_SIZE ) )
        fi

	# If we hit a frame with zero size, then we'll assume that we've reached
	# the end of the useful frames.  Let's hope we don't make an ASS out of U
	# and ME.
	[ $FSIZE -eq 0 ] && break

	# The frame name is the first 3 or 4 bytes at the start of the header,
	# depending on minor version

	FNAME=$( read_bytes "$FILE" $POINTER $FNAME_SIZE | asciify )

	# Now read the frame data in, converting to ascii in the process.  Store in our
	# blatantly incompatible (pre-Bash 4.something) associative array.  DEAL WITH IT.

	FRAME=$( read_bytes "$FILE" $(( $POINTER + $HSIZE )) $FSIZE | asciify )

	echo "$FNAME: $FRAME"

	# Each frame is equal to the header size (for the given version) plus the
	# frame data size.  Move our pointer to the start of the next frame header.

	POINTER=$(( $POINTER + $HSIZE + $FSIZE ))
done
