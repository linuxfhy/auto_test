#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

MAX_TIMEOUT=5
CMC_USER=admin
CMC_PASSWD=admin

function dbg_echo
{
    echo $@
}

function log_oak
{
	local dat=$(date +"%Y%m%d %H:%M:%S")
	echo $@
}

function get_active_cmc
{
	local ind
	local cmd
	local ret
	for ind in {0,1}
	do
		ret=$(exec_cmd mnet show cmcmode cmc $ind)
		if [[ $? == 0 && $ret == "Active" ]]; then
			echo $ind
			return 0
		fi
	done
	return 1
}

function get_cmc_ip
{
    local result
    local ip_get_cmd=0x14
    local cmc0_ip
    local cmc1_ip
    local tmp_ip
    result=$(exec_cmd_bmc ${ip_get_cmd})
    #ip get failed just return
    (( $? != 0 )) && return 1 
    local arry=($result)
    tmp_ip="0x${arr[4]} 0x${arr[5]} 0x${arr[6]} 0x${arr[7]}"
    cmc0_ip=(printf "%d.%d.%d.%d" $tmp_ip)

    tmp_ip="0x${arr[12]} 0x${arr[13]} 0x${arr[14]} 0x${arr[15]}"
    cmc1_ip=(printf "%d.%d.%d.%d" $tmp_ip)
    #get cmc0 state
    local cmcmode_cmd=0x23
    result=$(exec_cmd_cmc ${cmc0_ip} ${cmcmode_cmd})
    if (($? == 0)) && ((${result} == 1)); then
		echo $cmc0_ip
        return 0
    fi

    #get cmc1 state
    result=$(exec_cmd_cmc ${cmc1_ip} ${cmcmode_cmd})
    if (( $? == 0 )) && (( ${result} == 1 )); then
		echo $cmc1_ip
        return 0
    fi

    return 2 
}

function exec_cmd_midplane
{
	if (( $# < 2)); then
		echo "parameter required not less than 2 current [$#]:[$@]"
		return 1
	fi
	local cmd
	local rec
	local cmcip
	local ret
	local mid_code
	cmcip=$1
	shift
	midplane_code="0x06 0x52 0x0B 0xA0"
	cmd="ipmitool -H ${cmcip} -U ${CMC_USER} -P ${CMC_PASSWD} raw $mid_code"
	rec="exec_cmd $cmd $@"
	ret=$(exec_cmd $cmd $@)
	if (( $? == 0 )); then
		echo $ret
		return 0
	fi
	echo 
	return 1
}

function exec_cmd_cani
{
	local cmd
	local ret
	local rec
	cmd="ipmitool raw 0x06 0x52 0x09 0xAC"
	rec="exec_cmd $cmd $@"
	ret=$(exec_cmd $cmd $@)
	if (( $? == 0 )); then
		echo $ret
		return 0
	fi
	echo $rec
	return 1
}

function exec_cmd_cmc
{
	if (( $# < 2 )); then
		echo "parameter required not less than 2 current [$#]:[$@]"
		return 1
	fi
	local cmcip=$1
	local cmd ret
	local rec
	shift
	cmd="ipmitool -H ${cmcip} -U ${CMC_USER} -P ${CMC_PASSWD} raw 0x30"
	rec="exec_cmd $cmd $@"
	ret=$(exec_cmd $cmd $@)
	if (( $? == 0 )); then
		echo $ret
		return 0
	fi
	echo $rec
	return 1
}

function acqure_clusterid_from_midplane
{
	local cid_cmd
	local cmcip
	local clusterid
	cmcip=$(get_cmc_ip)
	if (( $? != 0 )); then
		echo "acquire ip failed"
		return 1
	fi
	cid_cmd="0x08 0x2F 0xA4"
	clusterid=$(exec_cmd_midplane $cmcip $cid_cmd)
	if (( $? == 0 )); then
		echo $clusterid
		return 0
	fi
	return 1
}

function exec_cmd_bmc
{
	if (($# != 1)); then
		echo "parameter required one current [$#]:[$@]"
		return 1
	fi
	local cmd
	local ret
	local rec
	cmd="ipmitool raw 0x30"
	rec="exec_cmd $cmd $@"
	ret=$(exec_cmd $cmd $@)
	if (($? == 0)); then
		echo $ret
		return 0
	fi
	echo "$rec"
	return 2	
}

function exec_cmd
{
	local rc
	local ret
	local cmd="timeout -k1 ${MAX_TIMEOUT} $@ 2>/dev/null"
	ret=$(timeout -k1 ${MAX_TIMEOUT} $@ 2>/dev/null)
	if (( $? == 0 )); then
		echo $ret
		return
	fi
	echo $ret
	return 2
}

function get_clusterid_local
{
	local cid
	local count
	local flname=/data/vpd_cluster
	if [[ -f $flname ]]; then
		while read line
		do
			count=$(echo $line | grep "^FC" | wc -l)
			if (( $count == 1)); then
				echo $line
				return 0
			fi
		done < $flname
	fi
	echo "clusterid not found"
	return 1
}
