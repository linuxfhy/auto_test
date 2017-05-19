#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

NAME=$(basename $0)
CDIR=$(dirname  $0)
TMPDIR=${TMPDIR:-"/tmp"}
TSROOT=$CDIR/../../

source $TSROOT/lib/libstr.sh
source $TSROOT/lib/libcommon.sh
source $TSROOT/config.vars

IPMITOOL=/usr/bin/ipmitool
IPMITOOL_REAL=/usr/bin/ipmitool.real
IPMITOOL_SHELL=$PWD/tests/en/ipmitool.sh2

tc_start $0
trap "tc_xres \$?" EXIT

function setup
{
	mount -o remount,rw /
	[ ! -f "$IPMITOOL_REAL" ] && cp $IPMITOOL $IPMITOOL_REAL
	[ -f "$IPMITOOL_REAL" ] && ln -sb $IPMITOOL_SHELL $IPMITOOL
	chmod augo+x $IPMITOOL_SHELL
	chmod augo+x $IPMITOOL_REAL
	chmod augo+x $IPMITOOL
	return 0
}

setup || exit $STF_FAIL
exit $STF_PASS
