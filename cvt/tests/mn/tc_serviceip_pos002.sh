#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

################################################################################
#
# __stc_assertion_start
#
# ID:	mn/tc_serviceip_pos002
#
# DESCRIPTION:
#	1. validate when active cmc switched from cmc 0 to cmc 1, serviceip is
#	   transfered from eth0:10 to eth1:10
#	2. validate when active cmc switched from cmc 1 to cmc 0, serviceip is
#	   transfered from eth1:10 to eth0:10
#
# STRATEGY:
#	1. make sure that mcs is runing normally
#	2. do cmc switch action by ipmi command
#	3. sleep 20 or longer seconds
#	4. check cmc is switched successfully
#	5. check service ip is transformed successfully according to active cmc
#
# __stc_assertion_end
#
################################################################################

NAME=$(basename $0)
CDIR=$(dirname  $0)
TMPDIR=${TMPDIR:-"/tmp"}
TSROOT=$CDIR/../../

source $TSROOT/lib/libstr.sh
source $TSROOT/lib/libcommon.sh
source $TSROOT/config.vars
source $CDIR/mn_comm.sh
source $CDIR/sip_comm.sh

CHKINTERVAL=5
TESTLOOP=1

function tc_switch_sip_main
{
    local index=0
    local rc sip
    local cmcindex cmcmode
    local flg1 flg2
    local dev=("eth0:10" "eth1:10")
    while (($index < ${TESTLOOP}))
    do
        ((index++))
        flg1=0
        flg2=0
        cmcindex=2
        msg_info "current loop [${index}]"
        cmcmode=$(exec_cmd mnet show cmcmode cmc 0)
        rc=$?
        (( $rc == 0)) && flg1=1
        [[ ${rc} == 0 && "$cmcmode" == "Active" ]] && {
            cmcindex=1
            sip=${dev[cmcindex]}
        }
        (( ${rc} != 0 )) && {
            msg_fail "get cmc 0 cmcmode fail"
            continue
        }
        msg_info "exec_cmd mnet show cmcmode cmc 1"
        cmcmode=$(exec_cmd mnet show cmcmode cmc 1)
        rc=$?
        (($rc == 0)) && flg2=1
        [[ ${rc} == 0  &&  "$cmcmode" == "Active" ]] && {
            cmcindex=0
            sip=${dev[cmcindex]}
        }
        (( ${rc} != 0 )) && {
            msg_fail "get cmc 1 cmcmode fail"
            return 1
        }
        (( ${cmcindex} > 1 )) && { msg_fail "no active cmc";  continue;}
        if [[ ${cmcindex} < 2 && $flg1 == 1 && $flg2 == 1 ]]; then
            msg_info "set cmc $cmcindex to active"
            msg_info "exec_cmd mnet set cmcmode active \
                         cmc ${cmcindex}"
            exec_cmd mnet set cmcmode active cmc ${cmcindex}
            (( $? != 0 )) && {
                msg_fail "cmc change fail"
                return 1
            }
            sleep 5
            cmc_stat=$(exec_cmd mnet show cmcmode cmc ${cmcindex})
            (($? != 0)) && {
                msg_fail "get cmc ${cmcindex} mode faile"
                return 1
            }
            msg_info "cmc ${cmcindex} mode [$cmc_stat]" \
                    "checking interface [$sip]"
            check_sip_config ${sip}
            (($? != 0)) && return 1
        else
            msg_fail "no need to switch cmc $cmcindex $flg1 $flg2"
        fi
    done
    return 0
}
function check_sip_config
{
    #check service ip
    local sip=${1?"require service ip interface"}
    local chk_ind=0
    local foundflag=0
    while (( $chk_ind < 10 ))
    do
        echo "wait for service ip switch ..."
        count=$(ifconfig ${sip} | grep -c -w inet)
        (( $count == 1)) && foundflag=1
        (($foundflag == 1)) && break
        sleep 5
        ((chk_ind++))
    done
    if (( $foundflag == 1 )) ; then
        msg_info "service ip switch success"
        return 0
    else
        msg_fail "service ip switch fail no ip found on ${sip}"
        return 1
    fi

}

tc_start $0
trap "tc_xres \$?" EXIT

tc_switch_sip_main  /tmp || exit $STF_FAILED

exit $STF_PASS
