#!/bin/bash

AWKCMD=awk
LSCMD=ls
trcfile="/dumps/scrumtest.trc"
g_para_1=$1

valid_cmc_ip=""
eth1ip_of_cmc[2]=0

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
        test_cmd="timeout -k1 2 ipmitool -H ${ipaddr[$i]} -U admin -P admin raw 0x30 0x23"
        test_result=$(${test_cmd})

        if [ $? != 0 ]; then
            log "check cmc${i} is master fail,cmd_rc:$?(124:timeout,127:cmd not exist)"
            continue
        fi

        #log "cmc${i} is:"${test_result}"(1:master,0:slave)"
        valid_cmc_ip=${ipaddr[$i]}
        eth1ip_of_cmc[$i]=${ipaddr[$i]}
        return 0
    done

    log "can't get master cmc ip"
    return 1
}


function log()
{
    echo "[$(date -d today +"%Y-%m-%d %H:%M:%S")]" $* #>>${trcfile}
}


function write_and_check_vpd()
{
    writecmd="/compass/ec_chvpd -w -n $1 -v $2"

    if [[ ${g_para_1} =~ "w_0_r_1" ]] #for test case:write use cmc0 and read use cmc1
    then
        #log "write use cmc0,read use cmc1,close cmc1"
        ifconfig eth2 up
        ifconfig eth3 down
    fi

    ${writecmd}
    cmd_rc=$?
    [ ${cmd_rc} -eq 0 ] || {
        log "cmd exec failed,cmd:${writecmd}, cmd_rc:${cmd_rc}"
        ifconfig eth3 up
        return ${cmd_rc}
    }

    if [[ ${g_para_1} =~ "w_m_r_s" ]] #for test case:write when cmc0 is master and read when cmc0 is slave
    then
        #log "change cmc0 to slave"
        get_valid_cmc_ip
        timeout -k1 2 ipmitool -H ${eth1ip_of_cmc[0]} -U admin -P admin raw 0x30 0x22 0x00 >null
    fi

    if [[ ${g_para_1} =~ "w_0_r_1" ]]
    then
        #log "write use cmc0,read use cmc1,close cmc0"
        ifconfig eth2 down
        ifconfig eth3 up
    fi

    readcmd="/compass/ec_chvpd -r -n $1"
    readresult=$(${readcmd})
    cmd_rc=$?
    [ ${cmd_rc} -eq 0 ] || {
        log "cmd exec failed,cmd:${readcmd}, cmd_rc:${cmd_rc}"
        ifconfig eth2 up
        return ${cmd_rc}
    }

    if [[ ${g_para_1} =~ "w_m_r_s" ]] #for test case:write when cmc0 is master and read when cmc0 is slave
    then
        #log "change cmc0 to master"
        get_valid_cmc_ip
        timeout -k1 2 ipmitool -H ${eth1ip_of_cmc[0]} -U admin -P admin raw 0x30 0x22 0x01 >null
    fi


   #readresult="${readresult}222" #inject error
    #log "w_cmd is ${writecmd}"
    #log "r_cmd is ${readcmd}"
    #log "read result is ${readresult}"

    write_data=$2

    if [[ $1 =~ "vpd_mid_version_e" ]] || [[ $1 =~ "vpd_can_version_e" ]]
    then
        write_data="0${write_data}"
    fi

    [ ${readresult} != ${write_data} ] && {
        ifconfig eth2 up
        log "read_write mismatch,read:${readresult},write:${write_data}"
        return 1
    }
    ifconfig eth2 up
    return 0
}

function write_and_check_vpd_encap()
{
    write_and_check_vpd $1 $2
    cmd_rc=$?
    [ ${cmd_rc} -eq 0 ] || {
        log "cmd exec failed,para1:$1,para2:$2"
        return ${cmd_rc}
    }
}

if [ ! -f ${trcfile} ]
then
    touch ${trcfile}
else
    typeset -i SZ
    SZ=$(${LSCMD} -s ${trcfile} | ${AWKCMD} -F " " '{print $1}')
    SZ=${SZ}*1024
    if [ $SZ -gt 163840 ]
    then
        tail --bytes=163840 ${trcfile} >/tmp/$$ 2>/dev/null
        mv -f /tmp/$$ ${trcfile} 2>/dev/null
    fi
fi

log "============Begin exec script $0 at $(date)============" >>${trcfile}


l=$(($RANDOM%10))
m=$(($RANDOM%10))
n=$(($RANDOM%10))
write_ok=1

cpu_cnt=$(cat /proc/cpuinfo | grep "physical id" | sort | uniq | wc -l)

vpdfield=( "vpd_mid_product_mtm_e 1815-L0${cpu_cnt}"
"vpd_mid_fru_identity_e 11S85Y5962YHU9994G0$l$m$n"
"vpd_mid_version_e 001"
"vpd_mid_fru_part_number_e 85y5896"
"vpd_mid_product_sn_e S9Y9$l$m$n"
"vpd_mid_latest_cluster_id_e 0000000000000000"
"vpd_mid_next_cluster_id_e 00000200642105e2"
"vpd_mid_node1_wwnn_e 56c92bf80100${l}${m}${n}0"
"vpd_mid_node2_wwnn_e 56c92bf80100${l}${m}${n}1"
"vpd_mid_node1_SAT_ipv4_address_e 192.168.001.100"
"vpd_mid_node1_SAT_ipv6_address_e 000000000000000000000000000000000000000"
"vpd_mid_node1_SAT_ipv6_prefix_e 000"
"vpd_mid_node1_SAT_ipv4_subnet_e 255.255.255.000"
"vpd_mid_node1_SAT_ipv4_gateway_e 192.168.001.001"
"vpd_mid_node1_SAT_ipv6_gateway_e 000000000000000000000000000000000000000"
"vpd_mid_node2_SAT_ipv4_address_e 192.168.001.102"
"vpd_mid_node2_SAT_ipv6_address_e 000000000000000000000000000000000000000"
"vpd_mid_node2_SAT_ipv6_prefix_e 000"
"vpd_mid_node2_SAT_ipv4_subnet_e 255.255.255.000"
"vpd_mid_node2_SAT_ipv4_gateway_e 192.168.001.001"
"vpd_mid_node2_SAT_ipv6_gateway_e 000000000000000000000000000000000000000"
"vpd_mid_node1_original_wwnn_e 0000000000000000"
"vpd_mid_node2_original_wwnn_e 0000000000000000" )
arr_mem_cnt=${#vpdfield[@]}
arr_index=0

while [ $((${arr_index})) -lt $((${arr_mem_cnt})) ]
do
    write_and_check_vpd_encap ${vpdfield[$arr_index]}
    #log ${vpdfield[$arr_index]}
    [ $? -eq 0 ] || {
        write_ok=0
        break
    }
    arr_index=$(($arr_index+1))
done

#The first loop of writing is used for initialization，and in the scecond loop of writing we need to check whether other vpd entries is changed
#when one vpd entry is written
if [[ ${g_para_1} =~ "w_affec" ]]; then
    arr_index=0
    log "check whether other vpd fields will be changed when we write one field"
    while [ $((${arr_index})) -lt $((${arr_mem_cnt})) ]; do
        write_and_check_vpd_encap ${vpdfield[$arr_index]}
        #log ${vpdfield[$arr_index]}
        [ $? -eq 0 ] || {
            write_ok=0
            break
        }

        arr_index_j=0
        while [ $((${arr_index_j})) -lt $((${arr_mem_cnt})) ]; do
            log "arr_index_j is ${arr_index_j}, arr_index is ${arr_index}"
            if [ "${arr_index_j}" = "${arr_index}" ]; then
                arr_index_j=$(($arr_index_j+1))
                continue
            fi
            tmp_arr=(${vpdfield[$arr_index_j]})
            readcmd="/compass/ec_chvpd -r -n ${tmp_arr[0]}"
            readresult=$(${readcmd})
            cmd_rc=$?
            [ ${cmd_rc} -eq 0 ] || {
                log "cmd exec failed,cmd:${readcmd}, cmd_rc:${cmd_rc}"
                exit ${cmd_rc}
            }
            log "read_write compare,read:${readresult},write:${tmp_arr[1]}"
            write_data=${tmp_arr[1]}
            if [[ ${tmp_arr[0]} =~ "vpd_mid_version_e" ]]
            then
                write_data="0${write_data}"
            fi

            [ ${readresult} != ${write_data} ] && {
                log "read_write mismatch,read:${readresult},write:${tmp_arr[1]}"
                exit 1
            }
            arr_index_j=$(($arr_index_j+1))
        done

        arr_index=$(($arr_index+1))
    done
fi

if [ $write_ok = 1 ]; then
    log "write midplane vpd OK"
    exit 0
else
    log "write midplane vpd fail"
    exit 1
fi
