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
	echo "This is a dummy cleanup"
	return 0
}

cleanup || exit $STF_FAIL
exit $STF_PASS
