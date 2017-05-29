#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	pl/tc_pl_vpd_case6.sh
#
# DESCRIPTION:
#	Test cases for VPD-access
#
# __stc_assertion_end
#
################################################################################

NAME=$(basename $0)
CDIR="$( cd "$( dirname "$0"  )" && pwd  )"
TMPDIR=${TMPDIR:-"/tmp"}
TSROOT=$CDIR/../../

AWKCMD=awk
LSCMD=ls
trcfile="/dumps/scrumtest.trc"

source $TSROOT/lib/libstr.sh
source $TSROOT/lib/libcommon.sh
source $TSROOT/config.vars

S_SAINFO=/compass/bin/sainfo
S_SATASK=/compass/bin/satask
S_SVCTASK=/compass/bin/svctask
S_EC_CHVPD=/compass/ec_chvpd

export PATH=$PATH:$CDIR
echo "PATH in tc_pl_vpd_pos0001.sh is $PATH"

source $CDIR/vpd_test_case_fun.sh

tc_start $0
trap "tc_xres \$?" EXIT


log ">>>>>>kill node before start<<<<<<"
kill_node -f >null 2>&1

log ">>>>>>test case 6.1 start: Inject timeout error once for each command<<<<<<"
test_case_fun_6_1 timeout
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 6.1 pass <<<<<<"

log ">>>>>>test case 6.2 start: Inject result-short error once for each command<<<<<<"
test_case_fun_6_1 short
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 6.2 pass <<<<<<"

exit $STF_PASS
