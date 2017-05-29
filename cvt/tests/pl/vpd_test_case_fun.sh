#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

valid_cmc_ip=""
eth1ip_of_cmc[2]=0

function log()
{
    echo "[$(date -d today +"%Y-%m-%d %H:%M:%S")]" $* #>>${trcfile}
}

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

function test_case_fun_2_3()
{
    sh write_midplanevpd_use_ecchvpd.sh w_affec
    [[ $? == 0 ]] || exit 1
}

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

function test_case_fun_3_2()
{
    sh write_canistervpd_use_ecchvpd.sh w_affec
    [[ $? -eq 0 ]] || exit 1
}

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

function test_case_fun_4_3()
{
     kill_node -f >null 2>&1
     ifconfig $1 down
     start_compass_and_check
     cmd_rc=$?
     ifconfig $1 up
     return $cmd_rc
}

function test_case_fun_6_1()
{
    kill_node -f >null 2>&1
    mount -o remount,rw /
    sh write_midplanevpd_use_ecchvpd_inject_err.sh $1
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