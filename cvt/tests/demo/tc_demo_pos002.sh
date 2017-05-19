#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	demo/tc_demo_pos002
#
# DESCRIPTION:
#	Demo test case pos002
#
# STRATEGY:
#	1. issue "uname -a", expect to pass
#	2. issue "ls /tmp/OopsXXX", expect to fail
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

RUN_POS uname -a || exit $STF_FAIL

RUN_NEU rm -f /tmp/OopsXXX
RUN_NEG ls /tmp/OopsXXX || exit $STF_FAIL

exit $STF_PASS
