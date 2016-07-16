#!/bin/bash

read_bytes(){
	# Read some bytes from the given file using "od" starting at an offset
	# and continuing for some number of bytes.

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

tag_size(){
	# This craziness takes the 7 lowest bits of each byte, shifts it left some
	# number of bits, adds them together, then shifts the whole results right
	# four bits, resulting in a 28 bit number, which is the size of the tag.
	#
	# Why not use all 32 bits of the four bytes you set aside to hold the frame size?
	# Or even the lowest 28 contiguous bits? Ask the clowns who designed this shit.

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

case $( read_bytes "$FILE" 3 1 ) in
	02)
		FNAME_SIZE=3
		FSIZE_SIZE=3
		HSIZE=6
		echo "ID3v2.2"
		;;
	03)
		FNAME_SIZE=4
		FSIZE_SIZE=4
		HSIZE=10
		echo "ID3v2.3"
		;;
	*)
		echo "Unknown ID3v2 tag minor version.  Exiting."
		exit 1
		;;
esac

# Read the size of the tag from the tag header.  This info is located starting
# at byte 6 of the tag, and is 4 bytes long.  See "tag_size()" above for more
# details on this insanity.

TAG_SIZE=$( tag_size $( read_bytes "$FILE" 6 4 ) )

echo "Tag Size: $TAG_SIZE"

# We have all the info we need from the first 10 bytes, so we'll
# fast forward to the first frame's header

POINTER=10

# Read in data until we reach the end of the tag or we reach
# a frame with zero size.  I'm assuming this means we have reached
# the last tag.  Let's hope that I don't make an ASS out of U and ME ^_^

while [ $POINTER -lt $TAG_SIZE ]
do
	# The frame name is the first 3 or 4 bytes at the start of the header,
	# depending on minor version

	FNAME=$( read_bytes "$FILE" $POINTER $FNAME_SIZE | asciify )

	# Immediately after the frame name, you'll find the frame size.  Again,
	# the number of byte that make up the size is determined by the version.

	FSIZE=$( printf "%d" 0x$( read_bytes "$FILE" $(( $POINTER + $FNAME_SIZE )) $FSIZE_SIZE ) )
	
	# If we get to a frame with zero size, we're probably past the end of useful frames

	[ $FSIZE -eq 0 ] && break

	# Now read the frame data in, converting to ascii in the process.  Store in our
	# blatantly incompatible (pre-Bash 4.something) associative array.  DEAL WITH IT.

	FRAME=$( read_bytes "$FILE" $(( $POINTER + $HSIZE )) $FSIZE | asciify )

	echo "$FNAME [$FSIZE]:"
	echo "$FRAME"

	# Each frame is equal to the header size (for the given version) plus the
	# frame data size.  Move our pointer to the start of the next frame header.

	POINTER=$(( $POINTER + $HSIZE + $FSIZE ))
done
