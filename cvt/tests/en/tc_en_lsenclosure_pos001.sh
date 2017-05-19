#!/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

NAME=$(basename $0)
CDIR=$(dirname  $0)
TMPDIR=${TMPDIR:-"/tmp"}
TSROOT=$CDIR/../../

source $TSROOT/lib/libstr.sh
source $TSROOT/lib/libcommon.sh
source $TSROOT/config.vars

tc_start $0
trap "tc_xres \$?" EXIT

EN_TEST_DIR=$PWD
TEST_CASE_ELEMENT_TYPE=""
current_time="date +%Y-%m-%d--%H:%M:%S"

IPMITOOL=/usr/bin/ipmitool
IPMITOOL_REAL=/usr/bin/ipmitool.real
IPMITOOL_SHELL=$PWD/ipmitool.sh2

IPMI_INJECT=$EN_TEST_DIR/ipmi.inject
#[ -e "$IPMI_INJECT" ] && source "$IPMI_INJECT"

log_file_time=$($current_time)
mkdir -p $EN_TEST_DIR/log
TEST_SUCC_LOG=$EN_TEST_DIR/log/test_succ.log.$log_file_time
TEST_ERR_LOG=$EN_TEST_DIR/log/test_err.log.$log_file_time
IPMITOOL_DEBUG_LOG=/tmp/ipmitool_debug.log

> $TEST_SUCC_LOG
> $TEST_ERR_LOG
> $IPMITOOL_DEBUG_LOG


recover_evironment()
{
    mount -o remount,rw /
    [ -f "$IPMITOOL_REAL" ] && rm -fr $IPMITOOL
    [ -f "$IPMITOOL_REAL" ] && cp -a $IPMITOOL_REAL $IPMITOOL
}

echo_exit()
{
	echo -e "[$($current_time)] [ERROR ] $@"
	echo -e "[$($current_time)] [ERROR ] $@" >>/$TEST_ERR_LOG
	recover_evironment
	exit 1
}
echo_success()
{
	echo -e "[$($current_time)] [SUCC ] $@"
	echo -e "[$($current_time)] [SUCC ] $@" >>/$TEST_SUCC_LOG
}
echo_log()
{
	echo -e "[$($current_time)] $@"
	echo -e "[$($current_time)] $@" >>/$TEST_SUCC_LOG
}
trap "echo_exit killed by signal" INT

# $1 output, $2 cmd, $3 error string
wait_120s()
{
	out="$1"
	cmd="$2"
        ret=""
	for ((i=0; i < 50; ++i)); do
                ret="$($cmd)"
		[ "$(echo $ret | grep "$out")" ] && {
			#echo -e "[SUCC] $3 (cmd $cmd expect $out)\n"
			echo_success "$3 (cmd $cmd expect $out)\n"
			return 0
		}
		sleep 8
	done

	echo_exit "$3 (cmd $cmd expect $out,but $ret)"
}

wait2_120s()
{
	cmd="$2"
	grepstr=`echo $1|awk -F "+" '{print $1}'`
	key=`echo $1|awk -F "+" '{print $2}'`
	value=`echo $1|awk -F "+" '{print $3}'`
	colnum=`echo "$($cmd)"|head -1|awk -v str=$key '{v="";for (i=1;i<=NF;i++) if($i==str)v=v?"":i;if (v) print v}'`
	[ -z "$colnum" ] && {
		echo -e "can not find $key in $cmd output\n" 
		return 0
	}
	ret=""
	for ((i=0; i < 50; ++i)); do
        ret=`$cmd | grep -m 1 "$grepstr" | sed s"/$grepstr/sensor_name/" | awk -v col=$colnum '{print $col}'`  
		[ "$ret" = "$value" ] && {
			#echo -e "[SUCC] $3 (cmd $cmd expect $out)\n"
			echo_success "$3 (cmd $cmd expect $out)\n"
			return 0
		}
		sleep 8
	done

	echo_exit "$3 (cmd $cmd expect $out,but $ret)"
}

wait3_120s()
{
	cmd="$2"
	grepstr=`echo $1|awk -F "+" '{print $1}'`
	key=`echo $1|awk -F "+" '{print $2}'`
	value=`echo $1|awk -F "+" '{print $3}'`
	colnum=`echo "$($cmd)"|head -1|awk -v str=$key '{v="";for (i=1;i<=NF;i++) if($i==str)v=v?"":i;if (v) print v}'`
	[ -z "$colnum" ] && { 
		echo -e "can not find $key in $cmd output\n" 
		return 0
	}
	alarm_status_colnum=`echo "$($cmd)"|head -1|awk -v str="alarm_status" '{v="";for (i=1;i<=NF;i++) if($i==str)v=v?"":i;if (v) print v}'`
	ret=""
	for ((i=0; i < 50; ++i)); do
	    if [[ $key = "alarm_status" ]]
		then
		    ret=`$cmd | grep -m 1 -E "$grepstr[[:space:]]+[[:digit:]]" | grep "$value"`
			[ -n "$ret" ] && {
			    #echo -e "[SUCC] $3 (cmd $cmd expect $out)\n"
			    echo_success "$3 (cmd $cmd expect $out)\n"
				return 0
			}
		else
			ret=`$cmd | grep -m 1 -E "$grepstr[[:space:]]+[[:digit:]]"  | sed s"/$grepstr/sensor_name/" | awk -v col=$colnum  -v col2=$alarm_status_colnum '{if(col2<col&&($(col2+1)=="under"||$(col2+1)=="over"))print $(col+1); else print $col}'`  
			[ "$ret" = "$value" ] && {
			    #echo -e "[SUCC] $3 (cmd $cmd expect $out)\n"
			    echo_success "$3 (cmd $cmd expect $out)\n"
				return 0
			}
		fi
		sleep 8
	done

	echo_exit "$3 (cmd $cmd expect $out,but $ret)"
}

#$1 condition $2 output, $3 cmd, $4, error string
test_case()
{
   condition="$1"
   out="$2"
   cmd="$3"
   error_log="$4"
   eval $condition
   echo "$condition">$IPMI_INJECT
   echo "TEST_CASE=open">>$IPMI_INJECT
   echo "TEST_CASE_ELEMENT_TYPE=$TEST_CASE_ELEMENT_TYPE">>$IPMI_INJECT
   [ -e "$IPMI_INJECT" ] && . "$IPMI_INJECT"

   echo_log  "[start test] : $out $cmd $error_log "

   specialcmd="svcinfo lsenclosuretemperature   svcinfo lsenclosurecurrent"
   if [[ $cmd = "svcinfo lsenclosurevoltage" ]];   then
       wait3_120s "$out"   "$cmd" "$error_log"
   elif [[ $specialcmd =~ $cmd ]];   then
       wait2_120s "$out"   "$cmd" "$error_log"
   else
   wait_120s "$out"   "$cmd" "$error_log"
   fi
}
function test_case_fan
{
    echo_log "##########################TEST FAN  #################################"
    TEST_CASE_ELEMENT_TYPE=FAN

    FAN0_status=online ;      	   test_case FAN0_status=online            "status $FAN0_status"                         "lsenclosurefanmodule -fanmodule 1 93" "inject test FAN0 $FAN0_status"
    FAN0_status=offline;      	   test_case FAN0_status=offline           "status $FAN0_status"                         "lsenclosurefanmodule -fanmodule 1 93" "inject test FAN0 $FAN0_status"
    FAN0_alarm_status=normal; 	   test_case FAN0_alarm_status=normal      "alarm_status $FAN0_alarm_status"             "lsenclosurefanmodule -fanmodule 1 93" "inject test FAN0 alarm_status $FAN0_alarm_status"
    FAN0_alarm_status=warning;	   test_case FAN0_alarm_status=warning     "alarm_status $FAN0_alarm_status"             "lsenclosurefanmodule -fanmodule 1 93" "inject test FAN0 alarm_status $FAN0_alarm_status"
    FAN0_alarm_status=critical;	   test_case FAN0_alarm_status=critical    "alarm_status $FAN0_alarm_status"             "lsenclosurefanmodule -fanmodule 1 93" "inject test FAN0 alarm_status $FAN0_alarm_status"
    FAN0_switch_status=on;    	   test_case FAN0_switch_status=on         "switch_status $FAN0_switch_status"           "lsenclosurefanmodule -fanmodule 1 93" "inject test FAN0 switch_status $FAN0_switch_status"
    FAN0_switch_status=off;   	   test_case FAN0_switch_status=off        "switch_status $FAN0_switch_status"           "lsenclosurefanmodule -fanmodule 1 93" "inject test FAN0 switch_status $FAN0_switch_status"
    FAN0_speed_mode=auto;     	   test_case FAN0_speed_mode=auto          "speed_mode $FAN0_speed_mode"                 "lsenclosurefanmodule -fanmodule 1 93" "inject test FAN0 speed_mode $FAN0_speed_mode"
    FAN0_speed_mode=manua;    	   test_case FAN0_speed_mode=manual        "speed_mode $FAN0_speed_mode"                 "lsenclosurefanmodule -fanmodule 1 93" "inject test FAN0 speed_mode $FAN0_speed_mode"
    FAN0_speed=4000;          	   test_case FAN0_speed=4000               "speed $FAN0_speed"                           "lsenclosurefanmodule -fanmodule 1 93" "inject test FAN0 speed $FAN0_speed"
    FAN0_waring_threshold=2000;	   test_case FAN0_waring_threshold=2000    "warning_threshold $FAN0_waring_threshold"    "lsenclosurefanmodule -fanmodule 1 93" "inject test FAN0 warning_threshold $FAN0_waring_threshold"
    FAN0_critical_threshold=400;   test_case FAN0_critical_threshold=400   "critical_threshold $FAN0_critical_threshold" "lsenclosurefanmodule -fanmodule 1 93" "inject test FAN0 critical_threshold $FAN0_critical_threshold"
    FAN0_fault_LED=on;        	   test_case FAN0_fault_LED=on             "fault_LED $FAN0_fault_LED"                   "lsenclosurefanmodule -fanmodule 1 93" "inject test FAN0 fault_LED $FAN0_fault_LED"
    FAN0_fault_LED=off;       	   test_case FAN0_fault_LED=off            "fault_LED $FAN0_fault_LED"                   "lsenclosurefanmodule -fanmodule 1 93" "inject test FAN0 fault_LED $FAN0_fault_LED"

    FAN1_status=online ;      	   test_case FAN1_status=online            "status $FAN1_status"                         "lsenclosurefanmodule -fanmodule 2 93" "inject test FAN1 $FAN1_status"
    FAN1_status=offline;      	   test_case FAN1_status=offline           "status $FAN1_status"                         "lsenclosurefanmodule -fanmodule 2 93" "inject test FAN1 $FAN1_status"
    FAN1_alarm_status=normal; 	   test_case FAN1_alarm_status=normal      "alarm_status $FAN1_alarm_status"             "lsenclosurefanmodule -fanmodule 2 93" "inject test FAN1 alarm_status $FAN1_alarm_status"
    FAN1_alarm_status=warning;	   test_case FAN1_alarm_status=warning     "alarm_status $FAN1_alarm_status"             "lsenclosurefanmodule -fanmodule 2 93" "inject test FAN1 alarm_status $FAN1_alarm_status"
    FAN1_alarm_status=critical;	   test_case FAN1_alarm_status=critical    "alarm_status $FAN1_alarm_status"             "lsenclosurefanmodule -fanmodule 2 93" "inject test FAN1 alarm_status $FAN1_alarm_status"
    FAN1_switch_status=on;    	   test_case FAN1_switch_status=on         "switch_status $FAN1_switch_status"           "lsenclosurefanmodule -fanmodule 2 93" "inject test FAN1 switch_status $FAN1_switch_status"
    FAN1_switch_status=off;   	   test_case FAN1_switch_status=off        "switch_status $FAN1_switch_status"           "lsenclosurefanmodule -fanmodule 2 93" "inject test FAN1 switch_status $FAN1_switch_status"
    FAN1_speed_mode=auto;     	   test_case FAN1_speed_mode=auto          "speed_mode $FAN1_speed_mode"                 "lsenclosurefanmodule -fanmodule 2 93" "inject test FAN1 speed_mode $FAN1_speed_mode"
    FAN1_speed_mode=manua;    	   test_case FAN1_speed_mode=manual        "speed_mode $FAN1_speed_mode"                 "lsenclosurefanmodule -fanmodule 2 93" "inject test FAN1 speed_mode $FAN1_speed_mode"
    FAN1_speed=4000;          	   test_case FAN1_speed=4000               "speed $FAN1_speed"                           "lsenclosurefanmodule -fanmodule 2 93" "inject test FAN1 speed $FAN1_speed"
    FAN1_waring_threshold=2000;	   test_case FAN1_waring_threshold=2000    "warning_threshold $FAN1_waring_threshold"    "lsenclosurefanmodule -fanmodule 2 93" "inject test FAN1 warning_threshold $FAN1_waring_threshold"
    FAN1_critical_threshold=400;   test_case FAN1_critical_threshold=400   "critical_threshold $FAN1_critical_threshold" "lsenclosurefanmodule -fanmodule 2 93" "inject test FAN1 critical_threshold $FAN1_critical_threshold"
    FAN1_fault_LED=on;        	   test_case FAN1_fault_LED=on             "fault_LED $FAN1_fault_LED"                   "lsenclosurefanmodule -fanmodule 2 93" "inject test FAN1 fault_LED $FAN1_fault_LED"
    FAN1_fault_LED=off;       	   test_case FAN1_fault_LED=off            "fault_LED $FAN1_fault_LED"                   "lsenclosurefanmodule -fanmodule 2 93" "inject test FAN1 fault_LED $FAN1_fault_LED"

    FAN2_status=online ;      	   test_case FAN2_status=online            "status $FAN2_status"                         "lsenclosurefanmodule -fanmodule 3 93" "inject test FAN2 $FAN2_status"
    FAN2_status=offline;      	   test_case FAN2_status=offline           "status $FAN2_status"                         "lsenclosurefanmodule -fanmodule 3 93" "inject test FAN2 $FAN2_status"
    FAN2_alarm_status=normal; 	   test_case FAN2_alarm_status=normal      "alarm_status $FAN2_alarm_status"             "lsenclosurefanmodule -fanmodule 3 93" "inject test FAN2 alarm_status $FAN2_alarm_status"
    FAN2_alarm_status=warning;	   test_case FAN2_alarm_status=warning     "alarm_status $FAN2_alarm_status"             "lsenclosurefanmodule -fanmodule 3 93" "inject test FAN2 alarm_status $FAN2_alarm_status"
    FAN2_alarm_status=critical;	   test_case FAN2_alarm_status=critical    "alarm_status $FAN2_alarm_status"             "lsenclosurefanmodule -fanmodule 3 93" "inject test FAN2 alarm_status $FAN2_alarm_status"
    FAN2_switch_status=on;    	   test_case FAN2_switch_status=on         "switch_status $FAN2_switch_status"           "lsenclosurefanmodule -fanmodule 3 93" "inject test FAN2 switch_status $FAN2_switch_status"
    FAN2_switch_status=off;   	   test_case FAN2_switch_status=off        "switch_status $FAN2_switch_status"           "lsenclosurefanmodule -fanmodule 3 93" "inject test FAN2 switch_status $FAN2_switch_status"
    FAN2_speed_mode=auto;     	   test_case FAN2_speed_mode=auto          "speed_mode $FAN2_speed_mode"                 "lsenclosurefanmodule -fanmodule 3 93" "inject test FAN2 speed_mode $FAN2_speed_mode"
    FAN2_speed_mode=manua;    	   test_case FAN2_speed_mode=manual        "speed_mode $FAN2_speed_mode"                 "lsenclosurefanmodule -fanmodule 3 93" "inject test FAN2 speed_mode $FAN2_speed_mode"
    FAN2_speed=4000;          	   test_case FAN2_speed=4000               "speed $FAN2_speed"                           "lsenclosurefanmodule -fanmodule 3 93" "inject test FAN2 speed $FAN2_speed"
    FAN2_waring_threshold=2000;	   test_case FAN2_waring_threshold=2000    "warning_threshold $FAN2_waring_threshold"    "lsenclosurefanmodule -fanmodule 3 93" "inject test FAN2 warning_threshold $FAN2_waring_threshold"
    FAN2_critical_threshold=400;   test_case FAN2_critical_threshold=400   "critical_threshold $FAN2_critical_threshold" "lsenclosurefanmodule -fanmodule 3 93" "inject test FAN2 critical_threshold $FAN2_critical_threshold"
    FAN2_fault_LED=on;        	   test_case FAN2_fault_LED=on             "fault_LED $FAN2_fault_LED"                   "lsenclosurefanmodule -fanmodule 3 93" "inject test FAN2 fault_LED $FAN2_fault_LED"
    FAN2_fault_LED=off;       	   test_case FAN2_fault_LED=off            "fault_LED $FAN2_fault_LED"                   "lsenclosurefanmodule -fanmodule 3 93" "inject test FAN2 fault_LED $FAN2_fault_LED"

    TEST_CASE_ELEMENT_TYPE=""
    echo_log "##########################TEST FAN END #################################"
}
function test_case_psu
{
    echo_log "##########################TEST PSU  ####################################"
    TEST_CASE_ELEMENT_TYPE=PSU

    PSU0_INPUT_FAILED=on;                      test_case PSU0_INPUT_FAILED=on                         "input_failed $PSU0_INPUT_FAILED"                                         "lsenclosurepsu -psu 1 93" "inject test PSU0 input_failed on"
    PSU0_INPUT_FAILED=off;                     test_case PSU0_INPUT_FAILED=off                        "input_failed $PSU0_INPUT_FAILED"                                         "lsenclosurepsu -psu 1 93" "inject test PSU0 input_failed off"
    PSU0_OUTPUT_FAILED=on;                     test_case PSU0_OUTPUT_FAILED=on                        "output_failed $PSU0_OUTPUT_FAILED"                                       "lsenclosurepsu -psu 1 93" "inject test PSU0 output_failed on"
    PSU0_OUTPUT_FAILED=off;                    test_case PSU0_OUTPUT_FAILED=off                       "output_failed $PSU0_OUTPUT_FAILED"                                       "lsenclosurepsu -psu 1 93" "inject test PSU0 output_failed off"
    PSU0_FAN_FAILED=on;                        test_case PSU0_FAN_FAILED=on                           "fan_failed $PSU0_FAN_FAILED"                                             "lsenclosurepsu -psu 1 93" "inject test PSU0 fan_failed on"    
    PSU0_FAN_FAILED=off;                       test_case PSU0_FAN_FAILED=off                          "fan_failed $PSU0_FAN_FAILED"                                             "lsenclosurepsu -psu 1 93" "inject test PSU0 fan_failed off"    
    
    PSU0_REDUNDANT=no;Enclosure_PSU_Status=online,offline;   test_case "PSU0_REDUNDANT=no;Enclosure_PSU_Status=online,offline;"    "redundant $PSU0_REDUNDANT"                       "lsenclosurepsu -psu 1 93" "inject test PSU0 redundant no"    
    PSU0_REDUNDANT=yes;Enclosure_PSU_Status=online,online;   test_case "PSU0_REDUNDANT=yes;Enclosure_PSU_Status=online,online;"    "redundant $PSU0_REDUNDANT"                       "lsenclosurepsu -psu 1 93" "inject test PSU0 redundant yes"    
      
    PSU0_FRU_PART_NUMBER="012345678901";                     test_case "RAW_OUTPUT_START=6;PSU0_FRU_PART_NUMBER=012345678901"      "FRU_part_number $PSU0_FRU_PART_NUMBER"           "lsenclosurepsu -psu 1 93" "inject test PSU0 FRU_part_number"    
    PSU0_FWLEVEL1="0123";                                    test_case "RAW_OUTPUT_START=18;PSU0_FWLEVEL1=0123"                    "firmware_level_1 $PSU0_FWLEVEL1"                 "lsenclosurepsu -psu 1 93" "inject test PSU0 firmware_level_1"    
    PSU0_FRU_IDENTITY="012345678901234";                     test_case "RAW_OUTPUT_START=1;PSU0_FRU_IDENTITY=012345678901234"      "FRU_identity $PSU0_FRU_IDENTITY"                 "lsenclosurepsu -psu 1 93" "inject test PSU0 FRU_identity"    
    PSU0_SWITCH_STATUS="on";                   test_case PSU0_SWITCH_STATUS=on                        "switch_status $PSU0_SWITCH_STATUS"                                       "lsenclosurepsu -psu 1 93" "inject test PSU0 switch_status"    
    PSU0_SWITCH_STATUS="off";                  test_case PSU0_SWITCH_STATUS=off                       "switch_status $PSU0_SWITCH_STATUS"                                       "lsenclosurepsu -psu 1 93" "inject test PSU0 switch_status"    
    PSU0_FAULT_INFO="normal";                  test_case PSU0_FAULT_INFO=normal                       "fault_info $PSU0_FAULT_INFO"                                             "lsenclosurepsu -psu 1 93" "inject test PSU0 fault_info"    
    PSU0_FAULT_INFO="AC_un_v";                 test_case PSU0_FAULT_INFO=AC_un_v                      "fault_info $PSU0_FAULT_INFO"                                             "lsenclosurepsu -psu 1 93" "inject test PSU0 fault_info"    
    PSU0_FAULT_INFO="AC_ov_v";                 test_case PSU0_FAULT_INFO=AC_ov_v                      "fault_info $PSU0_FAULT_INFO"                                             "lsenclosurepsu -psu 1 93" "inject test PSU0 fault_info"    
    PSU0_FAULT_INFO="ov_tm_wn";                test_case PSU0_FAULT_INFO=ov_tm_wn                     "fault_info $PSU0_FAULT_INFO"                                             "lsenclosurepsu -psu 1 93" "inject test PSU0 fault_info"    
    PSU0_FAULT_INFO="AC_un_v:ov_tm_wn";        test_case PSU0_FAULT_INFO=AC_un_v:ov_tm_wn             "fault_info $PSU0_FAULT_INFO"                                             "lsenclosurepsu -psu 1 93" "inject test PSU0 fault_info"    
    PSU0_FAULT_INFO="AC_ov_v:ov_tm_wn";        test_case PSU0_FAULT_INFO=AC_ov_v:ov_tm_wn             "fault_info $PSU0_FAULT_INFO"                                             "lsenclosurepsu -psu 1 93" "inject test PSU0 fault_info"    
    PSU0_FAULT_INFO="ov_tm_fl";                test_case PSU0_FAULT_INFO=ov_tm_fl                     "fault_info $PSU0_FAULT_INFO"                                             "lsenclosurepsu -psu 1 93" "inject test PSU0 fault_info"    
    PSU0_FAULT_INFO="AC_un_v:ov_tm_fl";        test_case PSU0_FAULT_INFO=AC_un_v:ov_tm_fl             "fault_info $PSU0_FAULT_INFO"                                             "lsenclosurepsu -psu 1 93" "inject test PSU0 fault_info"    
    PSU0_FAULT_INFO="AC_ov_v:ov_tm_fl";        test_case PSU0_FAULT_INFO=AC_ov_v:ov_tm_fl             "fault_info $PSU0_FAULT_INFO"                                             "lsenclosurepsu -psu 1 93" "inject test PSU0 fault_info"    
    PSU0_INPUT_POWER="ac";                     test_case PSU0_INPUT_POWER=ac                          "input_power $PSU0_INPUT_POWER"                                           "lsenclosurepsu -psu 1 93" "inject test PSU0 input_power"    
    PSU0_INPUT_POWER="invalid";                test_case PSU0_INPUT_POWER=invalid                     "input_power $PSU0_INPUT_POWER"                                           "lsenclosurepsu -psu 1 93" "inject test PSU0 input_power"    

    PSU0_ALARM_STATUS="normal";                test_case PSU0_ALARM_STATUS=normal                     "alarm_status $PSU0_ALARM_STATUS"                                         "lsenclosurepsu -psu 1 93" "inject test PSU0 alarm_status"    
    PSU0_ALARM_STATUS="warning";               test_case PSU0_ALARM_STATUS=warning                    "alarm_status $PSU0_ALARM_STATUS"                                         "lsenclosurepsu -psu 1 93" "inject test PSU0 alarm_status"    
    PSU0_ALARM_STATUS="critical";              test_case PSU0_ALARM_STATUS=critical                   "alarm_status $PSU0_ALARM_STATUS"                                         "lsenclosurepsu -psu 1 93" "inject test PSU0 alarm_status"    

    PSU0_status=online;                        test_case PSU0_status=online                           "status $PSU0_Status"                                                     "lsenclosurepsu -psu 1 93" "inject test PSU0 status online"
    PSU0_status=offline;                       test_case PSU0_status=offline                          "status $PSU0_Status"                                                     "lsenclosurepsu -psu 1 93" "inject test PSU0 status offline"
    PSU0_input_power_watt=100;                 test_case PSU0_input_power_watt=100                    "input_power_watt $PSU0_input_power_watt"                                 "lsenclosurepsu -psu 1 93" "inject test PSU0 input_power_watt 100"
    PSU0_input_power_watt_over_threshold=100;  test_case PSU0_input_power_watt_over_threshold=100     "input_power_watt_over_threshold $PSU0_input_power_watt_over_threshold"   "lsenclosurepsu -psu 1 93" "inject test PSU0 input_power_watt_over_threshold 100"
    PSU0_input_voltage=100;                    test_case PSU0_input_voltage=100                       "input_voltage $PSU0_input_voltage"                                       "lsenclosurepsu -psu 1 93" "inject test PSU0 input_voltage 100"
    PSU0_input_voltage_under_threshold=100;    test_case PSU0_input_voltage_under_threshold=100       "input_voltage_under_threshold $PSU0_input_voltage_under_threshold"       "lsenclosurepsu -psu 1 93" "inject test PSU0 input_voltage_under_threshold 100"
    PSU0_input_voltage_over_threshold=100;     test_case PSU0_input_voltage_over_threshold=100        "input_voltage_over_threshold $PSU0_input_voltage_over_threshold"         "lsenclosurepsu -psu 1 93" "inject test PSU0 input_voltage_over_threshold 100"
    PSU0_output_power_watt=100;                test_case PSU0_output_power_watt=100                   "output_power_watt $PSU0_output_power_watt"                               "lsenclosurepsu -psu 1 93" "inject test PSU0 output_power_watt 100"
    PSU0_output_power_watt_over_threshold=100; test_case PSU0_output_power_watt_over_threshold=100    "output_power_watt_over_threshold $PSU0_output_power_watt_over_threshold" "lsenclosurepsu -psu 1 93" "inject test PSU0 output_power_watt_over_threshold 100"
    PSU0_output_voltage=100;                   test_case PSU0_output_voltage=100                      "output_voltage $PSU0_output_voltage"                                     "lsenclosurepsu -psu 1 93" "inject test PSU0 output_voltage 100"
    PSU0_output_voltage_under_threshold=100;   test_case PSU0_output_voltage_under_threshold=100      "output_voltage_under_threshold $PSU0_output_voltage_under_threshold"     "lsenclosurepsu -psu 1 93" "inject test PSU0 output_voltage_under_threshold 100"
    PSU0_output_voltage_over_threshold=100;    test_case PSU0_output_voltage_over_threshold=100       "output_voltage_over_threshold $PSU0_output_voltage_over_threshold"       "lsenclosurepsu -psu 1 93" "inject test PSU0 output_voltage_over_threshold 100"
    PSU0_temperature=100;                      test_case PSU0_temperature=100                         "temperature $PSU0_temperature"                                           "lsenclosurepsu -psu 1 93" "inject test PSU0 temperature 100"
    PSU0_temperature_warning_threshold=100;    test_case PSU0_temperature_warning_threshold=100       "temperature $PSU0_temperature_warning_threshold"                         "lsenclosurepsu -psu 1 93" "inject test PSU0 temperature_warning_threshold 100"
    PSU0_temperature_critical_threshold=100;   test_case PSU0_temperature_critical_threshold=100      "temperature $PSU0_temperature_critical_threshold"                        "lsenclosurepsu -psu 1 93" "inject test PSU0 temperature_critical_threshold 100"
    PSU0_fantray_speed=100;                    test_case PSU0_fantray_speed=100                       "temperature $PSU0_fantray_speed"                                         "lsenclosurepsu -psu 1 93" "inject test PSU0 fantray_speed 100"
    PSU0_fantray_warning_threshold=100;        test_case PSU0_fantray_warning_threshold=100           "temperature $PSU0_fantray_warning_threshold"                             "lsenclosurepsu -psu 1 93" "inject test PSU0 fantray_warning_threshold 100"
    PSU0_fantray_critical_threshold=100;       test_case PSU0_fantray_critical_threshold=100          "temperature $PSU0_fantray_critical_threshold"                            "lsenclosurepsu -psu 1 93" "inject test PSU0 fantray_critical_threshold 100"

  
    PSU1_INPUT_FAILED=on;                      test_case PSU1_INPUT_FAILED=on                         "input_failed $PSU1_INPUT_FAILED"                                         "lsenclosurepsu -psu 2 93" "inject test PSU1 input_failed on"
    PSU1_INPUT_FAILED=off;                     test_case PSU1_INPUT_FAILED=off                        "input_failed $PSU1_INPUT_FAILED"                                         "lsenclosurepsu -psu 2 93" "inject test PSU1 input_failed off"
    PSU1_OUTPUT_FAILED=on;                     test_case PSU1_OUTPUT_FAILED=on                        "output_failed $PSU1_OUTPUT_FAILED"                                       "lsenclosurepsu -psu 2 93" "inject test PSU1 output_failed on"
    PSU1_OUTPUT_FAILED=off;                    test_case PSU1_OUTPUT_FAILED=off                       "output_failed $PSU1_OUTPUT_FAILED"                                       "lsenclosurepsu -psu 2 93" "inject test PSU1 output_failed off"
    PSU1_FAN_FAILED=on;                        test_case PSU1_FAN_FAILED=on                           "fan_failed $PSU1_FAN_FAILED"                                             "lsenclosurepsu -psu 2 93" "inject test PSU1 fan_failed on"    
    PSU1_FAN_FAILED=off;                       test_case PSU1_FAN_FAILED=off                          "fan_failed $PSU1_FAN_FAILED"                                             "lsenclosurepsu -psu 2 93" "inject test PSU1 fan_failed off"        
    
    PSU1_REDUNDANT=no;Enclosure_PSU_Status=online,offline;   test_case "PSU1_REDUNDANT=no;Enclosure_PSU_Status=online,offline;"    "redundant $PSU1_REDUNDANT"                       "lsenclosurepsu -psu 2 93" "inject test PSU1 redundant no"    
    PSU1_REDUNDANT=yes;Enclosure_PSU_Status=online,online;   test_case "PSU1_REDUNDANT=yes;Enclosure_PSU_Status=online,online;"    "redundant $PSU1_REDUNDANT"                       "lsenclosurepsu -psu 2 93" "inject test PSU1 redundant yes"    
    
    PSU1_FRU_PART_NUMBER="012345678901";                     test_case "RAW_OUTPUT_START=27;PSU1_FRU_PART_NUMBER=012345678901"     "FRU_part_number $PSU1_FRU_PART_NUMBER"           "lsenclosurepsu -psu 2 93" "inject test PSU1 FRU_part_number"    
    PSU1_FWLEVEL1="0123";                                    test_case "RAW_OUTPUT_START=39;PSU1_FWLEVEL1=0123"                    "firmware_level_1 $PSU1_FWLEVEL1"                 "lsenclosurepsu -psu 2 93" "inject test PSU1 firmware_level_1"    
    PSU1_FRU_IDENTITY="012345678901234";                     test_case "RAW_OUTPUT_START=16;PSU1_FRU_IDENTITY=012345678901234"     "FRU_identity $PSU1_FRU_IDENTITY"                 "lsenclosurepsu -psu 2 93" "inject test PSU1 FRU_identity"    
    PSU1_SWITCH_STATUS="on";                   test_case PSU1_SWITCH_STATUS=on                        "switch_status $PSU1_SWITCH_STATUS"                                       "lsenclosurepsu -psu 2 93" "inject test PSU1 switch_status"    
    PSU1_SWITCH_STATUS="off";                  test_case PSU1_SWITCH_STATUS=off                       "switch_status $PSU1_SWITCH_STATUS"                                       "lsenclosurepsu -psu 2 93" "inject test PSU1 switch_status"    
    PSU1_FAULT_INFO="normal";                  test_case PSU1_FAULT_INFO=normal                       "fault_info $PSU1_FAULT_INFO"                                             "lsenclosurepsu -psu 2 93" "inject test PSU1 fault_info"    
    PSU1_FAULT_INFO="AC_un_v";                 test_case PSU1_FAULT_INFO=AC_un_v                      "fault_info $PSU1_FAULT_INFO"                                             "lsenclosurepsu -psu 2 93" "inject test PSU1 fault_info"    
    PSU1_FAULT_INFO="AC_ov_v";                 test_case PSU1_FAULT_INFO=AC_ov_v                      "fault_info $PSU1_FAULT_INFO"                                             "lsenclosurepsu -psu 2 93" "inject test PSU1 fault_info"    
    PSU1_FAULT_INFO="ov_tm_wn";                test_case PSU1_FAULT_INFO=ov_tm_wn                     "fault_info $PSU1_FAULT_INFO"                                             "lsenclosurepsu -psu 2 93" "inject test PSU1 fault_info"    
    PSU1_FAULT_INFO="AC_un_v:ov_tm_wn";        test_case PSU1_FAULT_INFO=AC_un_v:ov_tm_wn             "fault_info $PSU1_FAULT_INFO"                                             "lsenclosurepsu -psu 2 93" "inject test PSU1 fault_info"    
    PSU1_FAULT_INFO="AC_ov_v:ov_tm_wn";        test_case PSU1_FAULT_INFO=AC_ov_v:ov_tm_wn             "fault_info $PSU1_FAULT_INFO"                                             "lsenclosurepsu -psu 2 93" "inject test PSU1 fault_info"    
    PSU1_FAULT_INFO="ov_tm_fl";                test_case PSU1_FAULT_INFO=ov_tm_fl                     "fault_info $PSU1_FAULT_INFO"                                             "lsenclosurepsu -psu 2 93" "inject test PSU1 fault_info"    
    PSU1_FAULT_INFO="AC_un_v:ov_tm_fl";        test_case PSU1_FAULT_INFO=AC_un_v:ov_tm_fl             "fault_info $PSU1_FAULT_INFO"                                             "lsenclosurepsu -psu 2 93" "inject test PSU1 fault_info"    
    PSU1_FAULT_INFO="AC_ov_v:ov_tm_fl";        test_case PSU1_FAULT_INFO=AC_ov_v:ov_tm_fl             "fault_info $PSU1_FAULT_INFO"                                             "lsenclosurepsu -psu 2 93" "inject test PSU1 fault_info"    
    PSU1_INPUT_POWER="ac";                     test_case PSU1_INPUT_POWER=ac                          "input_power $PSU1_INPUT_POWER"                                           "lsenclosurepsu -psu 2 93" "inject test PSU1 input_power"    
    PSU1_INPUT_POWER="invalid";                test_case PSU1_INPUT_POWER=invalid                     "input_power $PSU1_INPUT_POWER"                                           "lsenclosurepsu -psu 2 93" "inject test PSU1 input_power"    

    PSU1_ALARM_STATUS="normal";                test_case PSU1_ALARM_STATUS=normal                     "alarm_status $PSU1_ALARM_STATUS"                                         "lsenclosurepsu -psu 2 93" "inject test PSU1 alarm_status"    
    PSU1_ALARM_STATUS="warning";               test_case PSU1_ALARM_STATUS=warning                    "alarm_status $PSU1_ALARM_STATUS"                                         "lsenclosurepsu -psu 2 93" "inject test PSU1 alarm_status"    
    PSU1_ALARM_STATUS="critical";              test_case PSU1_ALARM_STATUS=critical                   "alarm_status $PSU1_ALARM_STATUS"                                         "lsenclosurepsu -psu 2 93" "inject test PSU1 alarm_status"    

    PSU1_status=online;                        test_case PSU1_status=online                           "status $PSU1_Status"                                                     "lsenclosurepsu -psu 2 93" "inject test PSU1 status online"
    PSU1_status=offline;                       test_case PSU1_status=offline                          "status $PSU1_Status"                                                     "lsenclosurepsu -psu 2 93" "inject test PSU1 status offline"
    PSU1_input_power_watt=100;                 test_case PSU1_input_power_watt=100                    "input_power_watt $PSU1_input_power_watt"                                 "lsenclosurepsu -psu 2 93" "inject test PSU1 input_power_watt 100"
    PSU1_input_power_watt_over_threshold=100;  test_case PSU1_input_power_watt_over_threshold=100     "input_power_watt_over_threshold $PSU1_input_power_watt_over_threshold"   "lsenclosurepsu -psu 2 93" "inject test PSU1 input_power_watt_over_threshold 100"
    PSU1_input_voltage=100;                    test_case PSU1_input_voltage=100                       "input_voltage $PSU1_input_voltage"                                       "lsenclosurepsu -psu 2 93" "inject test PSU1 PSU1_input_voltage 100"
    PSU1_input_voltage_under_threshold=100;    test_case PSU1_input_voltage_under_threshold=100       "input_voltage_under_threshold $PSU1_input_voltage_under_threshold"       "lsenclosurepsu -psu 2 93" "inject test PSU1 input_voltage_under_threshold 100"
    PSU1_input_voltage_over_threshold=100;     test_case PSU1_input_voltage_over_threshold=100        "input_voltage_over_threshold $PSU1_input_voltage_over_threshold"         "lsenclosurepsu -psu 2 93" "inject test PSU1 input_voltage_over_threshold 100"
    PSU1_output_power_watt=100;                test_case PSU1_output_power_watt=100                   "output_power_watt $PSU1_output_power_watt"                               "lsenclosurepsu -psu 2 93" "inject test PSU1 output_power_watt 100"
    PSU1_output_power_watt_over_threshold=100; test_case PSU1_output_power_watt_over_threshold=100    "output_power_watt_over_threshold $PSU1_output_power_watt_over_threshold" "lsenclosurepsu -psu 2 93" "inject test PSU1 output_power_watt_over_threshold 100"
    PSU1_output_voltage=100;                   test_case PSU1_output_voltage=100                      "output_voltage $PSU1_output_voltage"                                     "lsenclosurepsu -psu 2 93" "inject test PSU1 output_voltage 100"
    PSU1_output_voltage_under_threshold=100;   test_case PSU1_output_voltage_under_threshold=100      "output_voltage_under_threshold $PSU1_output_voltage_under_threshold"     "lsenclosurepsu -psu 2 93" "inject test PSU1 output_voltage_under_threshold 100"
    PSU1_output_voltage_over_threshold=100;    test_case PSU1_output_voltage_over_threshold=100       "output_voltage_over_threshold $PSU1_output_voltage_over_threshold"       "lsenclosurepsu -psu 2 93" "inject test PSU1 output_voltage_over_threshold 100"
    PSU1_temperature=100;                      test_case PSU1_temperature=100                         "temperature $PSU1_temperature"                                           "lsenclosurepsu -psu 2 93" "inject test PSU1 temperature 100"
    PSU1_temperature_warning_threshold=100;    test_case PSU1_temperature_warning_threshold=100       "temperature $PSU1_temperature_warning_threshold"                         "lsenclosurepsu -psu 2 93" "inject test PSU1 temperature_warning_threshold 100"
    PSU1_temperature_critical_threshold=100;   test_case PSU1_temperature_critical_threshold=100      "temperature $PSU1_temperature_critical_threshold"                        "lsenclosurepsu -psu 2 93" "inject test PSU1 temperature_critical_threshold 100"
    PSU1_fantray_speed=100;                    test_case PSU1_fantray_speed=100                       "temperature $PSU1_fantray_speed"                                         "lsenclosurepsu -psu 2 93" "inject test PSU1 fantray_speed 100"
    PSU1_fantray_warning_threshold=100;        test_case PSU1_fantray_warning_threshold=100           "temperature $PSU1_fantray_warning_threshold"                             "lsenclosurepsu -psu 2 93" "inject test PSU1 fantray_warning_threshold 100"
    PSU1_fantray_critical_threshold=100;       test_case PSU1_fantray_critical_threshold=100          "temperature $PSU1_fantray_critical_threshold"                            "lsenclosurepsu -psu 2 93" "inject test PSU1 fantray_critical_threshold 100"

    echo_log "##########################TEST PSU END #################################"
}

function test_case_cmc
{
    echo_log "##########################TEST CMC  ####################################"
    TEST_CASE_ELEMENT_TYPE=CMC

    CMC0_engine_id=3;                   test_case CMC0_engine_id=3         "engine_id $CMC0_engine_id" "lsenclosurecmc -cmc 1 93"           "inject test CMC0 engine_id 3"
    CMC0_slot_id=3;                     test_case CMC0_slot_id=3           "slot_id $CMC0_slot_id" "lsenclosurecmc -cmc 1 93"               "inject test CMC0 slot_id 3"
    CMC0_status=online;                 test_case CMC0_status=online       "status $CMC0_status" "lsenclosurecmc -cmc 1 93"                 "inject test CMC0 status online"
    CMC0_status=offline;                test_case CMC0_status=offline      "status $CMC0_status" "lsenclosurecmc -cmc 1 93"                 "inject test CMC0 status offline"
    CMC0_alarm_status=normal;           test_case CMC0_alarm_status        "alarm_status $CMC0_alarm_status" "lsenclosurecmc -cmc 1 93"     "inject test CMC0 alarm_status normal"
	CMC0_alarm_status="critical under"; test_case CMC0_alarm_status        "alarm_status $CMC0_alarm_status" "lsenclosurecmc -cmc 1 93"     "inject test CMC0 alarm_status critical under"
	CMC0_state=active;                  test_case CMC0_state=active        "state $CMC0_state" "lsenclosurecmc -cmc 1 93"                   "inject test CMC0 state active"
    CMC0_state=inactive;                test_case CMC0_state=inactive      "state $CMC0_state" "lsenclosurecmc -cmc 1 93"                   "inject test CMC0 state inactive"
	CMC0_hb_switch=on;                  test_case CMC0_hb_switch=on        "hb_switch $CMC0_hb_switch" "lsenclosurecmc -cmc 1 93"           "inject test CMC0 hb_switch on"
    CMC0_hb_switch=off;                 test_case CMC0_hb_switch=off       "hb_switch $CMC0_hb_switch" "lsenclosurecmc -cmc 1 93"           "inject test CMC0 hb_switch off"
    CMC0_hb_status=alive;               test_case CMC0_hb_status=alive     "hb_status $CMC0_hb_status" "lsenclosurecmc -cmc 1 93"           "inject test CMC0 hb_status alive"
    CMC0_hb_status=broken;              test_case CMC0_hb_status=broken    "hb_status $CMC0_hb_status" "lsenclosurecmc -cmc 1 93"           "inject test CMC0 hb_status broken"
    CMC0_hb_speed=3;                    test_case CMC0_hb_speed=3          "hb_speed $CMC0_hb_speed" "lsenclosurecmc -cmc 1 93"             "inject test CMC0 hb_speed 3"
    CMC0_firmware_level=0.68;           test_case CMC0_firmware_level=0.68 "firmware_level $CMC0_firmware_level" "lsenclosurecmc -cmc 1 93" "inject test CMC0 firmware_level 0.68"
	                                   
    CMC1_engine_id=3;                   test_case CMC1_engine_id=3         "engine_id $CMC1_engine_id" "lsenclosurecmc -cmc 2 93"           "inject test CMC1 engine_id 3"
    CMC1_slot_id=3;                     test_case CMC1_slot_id=3           "slot_id $CMC1_slot_id" "lsenclosurecmc -cmc 2 93"               "inject test CMC1 slot_id 3"
    CMC1_status=online;                 test_case CMC1_status=online       "status $CMC1_status" "lsenclosurecmc -cmc 2 93"                 "inject test CMC1 status online"
    CMC1_status=offline;                test_case CMC1_status=offline      "status $CMC1_status" "lsenclosurecmc -cmc 2 93"                 "inject test CMC1 status offline"
    CMC1_alarm_status=normal;           test_case CMC1_alarm_status        "alarm_status $CMC1_alarm_status" "lsenclosurecmc -cmc 2 93"     "inject test CMC1 alarm_status normal"
	CMC1_alarm_status="critical under"; test_case CMC1_alarm_status        "alarm_status $CMC1_alarm_status" "lsenclosurecmc -cmc 2 93"     "inject test CMC1 alarm_status critical under"
    CMC1_state=active;                  test_case CMC1_state=active        "state $CMC1_state" "lsenclosurecmc -cmc 2 93"                   "inject test CMC1 state active"
    CMC1_state=inactive;                test_case CMC1_state=inactive      "state $CMC1_state" "lsenclosurecmc -cmc 2 93"                   "inject test CMC0 state inactive"
	CMC1_hb_switch=off;                 test_case CMC1_hb_switch=off       "hb_switch $CMC1_hb_switch" "lsenclosurecmc -cmc 2 93"           "inject test CMC1 hb_switch off"
    CMC1_hb_switch=on;                  test_case CMC1_hb_switch=on        "hb_switch $CMC1_hb_switch" "lsenclosurecmc -cmc 2 93"           "inject test CMC1 hb_switch on"
    CMC1_hb_status=alive;               test_case CMC1_hb_status=alive     "hb_status $CMC1_hb_status" "lsenclosurecmc -cmc 2 93"           "inject test CMC1 hb_status alive"
    CMC1_hb_status=broken;              test_case CMC1_hb_status=broken    "hb_status $CMC1_hb_status" "lsenclosurecmc -cmc 2 93"           "inject test CMC1 hb_status broken"
    CMC1_hb_speed=3;                    test_case CMC1_hb_speed=3          "hb_speed $CMC1_hb_speed" "lsenclosurecmc -cmc 2 93"             "inject test CMC1 hb_speed 3"
    CMC1_firmware_level=0.68;           test_case CMC1_firmware_level=0.68 "firmware_level $CMC1_firmware_level" "lsenclosurecmc -cmc 2 93" "inject test CMC1 firmware_level 0.68"
    
    TEST_CASE_ELEMENT_TYPE=""
    echo_log "##########################TEST CMC END ####################################"
}

function test_case_temperature
{
    echo_log "##########################TEST TEMPERATURE  ####################################"
    TEST_CASE_ELEMENT_TYPE=TEMPERATURE

    SATA_SSD_Temp_alarm_status=normal;          test_case SATA_SSD_Temp_alarm_status=normal         "SATA SSD Temp+alarm_status+$SATA_SSD_Temp_alarm_status"             "svcinfo lsenclosuretemperature"  "inject test SATA SSD Temp alarm_status"
    SATA_SSD_Temp_alarm_status=warning;         test_case SATA_SSD_Temp_alarm_status=warning        "SATA SSD Temp+alarm_status+$SATA_SSD_Temp_alarm_status"            "svcinfo lsenclosuretemperature"  "inject test SATA SSD Temp alarm_status"
    #SATA_SSD_Temp_alarm_status=critical;        test_case SATA_SSD_Temp_alarm_status=critical       "SATA SSD Temp+alarm_status+$SATA_SSD_Temp_alarm_status"           "svcinfo lsenclosuretemperature"  "inject test SATA SSD Temp alarm_status"
    CPU0_Temp_alarm_status=normal;              test_case CPU0_Temp_alarm_status=normal             "CPU0 Temp+alarm_status+$CPU0_Temp_alarm_status"                 "svcinfo lsenclosuretemperature"  "inject test CPU0 Temp alarm_status"
    CPU0_Temp_alarm_status=warning;             test_case CPU0_Temp_alarm_status=warning            "CPU0 Temp+alarm_status+$CPU0_Temp_alarm_status"                  "svcinfo lsenclosuretemperature"  "inject test CPU0 Temp alarm_status"
    #CPU0_Temp_alarm_status=critical;            test_case CPU0_Temp_alarm_status=critical           "CPU0 Temp+alarm_status+$CPU0_Temp_alarm_status"                  "svcinfo lsenclosuretemperature"  "inject test CPU0 Temp alarm_status"
    CPU1_Temp_alarm_status=normal;              test_case CPU1_Temp_alarm_status=normal             "CPU1 Temp+alarm_status+$CPU1_Temp_alarm_status"                  "svcinfo lsenclosuretemperature"  "inject test CPU1 Temp alarm_status"
    CPU1_Temp_alarm_status=warning;             test_case CPU1_Temp_alarm_status=warning            "CPU1 Temp+alarm_status+$CPU1_Temp_alarm_status"                  "svcinfo lsenclosuretemperature"  "inject test CPU1 Temp alarm_status"
    #CPU1_Temp_alarm_status=critical;            test_case CPU1_Temp_alarm_status=critical           "CPU1 Temp+alarm_status+$CPU1_Temp_alarm_status"                  "svcinfo lsenclosuretemperature"  "inject test CPU1 Temp alarm_status"
    CPU0_VR_Temp_alarm_status=normal;           test_case CPU0_VR_Temp_alarm_status=normal          "CPU0 VR Temp+alarm_status+$CPU0_VR_Temp_alarm_status"               "svcinfo lsenclosuretemperature"  "inject test CPU0 VR Temp alarm_status"
    CPU0_VR_Temp_alarm_status=warning;          test_case CPU0_VR_Temp_alarm_status=warning         "CPU0 VR Temp+alarm_status+$CPU0_VR_Temp_alarm_status"               "svcinfo lsenclosuretemperature"  "inject test CPU0 VR Temp alarm_status"
    #CPU0_VR_Temp_alarm_status=critical;         test_case CPU0_VR_Temp_alarm_status=critical        "CPU0 VR Temp+alarm_status+$CPU0_VR_Temp_alarm_status"               "svcinfo lsenclosuretemperature"  "inject test CPU0 VR Temp alarm_status"
    CPU1_VR_Temp_alarm_status=normal;           test_case CPU1_VR_Temp_alarm_status=normal          "CPU1 VR Temp+alarm_status+$CPU1_VR_Temp_alarm_status"               "svcinfo lsenclosuretemperature"  "inject test CPU1 VR Temp alarm_status"
    CPU1_VR_Temp_alarm_status=warning;          test_case CPU1_VR_Temp_alarm_status=warning         "CPU1 VR Temp+alarm_status+$CPU1_VR_Temp_alarm_status"               "svcinfo lsenclosuretemperature"  "inject test CPU1 VR Temp alarm_status"
    #CPU1_VR_Temp_alarm_status=critical;         test_case CPU1_VR_Temp_alarm_status=critical        "CPU1 VR Temp+alarm_status+$CPU1_VR_Temp_alarm_status"               "svcinfo lsenclosuretemperature"  "inject test CPU1 VR Temp alarm_status"
    PCIE_SSD_Temp_alarm_status=normal;          test_case PCIE_SSD_Temp_alarm_status=normal         "PCIE SSD Temp+alarm_status+$PCIE_SSD_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test PCIE SSD Temp alarm_status"
    PCIE_SSD_Temp_alarm_status=warning;         test_case PCIE_SSD_Temp_alarm_status=warning        "PCIE SSD Temp+alarm_status+$PCIE_SSD_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test PCIE SSD Temp alarm_status"
    #PCIE_SSD_Temp_alarm_status=critical;        test_case PCIE_SSD_Temp_alarm_status=critical       "PCIE SSD Temp+alarm_status+$PCIE_SSD_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test PCIE SSD Temp alarm_status"
    PCIE_Zone_Temp_alarm_status=normal;         test_case PCIE_Zone_Temp_alarm_status=normal        "PCIE Zone Temp+alarm_status+$PCIE_Zone_Temp_alarm_status"             "svcinfo lsenclosuretemperature"  "inject test PCIE Zone Temp alarm_status"
    PCIE_Zone_Temp_alarm_status=warning;        test_case PCIE_Zone_Temp_alarm_status=warning       "PCIE Zone Temp+alarm_status+$PCIE_Zone_Temp_alarm_status"            "svcinfo lsenclosuretemperature"  "inject test PCIE Zone Temp alarm_status"
    #PCIE_Zone_Temp_alarm_status=critical;        test_case PCIE_Zone_Temp_alarm_status=critical      "PCIE Zone Temp+alarm_status+$PCIE_Zone_Temp_alarm_status"            "svcinfo lsenclosuretemperature"  "inject test PCIE Zone Temp alarm_status"
    PLX8733_Temp_alarm_status=normal;            test_case PLX8733_Temp_alarm_status=normal          "PLX8733 Temp+alarm_status+$PLX8733_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test PLX8733 Temp alarm_status"
    PLX8733_Temp_alarm_status=warning;           test_case PLX8733_Temp_alarm_status=warning         "PLX8733 Temp+alarm_status+$PLX8733_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test PLX8733 Temp alarm_status"
    #PLX8733_Temp_alarm_status=critical;          test_case PLX8733_Temp_alarm_status=critical        "PLX8733 Temp+alarm_status+$PLX8733_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test PLX8733 Temp alarm_status"
    PLX8796_Temp_alarm_status=normal;            test_case PLX8796_Temp_alarm_status=normal          "PLX8796 Temp+alarm_status+$PLX8796_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test PLX8796 Temp alarm_status"
    PLX8796_Temp_alarm_status=warning;           test_case PLX8796_Temp_alarm_status=warning         "PLX8796 Temp+alarm_status+$PLX8796_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test PLX8796 Temp alarm_status"
    #PLX8796_Temp_alarm_status=critical;          test_case PLX8796_Temp_alarm_status=critical        "PLX8796 Temp+alarm_status+$PLX8796_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test PLX8796 Temp alarm_status"
    PCH_Temp_alarm_status=normal;                test_case PCH_Temp_alarm_status=normal              "PCH Temp+alarm_status+$PCH_Temp_alarm_status"                  "svcinfo lsenclosuretemperature"  "inject test PCH Temp alarm_status"
    PCH_Temp_alarm_status=warning;               test_case PCH_Temp_alarm_status=warning             "PCH Temp+alarm_status+$PCH_Temp_alarm_status"                  "svcinfo lsenclosuretemperature"  "inject test PCH Temp alarm_status"
    #PCH_Temp_alarm_status=critical;              test_case PCH_Temp_alarm_status=critical            "PCH Temp+alarm_status+$PCH_Temp_alarm_status"                  "svcinfo lsenclosuretemperature"  "inject test PCH Temp alarm_status"
    DIMM_AB_Temp_alarm_status=normal;            test_case DIMM_AB_Temp_alarm_status=normal          "DIMM AB Temp+alarm_status+$DIMM_AB_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test DIMM AB Temp alarm_status"
    DIMM_AB_Temp_alarm_status=warning;           test_case DIMM_AB_Temp_alarm_status=warning         "DIMM AB Temp+alarm_status+$DIMM_AB_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test DIMM AB Temp alarm_status"
    #DIMM_AB_Temp_alarm_status=critical;          test_case DIMM_AB_Temp_alarm_status=critical        "DIMM AB Temp+alarm_status+$DIMM_AB_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test DIMM AB Temp alarm_status"
    DIMM_CD_Temp_alarm_status=normal;            test_case DIMM_CD_Temp_alarm_status=normal          "DIMM CD Temp+alarm_status+$DIMM_CD_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test DIMM CD Temp alarm_status"
    DIMM_CD_Temp_alarm_status=warning;           test_case DIMM_CD_Temp_alarm_status=warning         "DIMM CD Temp+alarm_status+$DIMM_CD_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test DIMM CD Temp alarm_status"
    #DIMM_CD_Temp_alarm_status=critical;          test_case DIMM_CD_Temp_alarm_status=critical        "DIMM CD Temp+alarm_status+$DIMM_CD_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test DIMM CD Temp alarm_status"
    DIMM_EF_Temp_alarm_status=normal;            test_case DIMM_EF_Temp_alarm_status=normal          "DIMM EF Temp+alarm_status+$DIMM_EF_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test DIMM EF Temp alarm_status"
    DIMM_EF_Temp_alarm_status=warning;           test_case DIMM_EF_Temp_alarm_status=warning         "DIMM EF Temp+alarm_status+$DIMM_EF_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test DIMM EF Temp alarm_status"
    #DIMM_EF_Temp_alarm_status=critical;          test_case DIMM_EF_Temp_alarm_status=critical        "DIMM EF Temp+alarm_status+$DIMM_EF_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test DIMM EF Temp alarm_status"
    DIMM_GH_Temp_alarm_status=normal;            test_case DIMM_GH_Temp_alarm_status=normal          "DIMM GH Temp+alarm_status+$DIMM_GH_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test DIMM GH Temp alarm_status"
    DIMM_GH_Temp_alarm_status=warning;           test_case DIMM_GH_Temp_alarm_status=warning         "DIMM GH Temp+alarm_status+$DIMM_GH_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test DIMM GH Temp alarm_status"
    #DIMM_GH_Temp_alarm_status=critical;          test_case DIMM_GH_Temp_alarm_status=critical        "DIMM GH Temp+alarm_status+$DIMM_GH_Temp_alarm_status"              "svcinfo lsenclosuretemperature"  "inject test DIMM GH Temp alarm_status"
    DIMM_AB_VR_Temp_alarm_status=normal;         test_case DIMM_AB_VR_Temp_alarm_status=normal       "DIMM AB VR Temp+alarm_status+$DIMM_AB_VR_Temp_alarm_status"           "svcinfo lsenclosuretemperature"  "inject test DIMM AB VR Temp alarm_status"
    DIMM_AB_VR_Temp_alarm_status=warning;        test_case DIMM_AB_VR_Temp_alarm_status=warning      "DIMM AB VR Temp+alarm_status+$DIMM_AB_VR_Temp_alarm_status"           "svcinfo lsenclosuretemperature"  "inject test DIMM AB VR Temp alarm_status"
    #DIMM_AB_VR_Temp_alarm_status=critical;       test_case DIMM_AB_VR_Temp_alarm_status=critical     "DIMM AB VR Temp+alarm_status+$DIMM_AB_VR_Temp_alarm_status"           "svcinfo lsenclosuretemperature"  "inject test DIMM AB VR Temp alarm_status"
    DIMM_CD_VR_Temp_alarm_status=normal;         test_case DIMM_CD_VR_Temp_alarm_status=normal       "DIMM CD VR Temp+alarm_status+$DIMM_CD_VR_Temp_alarm_status"           "svcinfo lsenclosuretemperature"  "inject test DIMM CD VR Temp alarm_status"
    DIMM_CD_VR_Temp_alarm_status=warning;        test_case DIMM_CD_VR_Temp_alarm_status=warning      "DIMM CD VR Temp+alarm_status+$DIMM_CD_VR_Temp_alarm_status"           "svcinfo lsenclosuretemperature"  "inject test DIMM CD VR Temp alarm_status"
    #DIMM_CD_VR_Temp_alarm_status=critical;       test_case DIMM_CD_VR_Temp_alarm_status=critical     "DIMM CD VR Temp+alarm_status+$DIMM_CD_VR_Temp_alarm_status"           "svcinfo lsenclosuretemperature"  "inject test DIMM CD VR Temp alarm_status"
    DIMM_EF_VR_Temp_alarm_status=normal;         test_case DIMM_EF_VR_Temp_alarm_status=normal       "DIMM EF VR Temp+alarm_status+$DIMM_EF_VR_Temp_alarm_status"           "svcinfo lsenclosuretemperature"  "inject test DIMM EF VR Temp alarm_status"
    DIMM_EF_VR_Temp_alarm_status=warning;        test_case DIMM_EF_VR_Temp_alarm_status=warning      "DIMM EF VR Temp+alarm_status+$DIMM_EF_VR_Temp_alarm_status"           "svcinfo lsenclosuretemperature"  "inject test DIMM EF VR Temp alarm_status"
    #DIMM_EF_VR_Temp_alarm_status=critical;       test_case DIMM_EF_VR_Temp_alarm_status=critical     "DIMM EF VR Temp+alarm_status+$DIMM_EF_VR_Temp_alarm_status"           "svcinfo lsenclosuretemperature"  "inject test DIMM EF VR Temp alarm_status"
    DIMM_GH_VR_Temp_alarm_status=normal;         test_case DIMM_GH_VR_Temp_alarm_status=normal       "DIMM GH VR Temp+alarm_status+$DIMM_GH_VR_Temp_alarm_status"           "svcinfo lsenclosuretemperature"  "inject test DIMM GH VR Temp alarm_status"
    DIMM_GH_VR_Temp_alarm_status=warning;        test_case DIMM_GH_VR_Temp_alarm_status=warning      "DIMM GH VR Temp+alarm_status+$DIMM_GH_VR_Temp_alarm_status"           "svcinfo lsenclosuretemperature"  "inject test DIMM GH VR Temp alarm_status"
    #DIMM_GH_VR_Temp_alarm_status=critical;       test_case DIMM_GH_VR_Temp_alarm_status=critical     "DIMM GH VR Temp+alarm_status+$DIMM_GH_VR_Temp_alarm_status"           "svcinfo lsenclosuretemperature"  "inject test DIMM GH VR Temp alarm_status"
    Inlet_Temp_alarm_status=normal;              test_case Inlet_Temp_alarm_status=normal            "Inlet Temp+alarm_status+$Inlet_Temp_alarm_status"                "svcinfo lsenclosuretemperature"  "inject test Inlet Temp alarm_status"
    Inlet_Temp_alarm_status=warning;             test_case Inlet_Temp_alarm_status=warning           "Inlet Temp+alarm_status+$Inlet_Temp_alarm_status"                "svcinfo lsenclosuretemperature"  "inject test Inlet Temp alarm_status"
    #Inlet_Temp_alarm_status=critical;            test_case Inlet_Temp_alarm_status=critical          "Inlet Temp+alarm_status+$Inlet_Temp_alarm_status"                "svcinfo lsenclosuretemperature"  "inject test Inlet Temp alarm_status"
    CMC_DB_Temp_alarm_status=normal;             test_case CMC_DB_Temp_alarm_status=normal           "CMC DB Temp+alarm_status+$CMC_DB_Temp_alarm_status"               "svcinfo lsenclosuretemperature"  "inject test CMC DB Temp alarm_status"
    CMC_DB_Temp_alarm_status=warning;            test_case CMC_DB_Temp_alarm_status=warning          "CMC DB Temp+alarm_status+$CMC_DB_Temp_alarm_status"               "svcinfo lsenclosuretemperature"  "inject test CMC DB Temp alarm_status"
    #CMC_DB_Temp_alarm_status=critical;           test_case CMC_DB_Temp_alarm_status=critical         "CMC DB Temp+alarm_status+$CMC_DB_Temp_alarm_status"               "svcinfo lsenclosuretemperature"  "inject test CMC DB Temp alarm_status"


    PLX8733_temperature=50;                 test_case  PLX8733_temperature=50                     "PLX8733 Temp+temperature+$PLX8733_temperature.000000"                "svcinfo lsenclosuretemperature" "inject test PLX8733 temperature"                                                                                                                             
    PLX8733_temp_warning_threshold=90;      test_case  PLX8733_temp_warning_threshold=90          "PLX8733 Temp+warning_threshold+$PLX8733_temp_warning_threshold.000000"            "svcinfo lsenclosuretemperature" "inject test PLX8733 temp_warning_threshold"
    PLX8733_temp_critical_threshold=99;    test_case  PLX8733_temp_critical_threshold=99         "PLX8733 Temp+critical_threshold+$PLX8733_temp_critical_threshold.000000"           "svcinfo lsenclosuretemperature" "inject test PLX8733 temp_critical_threshold"
    PLX8796_temperature=50;                 test_case  PLX8796_temperature=50                     "PLX8796 Temp+temperature+$PLX8796_temperature.000000"             "svcinfo lsenclosuretemperature" "inject test PLX8796 temperature"            
    PLX8796_temp_warning_threshold=90;      test_case  PLX8796_temp_warning_threshold=90          "PLX8796 Temp+warning_threshold+$PLX8796_temp_warning_threshold.000000"             "svcinfo lsenclosuretemperature" "inject test PLX8796 temp_warning_threshold"
    PLX8796_temp_critical_threshold=99;     test_case  PLX8796_temp_critical_threshold=99         "PLX8796 Temp+critical_threshold+$PLX8796_temp_critical_threshold.000000"             "svcinfo lsenclosuretemperature" "inject test PLX8796 temp_critical_threshold"
    CPU0_temperature=50;                    test_case  CPU0_temperature=50                        "CPU0 Temp+temperature+$CPU0_temperature.000000"                "svcinfo lsenclosuretemperature" "inject test CPU0 temperature"            
    CPU0_temp_warning_threshold=90;         test_case  CPU0_temp_warning_threshold=90             "CPU0 Temp+warning_threshold+$CPU0_temp_warning_threshold.000000"                "svcinfo lsenclosuretemperature" "inject test CPU0 temp_warning_threshold"
    CPU0_temp_critical_threshold=99;        test_case  CPU0_temp_critical_threshold=99            "CPU0 Temp+critical_threshold+$CPU0_temp_critical_threshold.000000"                "svcinfo lsenclosuretemperature" "inject test CPU0 temp_critical_threshold"
    CPU1_temperature=50;                    test_case  CPU1_temperature=50                        "CPU1 Temp+temperature+$CPU1_temperature.000000"                "svcinfo lsenclosuretemperature" "inject test CPU1 temperature"            
    CPU1_temp_warning_threshold=90;         test_case  CPU1_temp_warning_threshold=90             "CPU1 Temp+warning_threshold+$CPU1_temp_warning_threshold.000000"                "svcinfo lsenclosuretemperature" "inject test CPU1 temp_warning_threshold"
    CPU1_temp_critical_threshold=99;        test_case  CPU1_temp_critical_threshold=99            "CPU1 Temp+critical_threshold+$CPU1_temp_critical_threshold.000000"                "svcinfo lsenclosuretemperature" "inject test CPU1 temp_critical_threshold"
    CPU0_VR_temperature=50;                 test_case  CPU0_VR_temperature=50                     "CPU0 VR Temp+temperature+$CPU0_VR_temperature.000000"             "svcinfo lsenclosuretemperature" "inject test CPU0 VR temperature"            
    CPU0_VR_temp_warning_threshold=90;      test_case  CPU0_VR_temp_warning_threshold=90          "CPU0 VR Temp+warning_threshold+$CPU0_VR_temp_warning_threshold.000000"             "svcinfo lsenclosuretemperature" "inject test CPU0 VR temp_warning_threshold"
    CPU0_VR_temp_critical_threshold=99;     test_case  CPU0_VR_temp_critical_threshold=99         "CPU0 VR Temp+critical_threshold+$CPU0_VR_temp_critical_threshold.000000"             "svcinfo lsenclosuretemperature" "inject test CPU0 VR temp_critical_threshold"
    CPU1_VR_temperature=50;                 test_case  CPU1_VR_temperature=50                     "CPU1 VR Temp+temperature+$CPU1_VR_temperature.000000"             "svcinfo lsenclosuretemperature" "inject test CPU1 VR temperature"            
    CPU1_VR_temp_warning_threshold=90;      test_case  CPU1_VR_temp_warning_threshold=90          "CPU1 VR Temp+warning_threshold+$CPU1_VR_temp_warning_threshold.000000"             "svcinfo lsenclosuretemperature" "inject test CPU1 VR temp_warning_threshold"
    CPU1_VR_temp_critical_threshold=99;     test_case  CPU1_VR_temp_critical_threshold=99         "CPU1 VR Temp+critical_threshold+$CPU1_VR_temp_critical_threshold.000000"             "svcinfo lsenclosuretemperature" "inject test CPU1 VR temp_critical_threshold"
    DIMM_AB_temperature=50;                 test_case  DIMM_AB_temperature=50                     "DIMM AB Temp+temperature+$DIMM_AB_temperature.000000"             "svcinfo lsenclosuretemperature" "inject test DIMM AB temperature"            
    DIMM_AB_temp_warning_threshold=90;      test_case  DIMM_AB_temp_warning_threshold=90          "DIMM AB Temp+warning_threshold+$DIMM_AB_temp_warning_threshold.000000"             "svcinfo lsenclosuretemperature" "inject test DIMM AB temp_warning_threshold"
    DIMM_AB_temp_critical_threshold=99;     test_case  DIMM_AB_temp_critical_threshold=99         "DIMM AB Temp+critical_threshold+$DIMM_AB_temp_critical_threshold.000000"             "svcinfo lsenclosuretemperature" "inject test DIMM AB temp_critical_threshold"
    DIMM_CD_temperature=50;                 test_case  DIMM_CD_temperature=50                     "DIMM CD Temp+temperature+$DIMM_CD_temperature.000000"             "svcinfo lsenclosuretemperature" "inject test DIMM CD temperature"            
    DIMM_CD_temp_warning_threshold=90;      test_case  DIMM_CD_temp_warning_threshold=90          "DIMM CD Temp+warning_threshold+$DIMM_CD_temp_warning_threshold.000000"             "svcinfo lsenclosuretemperature" "inject test DIMM CD temp_warning_threshold"
    DIMM_CD_temp_critical_threshold=99;     test_case  DIMM_CD_temp_critical_threshold=99         "DIMM CD Temp+critical_threshold+$DIMM_CD_temp_critical_threshold.000000"             "svcinfo lsenclosuretemperature" "inject test DIMM CD temp_critical_threshold"
    DIMM_EF_temperature=50;                 test_case  DIMM_EF_temperature=50                     "DIMM EF Temp+temperature+$DIMM_EF_temperature.000000"             "svcinfo lsenclosuretemperature" "inject test DIMM EF temperature"            
    DIMM_EF_temp_warning_threshold=90;      test_case  DIMM_EF_temp_warning_threshold=90          "DIMM EF Temp+warning_threshold+$DIMM_EF_temp_warning_threshold.000000"             "svcinfo lsenclosuretemperature" "inject test DIMM EF temp_warning_threshold"
    DIMM_EF_temp_critical_threshold=99;     test_case  DIMM_EF_temp_critical_threshold=99         "DIMM EF Temp+critical_threshold+$DIMM_EF_temp_critical_threshold.000000"             "svcinfo lsenclosuretemperature" "inject test DIMM EF temp_critical_threshold"
    DIMM_GH_temperature=50;                 test_case  DIMM_GH_temperature=50                     "DIMM GH Temp+temperature+$DIMM_GH_temperature.000000"             "svcinfo lsenclosuretemperature" "inject test DIMM GH temperature"            
    DIMM_GH_temp_warning_threshold=90;      test_case  DIMM_GH_temp_warning_threshold=90          "DIMM GH Temp+warning_threshold+$DIMM_GH_temp_warning_threshold.000000"             "svcinfo lsenclosuretemperature" "inject test DIMM GH temp_warning_threshold"
    DIMM_GH_temp_critical_threshold=99;     test_case  DIMM_GH_temp_critical_threshold=99         "DIMM GH Temp+critical_threshold+$DIMM_GH_temp_critical_threshold.000000"             "svcinfo lsenclosuretemperature" "inject test DIMM GH temp_critical_threshold"
    DIMM_AB_VR_temperature=50;              test_case  DIMM_AB_VR_temperature=50                  "DIMM AB VR Temp+temperature+$DIMM_AB_VR_temperature.000000"          "svcinfo lsenclosuretemperature" "inject test DIMM AB VR temperature"            
    DIMM_AB_VR_temp_warning_threshold=90;   test_case  DIMM_AB_VR_temp_warning_threshold=90       "DIMM AB VR Temp+warning_threshold+$DIMM_AB_VR_temp_warning_threshold.000000"          "svcinfo lsenclosuretemperature" "inject test DIMM AB VR temp_warning_threshold"
    DIMM_AB_VR_temp_critical_threshold=99;  test_case  DIMM_AB_VR_temp_critical_threshold=99      "DIMM AB VR Temp+critical_threshold+$DIMM_AB_VR_temp_critical_threshold.000000"          "svcinfo lsenclosuretemperature" "inject test DIMM AB VR temp_critical_threshold"
    DIMM_CD_VR_temperature=50;              test_case  DIMM_CD_VR_temperature=50                  "DIMM CD VR Temp+temperature+$DIMM_CD_VR_temperature.000000"          "svcinfo lsenclosuretemperature" "inject test DIMM CD VR temperature"            
    DIMM_CD_VR_temp_warning_threshold=90;   test_case  DIMM_CD_VR_temp_warning_threshold=90       "DIMM CD VR Temp+warning_threshold+$DIMM_CD_VR_temp_warning_threshold.000000"          "svcinfo lsenclosuretemperature" "inject test DIMM CD VR temp_warning_threshold"
    DIMM_CD_VR_temp_critical_threshold=99;  test_case  DIMM_CD_VR_temp_critical_threshold=99      "DIMM CD VR Temp+critical_threshold+$DIMM_CD_VR_temp_critical_threshold.000000"          "svcinfo lsenclosuretemperature" "inject test DIMM CD VR temp_critical_threshold"
    DIMM_EF_VR_temperature=50;              test_case  DIMM_EF_VR_temperature=50                  "DIMM EF VR Temp+temperature+$DIMM_EF_VR_temperature.000000"          "svcinfo lsenclosuretemperature" "inject test DIMM EF VR temperature"            
    DIMM_EF_VR_temp_warning_threshold=90;   test_case  DIMM_EF_VR_temp_warning_threshold=90       "DIMM EF VR Temp+warning_threshold+$DIMM_EF_VR_temp_warning_threshold.000000"          "svcinfo lsenclosuretemperature" "inject test DIMM EF VR temp_warning_threshold"
    DIMM_EF_VR_temp_critical_threshold=99;  test_case  DIMM_EF_VR_temp_critical_threshold=99      "DIMM EF VR Temp+critical_threshold+$DIMM_EF_VR_temp_critical_threshold.000000"          "svcinfo lsenclosuretemperature" "inject test DIMM EF VR temp_critical_threshold"
    DIMM_GH_VR_temperature=50;              test_case  DIMM_GH_VR_temperature=50                  "DIMM GH VR Temp+temperature+$DIMM_GH_VR_temperature.000000"          "svcinfo lsenclosuretemperature" "inject test DIMM GH VR temperature"            
    DIMM_GH_VR_temp_warning_threshold=90;   test_case  DIMM_GH_VR_temp_warning_threshold=90       "DIMM GH VR Temp+warning_threshold+$DIMM_GH_VR_temp_warning_threshold.000000"          "svcinfo lsenclosuretemperature" "inject test DIMM GH VR temp_warning_threshold"
    DIMM_GH_VR_temp_critical_threshold=99;  test_case  DIMM_GH_VR_temp_critical_threshold=99      "DIMM GH VR Temp+critical_threshold+$DIMM_GH_VR_temp_critical_threshold.000000"          "svcinfo lsenclosuretemperature" "inject test DIMM GH VR temp_critical_threshold"
    PCH_temperature=50;                     test_case  PCH_temperature=50                         "PCH Temp+temperature+$PCH_temperature.000000"                 "svcinfo lsenclosuretemperature" "inject test PCH temperature"            
    PCH_temp_warning_threshold=90;          test_case  PCH_temp_warning_threshold=90              "PCH Temp+warning_threshold+$PCH_temp_warning_threshold.000000"                 "svcinfo lsenclosuretemperature" "inject test PCH temp_warning_threshold"
    PCH_temp_critical_threshold=99;         test_case  PCH_temp_critical_threshold=99             "PCH Temp+critical_threshold+$PCH_temp_critical_threshold.000000"                 "svcinfo lsenclosuretemperature" "inject test PCH temp_critical_threshold"
    SATA_SSD_temperature=50;                test_case  SATA_SSD_temperature=50                    "SATA SSD Temp+temperature+$SATA_SSD_temperature.000000"            "svcinfo lsenclosuretemperature" "inject test SATA SSD temperature"            
    SATA_SSD_temp_warning_threshold=90;     test_case  SATA_SSD_temp_warning_threshold=90         "SATA SSD Temp+warning_threshold+$SATA_SSD_temp_warning_threshold.000000"            "svcinfo lsenclosuretemperature" "inject test SATA SSD temp_warning_threshold"
    SATA_SSD_temp_critical_threshold=99;    test_case  SATA_SSD_temp_critical_threshold=99        "SATA SSD Temp+critical_threshold+$SATA_SSD_temp_critical_threshold.000000"            "svcinfo lsenclosuretemperature" "inject test SATA SSD temp_critical_threshold"
    PCIE_SSD_temperature=50;                test_case  PCIE_SSD_temperature=50                    "PCIE SSD Temp+temperature+$PCIE_SSD_temperature.000000"            "svcinfo lsenclosuretemperature" "inject test PCIE SSD temperature"            
    PCIE_SSD_temp_warning_threshold=90;     test_case  PCIE_SSD_temp_warning_threshold=90         "PCIE SSD Temp+warning_threshold+$PCIE_SSD_temp_warning_threshold.000000"            "svcinfo lsenclosuretemperature" "inject test PCIE SSD temp_warning_threshold"
    PCIE_SSD_temp_critical_threshold=99;    test_case  PCIE_SSD_temp_critical_threshold=99        "PCIE SSD Temp+critical_threshold+$PCIE_SSD_temp_critical_threshold.000000"            "svcinfo lsenclosuretemperature" "inject test PCIE SSD temp_critical_threshold"
    PCIE_Zone_temperature=50;               test_case  PCIE_Zone_temperature=50                   "PCIE Zone Temp+temperature+$PCIE_Zone_temperature.000000"           "svcinfo lsenclosuretemperature" "inject test PCIE Zone temperature"            
    PCIE_Zone_temp_warning_threshold=90;    test_case  PCIE_Zone_temp_warning_threshold=90        "PCIE Zone Temp+warning_threshold+$PCIE_Zone_temp_warning_threshold.000000"           "svcinfo lsenclosuretemperature" "inject test PCIE Zone temp_warning_threshold"
    PCIE_Zone_temp_critical_threshold=99;   test_case  PCIE_Zone_temp_critical_threshold=99       "PCIE Zone Temp+critical_threshold+$PCIE_Zone_temp_critical_threshold.000000"           "svcinfo lsenclosuretemperature" "inject test PCIE Zone temp_critical_threshold"

    Inlet_temperature=50;                   test_case  Inlet_temperature=50                       "Inlet Temp+temperature+$Inlet_temperature.000000"               "svcinfo lsenclosuretemperature" "inject test Inlet temperature"            
    Inlet_temp_warning_threshold=90;        test_case  Inlet_temp_warning_threshold=90            "Inlet Temp+warning_threshold+$Inlet_temp_warning_threshold.000000"               "svcinfo lsenclosuretemperature" "inject test Inlet temp_warning_threshold"
    Inlet_temp_critical_threshold=99;       test_case  Inlet_temp_critical_threshold=99           "Inlet Temp+critical_threshold+$Inlet_temp_critical_threshold.000000"               "svcinfo lsenclosuretemperature" "inject test Inlet temp_critical_threshold"
    CMC_DB_temperature=50;                  test_case  CMC_DB_temperature=50                      "CMC DB Temp+temperature+$CMC_DB_temperature.000000"              "svcinfo lsenclosuretemperature" "inject test CMC DB temperature"            
    CMC_DB_temp_warning_threshold=90;       test_case  CMC_DB_temp_warning_threshold=90           "CMC DB Temp+warning_threshold+$CMC_DB_temp_warning_threshold.000000"              "svcinfo lsenclosuretemperature" "inject test CMC DB temp_warning_threshold"
    CMC_DB_temp_critical_threshold=99;      test_case  CMC_DB_temp_critical_threshold=99          "CMC DB Temp+critical_threshold+$CMC_DB_temp_critical_threshold.000000"              "svcinfo lsenclosuretemperature" "inject test CMC DB temp_critical_threshold"

    TEST_CASE_ELEMENT_TYPE=""
    echo_log "##########################TEST TEMPERATURE END ####################################"
}

function test_case_voltage
{
    echo_log "##########################TEST VOLTAGE  ####################################"
    TEST_CASE_ELEMENT_TYPE=VOLTAGE
    voltage_12V_Standby_alarm_status=normal;              test_case "voltage_12V_Standby_alarm_status=normal"               "12V Standby+alarm_status+$voltage_12V_Standby_alarm_status"         "svcinfo lsenclosurevoltage"  "inject test 12V Standby alarm_status"
    voltage_12V_Standby_alarm_status="warning under";       test_case "voltage_12V_Standby_alarm_status=\"warning under\""        "12V Standby+alarm_status+$voltage_12V_Standby_alarm_status"         "svcinfo lsenclosurevoltage"  "inject test 12V Standby alarm_status"
    voltage_12V_Standby_alarm_status="critical under";      test_case "voltage_12V_Standby_alarm_status=\"critical under\""       "12V Standby+alarm_status+$voltage_12V_Standby_alarm_status"         "svcinfo lsenclosurevoltage"  "inject test 12V Standby alarm_status"
    voltage_12V_Standby_alarm_status="warning over";        test_case "voltage_12V_Standby_alarm_status=\"warning over\""         "12V Standby+alarm_status+$voltage_12V_Standby_alarm_status"         "svcinfo lsenclosurevoltage"  "inject test 12V Standby alarm_status"
    voltage_12V_Standby_alarm_status="critical over";       test_case "voltage_12V_Standby_alarm_status=\"critical over\""        "12V Standby+alarm_status+$voltage_12V_Standby_alarm_status"         "svcinfo lsenclosurevoltage"  "inject test 12V Standby alarm_status"
    voltage_5V_alarm_status=normal;                       test_case "voltage_5V_alarm_status=normal"                        "5V+alarm_status+$voltage_5V_alarm_status"                  "svcinfo lsenclosurevoltage"  "inject test 5V alarm_status"
    voltage_5V_alarm_status="warning under";                test_case "voltage_5V_alarm_status=\"warning under\""                 "5V+alarm_status+$voltage_5V_alarm_status"                  "svcinfo lsenclosurevoltage"  "inject test 5V alarm_status"
    voltage_5V_alarm_status="critical under";               test_case "voltage_5V_alarm_status=\"critical under\""                "5V+alarm_status+$voltage_5V_alarm_status"                  "svcinfo lsenclosurevoltage"  "inject test 5V alarm_status"
    voltage_5V_alarm_status="warning over";                 test_case "voltage_5V_alarm_status=\"warning over\""                  "5V+alarm_status+$voltage_5V_alarm_status"                  "svcinfo lsenclosurevoltage"  "inject test 5V alarm_status"
    voltage_5V_alarm_status="critical over";                test_case "voltage_5V_alarm_status=\"critical over\""                 "5V+alarm_status+$voltage_5V_alarm_status"                  "svcinfo lsenclosurevoltage"  "inject test 5V alarm_status"
    voltage_3_3V_Standby_alarm_status=normal;             test_case "voltage_3_3V_Standby_alarm_status=normal"              "3.3V Standby+alarm_status+$voltage_3_3V_Standby_alarm_status"        "svcinfo lsenclosurevoltage"  "inject test 3.3V Standby alarm_status"
    voltage_3_3V_Standby_alarm_status="warning under";      test_case "voltage_3_3V_Standby_alarm_status=\"warning under\""       "3.3V Standby+alarm_status+$voltage_3_3V_Standby_alarm_status"        "svcinfo lsenclosurevoltage"  "inject test 3.3V Standby alarm_status"
    voltage_3_3V_Standby_alarm_status="critical under";     test_case "voltage_3_3V_Standby_alarm_status=\"critical under\""      "3.3V Standby+alarm_status+$voltage_3_3V_Standby_alarm_status"        "svcinfo lsenclosurevoltage"  "inject test 3.3V Standby alarm_status"
    voltage_3_3V_Standby_alarm_status="warning over";       test_case "voltage_3_3V_Standby_alarm_status=\"warning over\""        "3.3V Standby+alarm_status+$voltage_3_3V_Standby_alarm_status"        "svcinfo lsenclosurevoltage"  "inject test 3.3V Standby alarm_status"
    voltage_3_3V_Standby_alarm_status="critical over";      test_case "voltage_3_3V_Standby_alarm_status=\"critical over\""       "3.3V Standby+alarm_status+$voltage_3_3V_Standby_alarm_status"        "svcinfo lsenclosurevoltage"  "inject test 3.3V Standby alarm_status"
    voltage_3_3V_alarm_status=normal;                     test_case "voltage_3_3V_alarm_status=normal"                      "3.3V+alarm_status+$voltage_3_3V_alarm_status"                "svcinfo lsenclosurevoltage"  "inject test 3.3V alarm_status"
    voltage_3_3V_alarm_status="warning under";              test_case "voltage_3_3V_alarm_status=\"warning under\""               "3.3V+alarm_status+$voltage_3_3V_alarm_status"                "svcinfo lsenclosurevoltage"  "inject test 3.3V alarm_status"
    voltage_3_3V_alarm_status="critical under";             test_case "voltage_3_3V_alarm_status=\"critical under\""              "3.3V+alarm_status+$voltage_3_3V_alarm_status"                "svcinfo lsenclosurevoltage"  "inject test 3.3V alarm_status"
    voltage_3_3V_alarm_status="warning over";               test_case "voltage_3_3V_alarm_status=\"warning over\""                "3.3V+alarm_status+$voltage_3_3V_alarm_status"                "svcinfo lsenclosurevoltage"  "inject test 3.3V alarm_status"
    voltage_3_3V_alarm_status="critical over";              test_case "voltage_3_3V_alarm_status=\"critical over\""               "3.3V+alarm_status+$voltage_3_3V_alarm_status"                "svcinfo lsenclosurevoltage"  "inject test 3.3V alarm_status"
    voltage_12V_alarm_status=normal;                      test_case "voltage_12V_alarm_status=normal"                       "12V+alarm_status+$voltage_12V_alarm_status"                 "svcinfo lsenclosurevoltage"  "inject test 12V alarm_status"
    voltage_12V_alarm_status="warning under";               test_case "voltage_12V_alarm_status=\"warning under\""                "12V+alarm_status+$voltage_12V_alarm_status"                 "svcinfo lsenclosurevoltage"  "inject test 12V alarm_status"
    voltage_12V_alarm_status="critical under";              test_case "voltage_12V_alarm_status=\"critical under\""               "12V+alarm_status+$voltage_12V_alarm_status"                 "svcinfo lsenclosurevoltage"  "inject test 12V alarm_status"
    voltage_12V_alarm_status="warning over";                test_case "voltage_12V_alarm_status=\"warning over\""                 "12V+alarm_status+$voltage_12V_alarm_status"                 "svcinfo lsenclosurevoltage"  "inject test 12V alarm_status"
    voltage_12V_alarm_status="critical over";               test_case "voltage_12V_alarm_status=\"critical over\""                "12V+alarm_status+$voltage_12V_alarm_status"                 "svcinfo lsenclosurevoltage"  "inject test 12V alarm_status"
    voltage_3V_Battery_alarm_status=normal;               test_case "voltage_3V_Battery_alarm_status=normal"                "3V Battery+alarm_status+$voltage_3V_Battery_alarm_status"          "svcinfo lsenclosurevoltage"  "inject test 3V Battery alarm_status"
    voltage_3V_Battery_alarm_status="warning under";        test_case "voltage_3V_Battery_alarm_status=\"warning under\""         "3V Battery+alarm_status+$voltage_3V_Battery_alarm_status"          "svcinfo lsenclosurevoltage"  "inject test 3V Battery alarm_status"
    voltage_3V_Battery_alarm_status="critical under";       test_case "voltage_3V_Battery_alarm_status=\"critical under\""        "3V Battery+alarm_status+$voltage_3V_Battery_alarm_status"          "svcinfo lsenclosurevoltage"  "inject test 3V Battery alarm_status"
    voltage_3V_Battery_alarm_status="warning over";         test_case "voltage_3V_Battery_alarm_status=\"warning over\""          "3V Battery+alarm_status+$voltage_3V_Battery_alarm_status"          "svcinfo lsenclosurevoltage"  "inject test 3V Battery alarm_status"
    voltage_3V_Battery_alarm_status="critical over";        test_case "voltage_3V_Battery_alarm_status=\"critical over\""         "3V Battery+alarm_status+$voltage_3V_Battery_alarm_status"          "svcinfo lsenclosurevoltage"  "inject test 3V Battery alarm_status"

    voltage_12V_voltage=10;                         test_case  voltage_12V_voltage=10                              "12V+voltage+$voltage_12V_voltage.000000"                                                    "svcinfo lsenclosurevoltage" "inject test 12V voltage"
    voltage_12V_warning_under_threshold=9;          test_case  voltage_12V_warning_under_threshold=9               "12V+warning_under_threshold+$voltage_12V_warning_under_threshold.000000"                      "svcinfo lsenclosurevoltage" "inject test 12V warning_under_threshold"
    voltage_12V_warning_over_threshold=11;          test_case  voltage_12V_warning_over_threshold=11               "12V+warning_over_threshold+$voltage_12V_warning_over_threshold.000000"                      "svcinfo lsenclosurevoltage" "inject test 12V warning_over_threshold"
    voltage_12V_critical_under_threshold=8;         test_case  voltage_12V_critical_under_threshold=8              "12V+critical_under_threshold+$voltage_12V_critical_under_threshold.000000"                     "svcinfo lsenclosurevoltage" "inject test 12V critical_under_threshold"
    voltage_12V_critical_over_threshold=12;         test_case  voltage_12V_critical_over_threshold=12              "12V+critical_over_threshold+$voltage_12V_critical_over_threshold.000000"                     "svcinfo lsenclosurevoltage" "inject test 12V critical_over_threshold"
    voltage_12V_Standby_voltage=10;                 test_case  voltage_12V_Standby_voltage=10                      "12V Standby+voltage+$voltage_12V_Standby_voltage.000000"                                           "svcinfo lsenclosurevoltage" "inject test 12V Standby voltage"
    voltage_12V_Standby_warning_under_threshold=9;  test_case  voltage_12V_Standby_warning_under_threshold=9       "12V Standby+warning_under_threshold+$voltage_12V_Standby_warning_under_threshold.000000"             "svcinfo lsenclosurevoltage" "inject test 12V Standby warning_under_threshold"
    voltage_12V_Standby_warning_over_threshold=11;  test_case  voltage_12V_Standby_warning_over_threshold=11       "12V Standby+warning_over_threshold+$voltage_12V_Standby_warning_over_threshold.000000"               "svcinfo lsenclosurevoltage" "inject test 12V Standby warning_over_threshold"
    voltage_12V_Standby_critical_under_threshold=8; test_case  voltage_12V_Standby_critical_under_threshold=8      "12V Standby+critical_under_threshold+$voltage_12V_Standby_critical_under_threshold.000000"               "svcinfo lsenclosurevoltage" "inject test 12V Standby critical_under_threshold"
    voltage_12V_Standby_critical_over_threshold=12; test_case  voltage_12V_Standby_critical_over_threshold=12      "12V Standby+critical_over_threshold+$voltage_12V_Standby_critical_over_threshold.000000"               "svcinfo lsenclosurevoltage" "inject test 12V Standby critical_over_threshold"
    voltage_5V_voltage=10;                          test_case  voltage_5V_voltage=10                               "5V+voltage+$voltage_5V_voltage.000000"                                                                 "svcinfo lsenclosurevoltage" "inject test 5V voltage"
    voltage_5V_warning_under_threshold=9;           test_case  voltage_5V_warning_under_threshold=9                "5V+warning_under_threshold+$voltage_5V_warning_under_threshold.000000"                                     "svcinfo lsenclosurevoltage" "inject test 5V warning_under_threshold"
    voltage_5V_warning_over_threshold=11;           test_case  voltage_5V_warning_over_threshold=11                "5V+warning_over_threshold+$voltage_5V_warning_over_threshold.000000"                                     "svcinfo lsenclosurevoltage" "inject test 5V warning_over_threshold"
    voltage_5V_critical_under_threshold=8;          test_case  voltage_5V_critical_under_threshold=8               "5V+critical_under_threshold+$voltage_5V_critical_under_threshold.000000"                                     "svcinfo lsenclosurevoltage" "inject test 5V critical_under_threshold"
    voltage_5V_critical_over_threshold=12;          test_case  voltage_5V_critical_over_threshold=12               "5V+critical_over_threshold+$voltage_5V_critical_over_threshold.000000"                                     "svcinfo lsenclosurevoltage" "inject test 5V critical_over_threshold"
    voltage_3_3V_voltage=10;                        test_case  voltage_3_3V_voltage=10                             "3.3V+voltage+$voltage_3_3V_voltage.000000"                                                         "svcinfo lsenclosurevoltage" "inject test 3.3V voltage"
    voltage_3_3V_warning_under_threshold=9;           test_case  voltage_3_3V_warning_under_threshold=9              "3.3V+warning_under_threshold+$voltage_3_3V_warning_under_threshold.000000"                                   "svcinfo lsenclosurevoltage" "inject test 3.3V warning_under_threshold"
    voltage_3_3V_warning_over_threshold=11;           test_case  voltage_3_3V_warning_over_threshold=11              "3.3V+warning_over_threshold+$voltage_3_3V_warning_over_threshold.000000"                                   "svcinfo lsenclosurevoltage" "inject test 3.3V warning_over_threshold"
    voltage_3_3V_critical_under_threshold=8;          test_case  voltage_3_3V_critical_under_threshold=8             "3.3V+critical_under_threshold+$voltage_3_3V_critical_under_threshold.000000"                                   "svcinfo lsenclosurevoltage" "inject test 3.3V critical_under_threshold"
    voltage_3_3V_critical_over_threshold=12;          test_case  voltage_3_3V_critical_over_threshold=12             "3.3V+critical_over_threshold+$voltage_3_3V_critical_over_threshold.000000"                                   "svcinfo lsenclosurevoltage" "inject test 3.3V critical_over_threshold"
    voltage_3_3V_Standby_voltage=10;                  test_case  voltage_3_3V_Standby_voltage=10                     "3.3V Standby+voltage+$voltage_3_3V_Standby_voltage.000000"                                                    "svcinfo lsenclosurevoltage" "inject test 3.3V Standby voltage" 
    voltage_3_3V_Standby_warning_under_threshold=9;   test_case  voltage_3_3V_Standby_warning_under_threshold=9      "3.3V Standby+warning_under_threshold+$voltage_3_3V_Standby_warning_under_threshold.000000"                           "svcinfo lsenclosurevoltage" "inject test 3.3V Standby warning_under_threshold"
    voltage_3_3V_Standby_warning_over_threshold=11;   test_case  voltage_3_3V_Standby_warning_over_threshold=11      "3.3V Standby+warning_over_threshold+$voltage_3_3V_Standby_warning_over_threshold.000000"                           "svcinfo lsenclosurevoltage" "inject test 3.3V Standby warning_over_threshold"
    voltage_3_3V_Standby_critical_under_threshold=8;  test_case  voltage_3_3V_Standby_critical_under_threshold=8     "3.3V Standby+critical_under_threshold+$voltage_3_3V_Standby_critical_under_threshold.000000"                           "svcinfo lsenclosurevoltage" "inject test 3.3V Standby critical_under_threshold"
    voltage_3_3V_Standby_critical_over_threshold=12;  test_case  voltage_3_3V_Standby_critical_over_threshold=12     "3.3V Standby+critical_over_threshold+$voltage_3_3V_Standby_critical_over_threshold.000000"                           "svcinfo lsenclosurevoltage" "inject test 3.3V Standby critical_over_threshold"
    voltage_3V_Battery_voltage=10;                  test_case  voltage_3V_Battery_voltage=10                       "3V Battery+voltage+$voltage_3V_Battery_voltage.000000"                                                     "svcinfo lsenclosurevoltage" "inject test 3V Battery voltage"
    voltage_3V_Battery_warning_under_threshold=9;   test_case  voltage_3V_Battery_warning_under_threshold=9        "3V Battery+warning_under_threshold+$voltage_3V_Battery_warning_under_threshold.000000"                             "svcinfo lsenclosurevoltage" "inject test 3V Battery warning_under_threshold"
    voltage_3V_Battery_warning_over_threshold=11;   test_case  voltage_3V_Battery_warning_over_threshold=11        "3V Battery+warning_over_threshold+$voltage_3V_Battery_warning_over_threshold.000000"                             "svcinfo lsenclosurevoltage" "inject test 3V Battery warning_over_threshold"
    voltage_3V_Battery_critical_under_threshold=8;  test_case  voltage_3V_Battery_critical_under_threshold=8       "3V Battery+critical_under_threshold+$voltage_3V_Battery_critical_under_threshold.000000"                             "svcinfo lsenclosurevoltage" "inject test 3V Battery critical_under_threshold"
    voltage_3V_Battery_critical_over_threshold=12;  test_case  voltage_3V_Battery_critical_over_threshold=12       "3V Battery+critical_over_threshold+$voltage_3V_Battery_critical_over_threshold.000000"                             "svcinfo lsenclosurevoltage" "inject test 3V Battery critical_over_threshold"

    TEST_CASE_ELEMENT_TYPE=""
    echo_log "##########################TEST VOLTAGE END ####################################"
}


function test_case_canister
{
    echo_log "##########################TEST CANISTER ####################################"
    TEST_CASE_ELEMENT_TYPE=CANISTER
    canisterid=`$IPMITOOL_REAL raw 0x30 0x40`
    if [ $canisterid = "00" ]; then
        canister_status=online ;      test_case canister_status=online      "status $canister_status"                   "lsenclosurecanister -canister 1 93" "inject test status $canister_status"
        canister_temp=15;             test_case canister_temp=15            "temperature $canister_temp"                "lsenclosurecanister -canister 1 93" "inject test temperature $canister_temp"
        canister_fw_level=99;         test_case canister_fw_level=99        "firmware_level 0.${canister_fw_level}"     "lsenclosurecanister -canister 1 93" "inject test firmware_level 0.${canister_fw_level}"
        canister_fw_level_2=99;       test_case canister_fw_level_2=99      "firmware_level2 0.${canister_fw_level_2}"  "lsenclosurecanister -canister 1 93" "inject test firmware_level2 0.${canister_fw_level_2}"
    fi
    TEST_CASE_ELEMENT_TYPE=""
    echo_log "##########################TEST CANISTER END####################################"
}
function test_case_enclosure
{
    echo_log "##########################TEST ENCLOSURE ####################################"
    TEST_CASE_ELEMENT_TYPE=ENCLOSURE

    Enclosure_online_PSUs=0;        Enclosure_PSU_Status=offline,offline;   test_case "Enclosure_online_PSUs=0;Enclosure_PSU_Status=offline,offline;"   "online_PSUs $Enclosure_online_PSUs"         "svcinfo lsenclosure 93"  "inject test enclosure online_PSUs $Enclosure_online_PSUs"
    Enclosure_online_PSUs=1;        Enclosure_PSU_Status=online,offline;    test_case "Enclosure_online_PSUs=1;Enclosure_PSU_Status=online,offline"     "online_PSUs $Enclosure_online_PSUs"         "svcinfo lsenclosure 93"  "inject test enclosure online_PSUs $Enclosure_online_PSUs"
    Enclosure_online_PSUs=2;        Enclosure_PSU_Status=online,online;     test_case "Enclosure_online_PSUs=2;Enclosure_PSU_Status=online,online"      "online_PSUs $Enclosure_online_PSUs"         "svcinfo lsenclosure 93"  "inject test enclosure online_PSUs $Enclosure_online_PSUs"

    Enclosure_online_CMCs=0;        Enclosure_CMC_Status=offline,offline;   test_case "Enclosure_online_CMCs=0;Enclosure_CMC_Status=offline,offline"    "online_CMCs $Enclosure_online_CMCs"         "svcinfo lsenclosure 93"  "inject test enclosure online_CMCs $Enclosure_online_CMCs"
    Enclosure_online_CMCs=1;        Enclosure_CMC_Status=online,offline;    test_case "Enclosure_online_CMCs=1;Enclosure_CMC_Status=online,offline"     "online_CMCs $Enclosure_online_CMCs"         "svcinfo lsenclosure 93"  "inject test enclosure online_CMCs $Enclosure_online_CMCs"
    Enclosure_online_CMCs=2;        Enclosure_CMC_Status=online,online;     test_case "Enclosure_online_CMCs=2;Enclosure_CMC_Status=online,online"      "online_CMCs $Enclosure_online_CMCs"         "svcinfo lsenclosure 93"  "inject test enclosure online_CMCs $Enclosure_online_CMCs"

    Enclosure_online_fan_modules=0; Enclosure_FAN_Presence=offline,offline,offline;   test_case "Enclosure_online_fan_modules=0;Enclosure_FAN_Presence=offline,offline,offline"    "online_fan_modules $Enclosure_online_fan_modules"     "svcinfo lsenclosure 93"  "inject test enclosure online_fan_modules $Enclosure_online_fan_modules"
    Enclosure_online_fan_modules=1; Enclosure_FAN_Presence=online,offline,offline;    test_case "Enclosure_online_fan_modules=1;Enclosure_FAN_Presence=online,offline,offline"     "online_fan_modules $Enclosure_online_fan_modules"     "svcinfo lsenclosure 93"  "inject test enclosure online_fan_modules $Enclosure_online_fan_modules"
    Enclosure_online_fan_modules=2; Enclosure_FAN_Presence=online,online,offline;     test_case "Enclosure_online_fan_modules=2;Enclosure_FAN_Presence=online,online,offline"      "online_fan_modules $Enclosure_online_fan_modules"     "svcinfo lsenclosure 93"  "inject test enclosure online_fan_modules $Enclosure_online_fan_modules"
    Enclosure_online_fan_modules=3; Enclosure_FAN_Presence=online,online,online;      test_case "Enclosure_online_fan_modules=3;Enclosure_FAN_Presence=online,online,online"       "online_fan_modules $Enclosure_online_fan_modules"     "svcinfo lsenclosure 93"  "inject test enclosure online_fan_modules $Enclosure_online_fan_modules"

    Enclosure_temperature=30;Inlet_temperature=$Enclosure_temperature;       test_case "Enclosure_temperature=30;Inlet_temperature=$Enclosure_temperature"       "ambient_temperature $Enclosure_temperature"     "svcinfo lsenclosure 93"  "inject test enclosure temperature $Enclosure_temperature"

    TEST_CASE_ELEMENT_TYPE=""
    echo_log "##########################TEST ENCLOSURE END ####################################"
}

test_case_fan || exit $STF_FAIL
test_case_psu || exit $STF_FAIL
test_case_cmc || exit $STF_FAIL
test_case_temperature || exit $STF_FAIL
test_case_voltage || exit $STF_FAIL
test_case_canister || exit $STF_FAIL
test_case_enclosure || exit $STF_FAIL

########test complate##########################
