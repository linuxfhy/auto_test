#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	demo/tc_demo_pos001
#
# DESCRIPTION:
#	Demo test case pos001
#
# STRATEGY:
#	1. issue "ls -l /tmp", expect to pass
#	2. issue "uname -a | grep oak", expect to pass
#
# __stc_assertion_end
#
################################################################################

NAME=$(basename $0)
CDIR=$(dirname  $0)
TMPDIR=${TMPDIR:-"/tmp"}
TSROOT=$CDIR/../../

source $TSROOT/lib/libstr.sh
source $TSROOT/lib/libcommon.sh
source $TSROOT/config.vars

tc_start $0
trap "tc_xres \$?" EXIT

RUN_POS ls -l /tmp || exit $STF_FAIL

RUN_POS "uname -a | grep oak"
if (( $? != 0 )); then
	RUN_RAW uname -a
	exit $STF_FAIL
fi

exit $STF_PASS
