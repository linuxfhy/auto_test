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
CDIR=$(dirname  $0)
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

function log()
{
    echo "[$(date -d today +"%Y-%m-%d %H:%M:%S")]" $* #>>${trcfile}
}

function remote_exec()
{
    ssh -p 26 ${remote_ip} "$*"
    return $?
}

if [[ ! -f ${trcfile} ]]
then
    touch ${trcfile}
else
    typeset -i SZ
    SZ=$(${LSCMD} -s ${trcfile} | ${AWKCMD} -F " " '{print $1}')
    SZ=${SZ}*1024
    if [[ $SZ -gt 163840 ]]
    then
        tail --bytes=163840 ${trcfile} >/tmp/$$ 2>/dev/null
        mv -f /tmp/$$ ${trcfile} 2>/dev/null
    fi
fi


tc_start $0
trap "tc_xres \$?" EXIT

#test case 1.1
function test_case_fun_1_1 ()
{
    total_step_case_1_1=2
    cur_step=1

    log "STEP ${cur_step} of ${total_step_case_1_1}:exec $1"
    cur_step=$((${cur_step}+1))
    sh $1

    if [[ $? != 0 ]];then
    {
        log "exec $1 fail on ${cur_node} node,cmd_rc is $?"
        exit 1
    }
    fi
    log "STEP ${cur_step} of ${total_step_case_1_1}:write and read check pass,write done"
    return 0
}

log ">>>>>>kill node before start<<<<<<"
kill_node -f >null 2>&1

echo ""
log ">>>>>>test case 1.1 start:write mid vpd use ipmi<<<<<<"
test_case_fun_1_1 write_midplanevpd_optimized_anyCPUcnt.sh
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 1.1 pass<<<<<<"

echo ""
log ">>>>>>test case 1.2 start:write mid vpd use ec_chvpd<<<<<<"
test_case_fun_1_1 write_midplanevpd_use_ecchvpd.sh
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 1.2 pass<<<<<<"

echo ""
log ">>>>>>test case 1.3 start:write can vpd use ipmi<<<<<<"
test_case_fun_1_1 write_canistervpd_optimized.sh
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 1.3 pass<<<<<<"

echo ""
log ">>>>>>test case 1.4 start:write can vpd use ec_chvpd<<<<<<"
test_case_fun_1_1 write_canistervpd_use_ecchvpd.sh
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 1.4 pass<<<<<<"

echo ""
log ">>>>>>test case 2.1 start:Test mid VPD access while both CMC ok<<<<<<"
ifconfig eth2 up
ifconfig eth3 up
test_case_fun_1_1 write_midplanevpd_use_ecchvpd.sh
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.1 pass<<<<<<"

echo ""
log ">>>>>>test case 2.2 start: Write by CMC0 and read by CMC1<<<<<<"
timeout -k1 2 ipmitool -H 192.168.200.42 -U admin -P admin raw 0x30 0x22 0x01
[[ $? -eq 0 ]] || exit $STF_FAIL
sh write_midplanevpd_use_ecchvpd.sh w_0_r_1
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.2 pass<<<<<<"

function test_case_fun_2_3()
{
    sh write_midplanevpd_use_ecchvpd.sh w_affec
    [[ $? -eq 0 ]] || exit 1
}
echo ""
log ">>>>>>test case 2.3 start: Write one mid vpd and check other VPD is changed<<<<<<"
test_case_fun_2_3
[ $? -eq 0 ] || exit $STF_FAIL
log ">>>>>>test case 2.3 pass<<<<<<"

echo ""
log ">>>>>>test case 2.4 need reset cmc handly, mark as pass<<<<<<"


exit $STF_PASS
