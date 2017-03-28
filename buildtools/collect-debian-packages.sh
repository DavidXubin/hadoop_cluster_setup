#!/bin/bash

PROG=$(basename $0)

usage()
{
    cat << EOF

Script to help move debian packages into target directory

Usage: $PROG <Debian Changelog FilePath> <Target Directory>

Examples:
  * Developer updates the changelog with following command
     $PROG debian/changelog packages/

EOF

    return 0
}

if [ $# -lt 2 ] ; then
    usage
    exit 1
fi

changelogfile=$1
targetdirectory=$2

if [ ! -f "$changelogfile" ] ; then
    echo "Can't find changelog file at '$changelogfile'!"
    exit 1
fi

build_arch=`dpkg --print-architecture`
source_package_name=`dpkg-parsechangelog -l$changelogfile | awk '/^Source:/ { print $2}'`
version=`dpkg-parsechangelog -l$changelogfile | awk '/^Version:/ {print $2}'`
changebase=${source_package_name}_${version}_${build_arch}
changes=../$changebase.changes
buildlog=../$changebase.build
mkdir -p $targetdirectory

for debpkg in `sed -n '/^Files:/,$ { /^Files:/ d ; p ;} ' $changes  | awk '{print $5}'`
do
    mv ../$debpkg $targetdirectory/
done
mv $changes $buildlog $targetdirectory/
