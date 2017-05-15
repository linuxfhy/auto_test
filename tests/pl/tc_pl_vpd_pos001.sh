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
    sh write_midplanevpd_use_ecchvpd.sh $1
    if [[ $? != 0 ]]; then
        log " Write by CMC0 and read by CMC1"
        exit 1
    fi
}

echo ""
log ">>>>>>test case 2.2 start: Write by CMC0 and read by CMC1<<<<<<"
#test_case_fun_2_2 w_0_r_1
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.2 pass<<<<<<"

function test_case_fun_2_3()
{
    sh write_midplanevpd_use_ecchvpd.sh w_affec
    [[ $? == 0 ]] || exit 1
}
echo ""
log ">>>>>>test case 2.3 start: Write one mid vpd and check other VPD is changed<<<<<<"
#test_case_fun_2_3
[[ $? == 0 ]] || exit $STF_FAIL
log ">>>>>>test case 2.3 pass<<<<<<"

echo ""
log ">>>>>>test case 2.4 need reset cmc handly, mark pass<<<<<<"

function test_case_fun_2_5()
{
    get_valid_cmc_ip
    timeout -k1 2 ipmitool -H ${eth1ip_of_cmc[0]} -U admin -P admin raw 0x30 0x22 0x00 >null
    if [[ $? != 0 ]]; then
        log "set cmc0 slave fail,cmd_rc is $?"
        exit 1
    fi
    test_case_fun_1_1 write_midplanevpd_use_ecchvpd.sh
    if [[ $? != 0 ]]; then
        log "access mid vpd fail when cmc is slave,cmd_rc is $?"
        exit 1
    fi
    timeout -k1 2 ipmitool -H ${eth1ip_of_cmc[0]} -U admin -P admin raw 0x30 0x22 0x01  >null
    if [[ $? != 0 ]]; then
        log "set cmc0 master fail,cmd_rc is $?"
        exit 1
    fi
}

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

function test_case_fun_2_7()
{
    total_step_case_1_1=3
    cur_step=1

    #log "STEP ${cur_step} of ${total_step_case_1_1}:close network to cmc0"
    cur_step=$((${cur_step}+1))
    ifconfig $1 down

    #log "STEP ${cur_step} of ${total_step_case_1_1}:access vpd"
    cur_step=$((${cur_step}+1))
    test_case_fun_1_1 write_midplanevpd_use_ecchvpd.sh
    if [[ $? != 0 ]];then
    {
        log "access vpd fail"
        ifconfig $1 up
        exit 1
    }
    fi

    #log "STEP ${cur_step} of ${total_step_case_1_1}:recover test config,open $1"
    ifconfig $1 up
    return 0
}

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

function test_case_fun_3_2()
{
    sh write_canistervpd_use_ecchvpd.sh w_affec
    [[ $? -eq 0 ]] || exit 1
}
echo ""
log ">>>>>>test case 3.2 start: Write one can vpd and check other VPD is changed<<<<<<"
#test_case_fun_3_2
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 3.2 pass<<<<<<"

function start_compass_and_check()
{
    start_ok=0
    compass_start
    for((i=0;i<60;i++))
    do
        sainfo lsservicenodes | grep $(/compass/ec_getend | cut -d: -f7) | grep Candidate
        if [[ $? != 0 ]]; then
            #log "compass_start hasn't complete,loop $i"
            sleep 2
            continue
        fi
        start_ok=1
        break
    done
    if [[ ${start_ok} != 1 ]]; then
        log "compass_start fail"
        exit 1
    fi
    return 0
}

function test_case_fun_4_1()
{
     kill_node -f  >null 2>&1
     get_valid_cmc_ip
     timeout -k1 2 ipmitool -H ${eth1ip_of_cmc[0]} -U admin -P admin raw 0x30 0x22 0x0$1
     start_compass_and_check
     cmd_rc=$?
     timeout -k1 2 ipmitool -H ${eth1ip_of_cmc[0]} -U admin -P admin raw 0x30 0x22 0x01
     return $cmd_rc
}
log ">>>>>>test case 4.1 start: Start compass when cmc0 is master<<<<<<"
#test_case_fun_4_1 1
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 4.1 pass<<<<<<"

log ">>>>>>test case 4.2 start: Start compass when cmc0 is slave<<<<<<"
#test_case_fun_4_1 0
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 4.2 pass<<<<<<"

function test_case_fun_4_3()
{
     kill_node -f >null 2>&1
     ifconfig $1 down
     start_compass_and_check
     cmd_rc=$?
     ifconfig $1 up
     return $cmd_rc
}
log ">>>>>>test case 4.3 start: Start compass when network to cmc0 is down<<<<<<"
#test_case_fun_4_3 eth2
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 4.3 pass<<<<<<"

log ">>>>>>test case 4.2 start: Start compass when network to cmc1 is down<<<<<<"
#test_case_fun_4_3 eth3
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 4.2 pass<<<<<<"

log ">>>>>>test case 4.5/4.6: Start compass when only one cmc is present, need operate handly, mark as pass<<<<<<"

function test_case_fun_6_1()
{
    kill_node -f >null 2>&1
    mount -o remount,rw /
    sh write_midplanevpd_use_ecchvpd_inject_err.sh $1
}
log ">>>>>>test case 6.1 start: Inject timeout error once for each command<<<<<<"
test_case_fun_6_1 timeout
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 6.1 pass <<<<<<"

log ">>>>>>test case 6.2 start: Inject result-short error once for each command<<<<<<"
test_case_fun_6_1 short
[[ $? -eq 0 ]] || exit $STF_FAIL
log ">>>>>>test case 6.2 pass <<<<<<"

exit $STF_PASS
