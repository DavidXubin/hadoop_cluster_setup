#!/bin/bash

TARGET=${1:-"all"}
export BUILD=${BUILD_NUMBER:-0}

export BASE_DIR=`pwd`
BIN_DIR=$BASE_DIR/buildtools

export PATH=$PATH:$BIN_DIR

require()
{
    missing_files=""
    until [ $# -eq 0 ];do
        which $1 > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            missing_files+=" jenkins/bin/$1"
            echo "[INFO] Missing $1, downloading..."
        fi
        shift
    done
    if [ "$missing_files" == "" ]; then
        return 0
    fi

    # retrieve scripts from rdinternal.git
    git archive --format=tar --remote=gerrit.mozy.lab.emc.com:rdinternal.git master $missing_files \
        | tar xf - --strip-components 2 -C $BIN_DIR
    if [ $? -ne 0 ]; then
        echo "[ERROR] Downloading failed!" && exit 1
    fi
}

build_deb()
{
    if [ ! -d "$1/debian/" ]; then
        echo "[INFO] Not found debian folder, skip debuild!" && return
    fi

    # update changelog
    # FIXME: APPMON-60
    changelog=$1/debian/changelog
    git-changelog.sh --auto -n $BUILD -p $BASE_DIR/$1/ $changelog
    sed -i '/\s*\[.*\]$/d' $changelog
    echo "[INFO] $changelog updated"

    # build
    debuild -e BUILD_NUMBER=$BUILD -us -uc -b
    if [ $? -ne 0 ] ; then
        echo "[ERROR] Build $1 failed!" && exit 1
    fi
    debuild clean

    # collect artifacts
    collect-debian-packages.sh $changelog $2
}

package()
{
    export WORKING_DIR=$BASE_DIR/$1/
    if [ ! -d "$WORKING_DIR" ];then
        echo "[ERROR] Unknown target $1!" 1>&2
        exit 1
    fi
    cd $WORKING_DIR

    echo "[INFO] Build $1 started..."

    # prepare
    export PKG_DIR=$BASE_DIR/packages/$1/
    rm -rf $PKG_DIR
    mkdir -p $PKG_DIR

    pre_script=$WORKING_DIR/pre_package.sh
    [ -x "$pre_script" ] && $pre_script

    build_deb $WORKING_DIR $PKG_DIR

    echo "[INFO] Build $1 successfully!"
    cd $BASE_DIR
}

require git-changelog.sh collect-debian-packages.sh

if [ "$TARGET" != "all" ]; then
    package $TARGET
else
    package "monitor-cluster"
fi

exit 0
