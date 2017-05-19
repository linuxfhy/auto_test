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

tc_start $0
trap "tc_xres \$?" EXIT

function cleanup
{
	mount -o remount,rw /
	[ -f "$IPMITOOL_REAL" ] && rm -fr $IPMITOOL
	[ -f "$IPMITOOL_REAL" ] && cp -a $IPMITOOL_REAL $IPMITOOL
	return 0
}

cleanup || exit $STF_FAIL
exit $STF_PASS
