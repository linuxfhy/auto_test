#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	pl/tc_pl_vpd_case2.sh
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
log ">>>>>>test case 2.1 start:Test mid VPD access while both CMC ok<<<<<<"
ifconfig eth2 up
ifconfig eth3 up
test_case_fun_1_1 write_midplanevpd_use_ecchvpd.sh
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.1 pass<<<<<<"


echo ""
log ">>>>>>test case 2.2 start: Write by CMC0 and read by CMC1<<<<<<"
test_case_fun_2_2 w_0_r_1
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.2 pass<<<<<<"


echo ""
log ">>>>>>test case 2.3 start: Write one mid vpd and check other VPD is changed<<<<<<"
test_case_fun_2_3
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.3 pass<<<<<<"

echo ""
log ">>>>>>test case 2.4 need reset cmc handly, mark pass<<<<<<"

echo ""
log ">>>>>>test case 2.5 start: Change CMC0 to slave and test VPD access<<<<<<"
test_case_fun_2_5
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.5 pass<<<<<<"

echo ""
log ">>>>>>test case 2.6 start: Write, then change CMC0 to slave, then read<<<<<<"
test_case_fun_2_2 w_m_r_s
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.6 pass<<<<<<"

echo ""
log ">>>>>>test case 2.7 start: Simulate CMC0 fail<<<<<<"
test_case_fun_2_7 eth2
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.7 pass<<<<<<"

echo ""
log ">>>>>>test case 2.8 start: Simulate CMC1 fail<<<<<<"
test_case_fun_2_7 eth3
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.8 pass<<<<<<"

log ">>>>>>test case 2.9/2.10 need remove cmc handly, mark as pass<<<<<<"

exit $STF_PASS
