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

valid_cmc_ip=""
eth1ip_of_cmc[2]=0

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

function get_valid_cmc_ip()
{
    ip=$(ipmitool raw 0x30 0x14)
    array=($ip)
    i=0
    ipaddr[2]=0

    for((i=0;i<2;i++))
    do
        ipaddr[$i]="$((16#${array[4+$((8*$i))]})).$((16#${array[5+$((8*$i))]})).$((16#${array[6+$((8*$i))]})).$((16#${array[7+$((8*$i))]}))"
        #log "cmc${i}_eth1_ip:"${ipaddr[$i]}
        readcmd="timeout -k1 2 ipmitool -H ${ipaddr[$i]} -U admin -P admin raw 0x30 0x23"
        readresult=$(${readcmd})

        if [ $? != 0 ]; then
            log "check cmc${i} is master fail,cmd_rc:$?(124:timeout,127:cmd not exist)"
            continue
        fi

        #log "cmc${i} is:"${readresult}"(1:master,0:slave)"
        valid_cmc_ip=${ipaddr[$i]}
        eth1ip_of_cmc[$i]=${ipaddr[$i]}
        return 0
    done

    log "can't get master cmc ip"
    return 1
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
function test_case_fun_1_1()
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
log ">>>>>>test case 1.4 start:write can vpd use ec_chvpd<<<<<<"
test_case_fun_1_1 write_canistervpd_use_ecchvpd.sh
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 1.4 pass<<<<<<"

echo ""
log ">>>>>>test case 2.1 start:Test mid VPD access while both CMC ok<<<<<<"
ifconfig eth2 up
ifconfig eth3 up
test_case_fun_1_1 write_midplanevpd_use_ecchvpd.sh
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.1 pass<<<<<<"

function test_case_fun_2_2()
{
    get_valid_cmc_ip
    if [[ $? != 0 ]]; then
        log "get master cmc ip fail,cmd_rc is $?"
        exit 1
    fi
    timeout -k1 2 ipmitool -H ${eth1ip_of_cmc[0]} -U admin -P admin raw 0x30 0x22 0x01
    if [[ $? != 0 ]]; then
        log "set cmc0 master fail,cmd_rc is $?"
        exit 1
    fi
    sh write_midplanevpd_use_ecchvpd.sh w_0_r_1
    if [[ $? != 0 ]]; then
        log " Write by CMC0 and read by CMC1"
        exit 1
    fi
}

echo ""
log ">>>>>>test case 2.2 start: Write by CMC0 and read by CMC1<<<<<<"
test_case_fun_2_3
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.2 pass<<<<<<"

function test_case_fun_2_3()
{
    sh write_midplanevpd_use_ecchvpd.sh w_affec
    [[ $? == 0 ]] || exit 1
}
echo ""
log ">>>>>>test case 2.3 start: Write one mid vpd and check other VPD is changed<<<<<<"
test_case_fun_2_3
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.3 pass<<<<<<"

echo ""
log ">>>>>>test case 2.4 need reset cmc handly, mark pass<<<<<<"

function test_case_2_5()
{
    get_valid_cmc_ip
    timeout -k1 2 ipmitool -H ${eth1ip_of_cmc[0]} -U admin -P admin raw 0x30 0x22 0x00
    if [[ $? != 0 ]]; then
        log "set cmc0 slave fail,cmd_rc is $?"
        exit 1
    fi
    test_case_fun_1_1 write_midplanevpd_use_ecchvpd.sh
    if [[ $? != 0 ]]; then
        log "access mid vpd fail when cmc is slave,cmd_rc is $?"
        exit 1
    fi
    timeout -k1 2 ipmitool -H ${eth1ip_of_cmc[0]} -U admin -P admin raw 0x30 0x22 0x01
    if [[ $? != 0 ]]; then
        log "set cmc0 master fail,cmd_rc is $?"
        exit 1
    fi
}

echo ""
log ">>>>>>test case 2.5 start: Change CMC0 to slave and test VPD access<<<<<<"
test_case_fun_2_5
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.5 pass<<<<<<"



exit $STF_PASS
