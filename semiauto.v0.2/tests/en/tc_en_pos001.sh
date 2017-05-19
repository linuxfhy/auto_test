#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	en/tc_en_pos001
#
# DESCRIPTION:
#	ping remote host then run "uname -a" on it
#
# STRATEGY:
#	01. ping remost host A, expect to pass
#	02. issue "ssh A uname -a", expect to pass
#
# TEST_AUTOMATION_LEVEL: automated
#                     T1 automated
#                     T2 semi-automated
#                     T3 manual
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

RUN_POS ping -w 5 $SSH_RHOST1 || exit $STF_FAIL
RUN_POS $SP1 "uname -a | grep oak" || exit $STF_FAIL

exit $STF_PASS
