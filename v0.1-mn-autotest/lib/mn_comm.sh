#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

MAX_TIMEOUT=5
CMC_USER=admin
CMC_PASSWD=admin

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
		[[ $? == 0 && $ret == "Active" ]] && {
			echo $ind
			return
		}
	done
	return 1
}

function get_cmc_ip
{
    local result
    local ip_get_cmd=0x14
    result=$(exec_cmd_bmc ${ip_get_cmd})
    #ip get failed just return
    (($? != 0)) && return 1 
    local arry=($result)
    local cmc0_ip="$((16#${arry[4]})).$((16#${arry[5]})).$((16#${arry[6]})).$((16#${arry[7]}))"
    local cmc1_ip="$((16#${arry[12]})).$((16#${arry[13]})).$((16#${arry[14]})).$((16#${arry[15]}))"
    #get cmc0 state
    local cmcmode_cmd=0x23
    result=$(exec_cmd_cmc ${cmc0_ip} ${cmcmode_cmd})
    if (($? == 0)) && ((${result} == 1)); then
		echo $cmc0_ip
        return
    fi

    #get cmc1 state
    result=$(exec_cmd_cmc ${cmc1_ip} ${cmcmode_cmd})
    if (($? == 0)) && ((${result} == 1)); then
		echo $cmc1_ip
        return 
    fi

    return 2 
}

function exec_cmd_midplane
{
	(( $# < 2))&& {
		echo "parameter required not less than 2 current [$#]:[$@]"
		return 1
	}
	local cmd
	local rec
	local cmcip
	local ret
	cmcip=$1
	shift
	cmd="ipmitool -H ${cmcip} -U ${CMC_USER} -P ${CMC_PASSWD} raw 0x06 0x52 0x0B 0xA0"
	rec="exec_cmd $cmd $@"
	ret=$(exec_cmd $cmd $@)
	(($? == 0)) && {
		echo $ret
		return
	}
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
	(($? == 0)) && {
		echo $ret
		return
	}
	echo $rec
	return 1
}

function exec_cmd_cmc
{
	(( $# < 2))&& {
		echo "parameter required not less than 2 current [$#]:[$@]"
		return 1
	}
	local cmcip=$1
	local cmd ret
	local rec
	shift
	cmd="ipmitool -H ${cmcip} -U ${CMC_USER} -P ${CMC_PASSWD} raw 0x30"
	rec="exec_cmd $cmd $@"
	ret=$(exec_cmd $cmd $@)
	(( $? == 0)) && {
		echo $ret
		return
	}
	echo $rec
	return 1
}

function acqure_clusterid_from_midplane
{
	local cid_cmd
	local cmcip
	local clusterid
	cmcip=$(get_cmc_ip)
	(($? != 0))&& {
		echo "acquire ip failed"
		return 1
	}
	cid_cmd="0x08 0x2F 0xA4"
	clusterid=$(exec_cmd_midplane $cmcip $cid_cmd)
	(($? == 0)) && {
		echo $clusterid
		return
	}
	return 1
}

function exec_cmd_bmc
{
	(($# != 1))&& {
		echo "parameter required one current [$#]:[$@]"
		return 1
	}
	local cmd
	local ret
	local rec
	cmd="ipmitool raw 0x30"
	rec="exec_cmd $cmd $@"
	ret=$(exec_cmd $cmd $@)
	(($? == 0)) && {
		echo $ret
		return
	}
	echo "$rec"
	return 2	
}

function exec_cmd
{
	local rc
	local ret
	local cmd="timeout -k1 ${MAX_TIMEOUT} $@ 2>/dev/null"
	ret=$(timeout -k1 ${MAX_TIMEOUT} $@ 2>/dev/null)
	(($? == 0)) && {
		echo $ret
		return
	}
	echo $ret
	return 2
}

function get_clusterid_local
{
	local cid
	local count
	local flname=/data/vpd_cluster
	[[ -f $flname ]] && {
		while read line
		do
			count=$(echo $line | grep "^FC" | wc -l)
			(( $count == 1)) && {
				echo $line
				return
			} 
		done < $flname
	}
	echo "clusterid not found"
	return 1
}
