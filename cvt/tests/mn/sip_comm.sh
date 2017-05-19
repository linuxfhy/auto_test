#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

NAME=$(basename $0)
CDIR=$(dirname  $0)
TSROOT=$CDIR/../../

source $TSROOT/lib/libstr.sh
source $TSROOT/lib/libcommon.sh
source $CDIR/mn_comm.sh

#
#node id 
#
function getnodeid
{
    local cmd=0x40
    local slotid=$(exec_cmd_bmc $cmd)
    if (( $? != 0 )); then
        log_oak "get node id failed"
        return 1
    fi
    echo $(( $slotid + 1 ))
}

#
#get service ip from midplane 
#
function get_serviceip_midplane
{
    local nodeid cmd result serviceip cmcip
    local sip_hex
    local arr
    nodeid=$(getnodeid)
    (( $? != 0)) && return 1
    if (($nodeid == 1)); then
        cmd="0x04 0x2F 0xE8"
    elif (($nodeid == 2)); then
        cmd="0x04 0x30 0x28"
    else
        log_oak "invalid node id"
        return 1
    fi
    cmcip=$(get_cmc_ip)
    (($? != 0)) && {
        log_oak "cmc ip get failed"
        return 1
    }
    result=$(exec_cmd_midplane $cmcip $cmd)
    (($? != 0)) && {
        log_oak "get serviceip failed"
        return 1
    }
    arr=($result)
    sip_hex="0x${arr[0]} 0x${arr[1]} 0x${arr[2]} 0x${arr[3]}"
    serviceip=$(printf "%d.%d.%d.%d" $sip_hex)
    echo $serviceip
}

#
# get service ip from interface
#
function get_serviceip_local
{
    local info sip dev
    local devarry=("eth0:10" "eth1:10")
    local cmcindex
    cmcind=$(get_active_cmc)
    (($? != 0)) && {
        log_oak "no active cmc found"
        return 1
    }
    dev=${devarry[cmcind]} 
    info=$(ifconfig $dev | grep -w inet)
    [[ $? != 0 || -z "$info" ]] && {
        log_oak "no service ip found on dev ${dev}"
        return 1
    }
    sip=$(echo $info | awk '{print $2}')
    [[ $? != 0 || -z "$sip" ]] && {
        log_oak "parse service ip failed"
        return 1
    }
    echo $sip
    return 0
}

#
# get the default service ip from file
# the service ip is generated according to the netcfg and node location
#
function get_serviceip_default
{
    local flname=/data/default_ipv4
    [[ -f $flname ]] || {
        log_oak "no default ip file found"
        return 1
    }
    local sip
    sip=$(cat $flname | awk '{print $1}')
    (($? != 0)) && {
        log_oak "parse default service ip failed"
        return 1
    }
    echo $sip
    return 0
}

#
# check the mcs is running
#
function is_running_mcs
{
    local count
    local is_run=0
    if [[ -n $( ps --no-heading -C ecmain ) ]]
    then
        is_run=1
    fi
    echo $is_run
    return 0
}

#
# get active cmc index in the enclosure,
# 0: cmc0
# 1: cmc1
#
function getActiveCMC
{
    local cmd result index
    for index in {0,1}
    do
        result=$(mnet show cmcmode cmc ${index})
        if [[ $? == 0 && ${result} == "Active" ]];then
            echo $index
            return
        fi
    done
    ((index++))
    echo $index
    return 0
}

#
# according to the cmc mode, switch cmc mode
#
function sip_switch_case
{
    local cmd
    local result rc i
    local flag=(0 0)
    local modeindex
    local cmcindex=2
    local cmcmodearr=("Active" "Standby" "Unknown")
    #get cmc current state
    for i in {0,1}
    do
        cmd="exec_cmd  mnet show cmcmode cmc $i 2>/dev/null"
        echo $cmd
        result=$(exec_cmd mnet show cmcmode cmc $i 2>/dev/null)
        rc=$?
        [[ $rc == 0 && "$result" == "Active" ]] && flag[$i]=1
        [[ $rc == 0 && "$result" == "Standby" ]] && flag[$i]=0
        (( $rc != 0 )) && flag[$i]=2
    done

    #change cmc state according to acquire above
    if [[ ${flag[0]} == 1 && ${flag[1]} == 0 ]]; then
        cmd="mnet set cmcmode active cmc 0"
        modeindex=${flag[0]}
        log_oak "mnet set cmcmode active cmc 0"
        #result=$(mnet set cmcmode active cmc 0)
        cmcindex=0
    elif [[ ${flag[0]} == 0 && ${flag[1]} == 1 ]]; then
        cmd="mnet set cmcmode active cmc 1"
        modeindex=${flag[1]}
        log_oak "mnet set cmcmode active cmc 0"
        #result=$(mnet set cmcmode active cmc 1)
        cmcindex=1
    else
        local cmc0mode=${flag[0]}
        local cmc1mode=${flag[1]}
        log_oak "cmd 1 mode [${cmcmodearr[$cmc0mode]}]" \
                "cmd 2 mode [${cmcmodearr[$cmc1mode]}]"
    fi
    echo $cmcindex
    return 0
}

#
#check the service ip is configured correctly on NIC according cmc mode
#
function chk_sip_chg_correct
{
    local devarr=("eth0:10" "eth1:10")
    local dev
    local index
    local flag=0
    local chindex=$1
    (($chindex > 1)) && {
        log_oak "invalid cmc index"
        return 1
    }
    dev=${devarr[$chindex]}
    ret=$(ifconfig $dev | grep -w inet | awk '{print $2}')
    [[ $? == 0 && -n "$ret" ]] && {
        log_oak "[$dev] Pass"
        return 0
    }

    log_oak "NO SERVICE IP FOUND ON ${devarr[$chindex]}"
    return 1
}

#
# compare the service ip is the same between midplane 
# and configured on NIC
#
function cmp_sip_midplane_local
{
    local sip_midplane
    local sip_local

    sip_midplane=$(get_serviceip_midplane)
    (($? != 0)) && {
        log_oak "sip_midplane failed"
        return 1
    }
    log_oak "midplane [$sip_midplane]"
    sip_local=$(get_serviceip_local)
    (($? != 0))&& {
        log_oak "sip local failed"
        return 1
    }
    log_oak "local [$sip_local]"
    if [[ "$sip_midplane" == "$sip_local" ]]; then
        log_oak "case PASS"
        return 0
    else
        log_oak "case FAILED"
        return 1
    fi
}

#
# compare the service ip is the same between midplane 
# and default written in file
#
function cmp_sip_midplane_default
{
    local sip_midplane
    local sip_default
    sip_midplane=$(get_serviceip_midplane)
    (($? != 0)) && {
        log_oak "sip_midplane failed"
        return 1
    }
    log_oak "midplane [$sip_local]"
    sip_default=$(get_serviceip_default)
    (($? != 0)) && {
        log_oak "sip default failed"
        return 1
    }
    log_oak "default [$sip_local]"
    if [[ "$sip_default" == "$sip_midplane" ]]; then
        log_oak "case PASS"
        return 0
    else
        log_oak "case FAILED"
        return 1
    fi    
}

