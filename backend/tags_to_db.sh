#!/bin/bash

read_bytes(){
	FILENAME=$1
	OFFSET=$2
	LENGTH=$3

	od -An -v -t x1 -j $OFFSET -N $LENGTH "$FILENAME" | sed -e 's/ //g' | tr --delete "\n"
}

asciify(){ 
	while read -n 2 CHAR
	do
		printf "\x${CHAR}"
	done
}

unsync_size(){
	# 0AAAAAAA0BBBBBBB0CCCCCCC0DDDDDDD->AAAAAAABBBBBBBCCCCCCCDDDDDDD0000->
	# 0000AAAAAAABBBBBBBCCCCCCCDDDDDDD->Decimal
	HEX=$1

	printf "%d" $(( ( ( ( 0x${HEX:0:2} & 0x7f) << 25 ) + ( ( 0x${HEX:2:2} & 0x7f ) << 18 ) + ( ( 0x${HEX:4:2} & 0x7f ) << 11 ) + ( ( 0x${HEX:6:2} & 0x7f ) << 4 ) ) >> 4 ))
}

while read FILE
do

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
		echo -en "Unknown ID3v2 tag minor version for file: $FILE\n" >> log.txt
		continue
		;;
esac

TAG_SIZE=$( unsync_size $( read_bytes "$FILE" 6 4 ) )

POINTER=10

while [ $POINTER -lt $TAG_SIZE ]
do
	if [ $VERSION = "04" ]
	then
		FSIZE=$( unsync_size $( read_bytes "$FILE" $(( $POINTER + $FNAME_SIZE )) $FSIZE_SIZE ) )
	else
		FSIZE=$( printf "%d" 0x$( read_bytes "$FILE" $(( $POINTER + $FNAME_SIZE )) $FSIZE_SIZE ) )
	fi

	[ $FSIZE -eq 0 ] && break
		
	FRAME=$( read_bytes "$FILE" $(( $POINTER + $HSIZE )) $FSIZE | asciify )

	case $( read_bytes "$FILE" $POINTER $FNAME_SIZE | asciify ) in
		TPE1|TP1)
			ARTIST=$FRAME
			;;
		TALB|TAL)
			ALBUM=$FRAME
			;;
		TIT2|TT2)
			TITLE=$FRAME
			;;
		TRCK|TRK)
			TRACK=$FRAME
			;;
		TYER|TYE|TDRC)
			YEAR=$FRAME
			;;
	esac

	POINTER=$(( $POINTER + $HSIZE + $FSIZE ))
done

echo "sqlite jukebox.db \"INSERT into songs values( '$ARTIST' , '$ALBUM' , '$TITLE' , '$TRACK' , '$YEAR' , '$FILE' );\"" >> jukebox.sql

done
