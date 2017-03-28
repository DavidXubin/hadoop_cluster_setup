#!/bin/bash

FILE=$1
DIST=${2:-any}

NAME=`dpkg-deb -f $FILE Package`
VERSION=`dpkg-deb -f $FILE VERSION`
ARCH=`dpkg-deb -f $FILE Architecture`
MAINTAINER=`dpkg-deb -f $FILE Maintainer`
DESC=`dpkg-deb -f $FILE Description`
SECTION=`dpkg-deb -f $FILE Section`
PRIORITY=`dpkg-deb -f $FILE Priority`
URGENCY=medium

FILENAME=`basename $1`
DATE=`stat -c "%Y" $1 | date -R`
SIZE=`stat -c "%s" $1`
SHA1=`openssl dgst -sha1 $1 | awk '{print $2}'`
SHA256=`openssl dgst -sha256 $1 | awk '{print $2}'`
MD5=`openssl dgst -md5 $1 | awk '{print $2}'`

# in case the deb only provides email w/o the name
if [[ "$MAINTAINER" =~ ^[^\<]+@[^\>]+$ ]]; then
    MAINTAINER="$NAME <$MAINTAINER>"
fi

echo "Format: 1.8"
echo "Date: $DATE"
echo "Source: $NAME"
echo "Binary: $NAME"
echo "Architecture: $ARCH"
echo "Version: $VERSION"
echo "Distribution: $DIST"
echo "Urgency: $URGENCY"
echo "Maintainer: $MAINTAINER"
echo "Description: $DESC"
echo "Changes: "
echo " $NAME ($VERSION) $DIST; urgency=$URGENCY"
echo " ."
echo " * Please refer to the official changelog"
echo "Checksums-Sha1: "
echo " $SHA1 $SIZE $FILENAME"
echo "Checksums-Sha256: "
echo " $SHA256 $SIZE $FILENAME"
echo "Files: "
echo " $MD5 $SIZE $SECTION $PRIORITY $FILENAME"
