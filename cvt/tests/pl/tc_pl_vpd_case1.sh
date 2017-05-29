#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	pl/tc_pl_vpd_case1.sh
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

echo ""
log ">>>>>>test case 1.1 start:write mid vpd use ipmi<<<<<<"
test_case_fun_1_1 write_midplanevpd_optimized_anyCPUcnt.sh
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 1.1 pass<<<<<<"

echo ""
log ">>>>>>test case 1.2 start:write mid vpd use ec_chvpd<<<<<<"
test_case_fun_1_1 write_midplanevpd_use_ecchvpd.sh
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 1.2 pass<<<<<<"

echo ""
log ">>>>>>test case 1.3 start:write can vpd use ipmi<<<<<<"
test_case_fun_1_1 write_canistervpd_optimized.sh
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 1.3 pass<<<<<<"

echo ""
log ">>>>>>test case 1.4 start:write and read can vpd use ec_chvpd<<<<<<"
test_case_fun_1_1 write_canistervpd_use_ecchvpd.sh
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 1.4 pass<<<<<<"

exit $STF_PASS
