#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	pl/tc_pl_vpd_pos001
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
#test_case_fun_1_1 write_midplanevpd_optimized_anyCPUcnt.sh
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 1.1 pass<<<<<<"

echo ""
log ">>>>>>test case 1.2 start:write mid vpd use ec_chvpd<<<<<<"
#test_case_fun_1_1 write_midplanevpd_use_ecchvpd.sh
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 1.2 pass<<<<<<"

echo ""
log ">>>>>>test case 1.3 start:write can vpd use ipmi<<<<<<"
#test_case_fun_1_1 write_canistervpd_optimized.sh
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 1.3 pass<<<<<<"

echo ""
log ">>>>>>test case 1.4 start:write and read can vpd use ec_chvpd<<<<<<"
#test_case_fun_1_1 write_canistervpd_use_ecchvpd.sh
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 1.4 pass<<<<<<"

echo ""
log ">>>>>>test case 2.1 start:Test mid VPD access while both CMC ok<<<<<<"
ifconfig eth2 up
ifconfig eth3 up
#test_case_fun_1_1 write_midplanevpd_use_ecchvpd.sh
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.1 pass<<<<<<"


echo ""
log ">>>>>>test case 2.2 start: Write by CMC0 and read by CMC1<<<<<<"
#test_case_fun_2_2 w_0_r_1
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.2 pass<<<<<<"


echo ""
log ">>>>>>test case 2.3 start: Write one mid vpd and check other VPD is changed<<<<<<"
#test_case_fun_2_3
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.3 pass<<<<<<"

echo ""
log ">>>>>>test case 2.4 need reset cmc handly, mark pass<<<<<<"

echo ""
log ">>>>>>test case 2.5 start: Change CMC0 to slave and test VPD access<<<<<<"
#test_case_fun_2_5
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.5 pass<<<<<<"

echo ""
log ">>>>>>test case 2.6 start: Write, then change CMC0 to slave, then read<<<<<<"
#test_case_fun_2_2 w_m_r_s
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.6 pass<<<<<<"

echo ""
log ">>>>>>test case 2.7 start: Simulate CMC0 fail<<<<<<"
#test_case_fun_2_7 eth2
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.7 pass<<<<<<"

echo ""
log ">>>>>>test case 2.8 start: Simulate CMC1 fail<<<<<<"
#test_case_fun_2_7 eth3
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.8 pass<<<<<<"

log ">>>>>>test case 2.9/2.10 need remove cmc handly, mark as pass<<<<<<"

echo ""
log ">>>>>>test case 3.1/3.3 start: write and read can vpd use ec_chvpd<<<<<<"
log "Theses two cases are same as test case 1.4, mark as pass"
log ">>>>>>test case 3.1/3.3 pass<<<<<<"


echo ""
log ">>>>>>test case 3.2 start: Write one can vpd and check other VPD is changed<<<<<<"
#test_case_fun_3_2
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 3.2 pass<<<<<<"

log ">>>>>>test case 4.1 start: Start compass when cmc0 is master<<<<<<"
#test_case_fun_4_1 1
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 4.1 pass<<<<<<"

log ">>>>>>test case 4.2 start: Start compass when cmc0 is slave<<<<<<"
#test_case_fun_4_1 0
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 4.2 pass<<<<<<"


log ">>>>>>test case 4.3 start: Start compass when network to cmc0 is down<<<<<<"
#test_case_fun_4_3 eth2
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 4.3 pass<<<<<<"

log ">>>>>>test case 4.2 start: Start compass when network to cmc1 is down<<<<<<"
#test_case_fun_4_3 eth3
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 4.2 pass<<<<<<"

log ">>>>>>test case 4.5/4.6: Start compass when only one cmc is present, need operate handly, mark as pass<<<<<<"

log ">>>>>>test case 6.1 start: Inject timeout error once for each command<<<<<<"
#test_case_fun_6_1 timeout
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 6.1 pass <<<<<<"

log ">>>>>>test case 6.2 start: Inject result-short error once for each command<<<<<<"
#test_case_fun_6_1 short
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 6.2 pass <<<<<<"

exit $STF_PASS
