#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

NAME=$(basename ${0})
CDIR=$(dirname ${0})
TMPDIR=${TMPDIR:-"/tmp"}

#
# 1. global VARs and ENVs
#

STC_VERSION=$(egrep "^STC_VERSION=" STC.INFO | \
    awk -F'=' '{print $NF}' | sed 's/"//g')
STC_NAME=$(egrep "STC_NAME=" STC.INFO | \
    awk -F'=' '{print $NF}' | sed 's/"//g')
RESULTS_DIR=${RESULTS_DIR:-"/tmp/oak/results"}

# ARCH, MACH, TESTS_PATH
ARCH=$(uname -p)
MACH=$(uname -p)
TESTS_PATH="./tests"

# SETUP and CLEANUP
SETUP=setup.sh
CLEANUP=cleanup.sh

# set LD_LIBRARY_PATH
export LD_LIBRARY_PATH=

# set PATH
export PATH=$TESTS_PATH:$PATH


#
# 2. source lib functions
#

. $CDIR/lib/libstr.sh

#
# 3. private functions for tests
#

function get_tc_list
{
	typeset func="get_tc_list"
	typeset f_tmp=$TMPDIR/$NAME.$func.tmp.$$

	typeset tc_list="$(ls -1 $TESTS_PATH/tc*.sh)"
	print "$tc_list"
}

function log_summary
{
	typeset what=$1
	if [[ "$what" == "TC" ]]; then
		# TC <tc_res> <tc_name>
		shift
		typeset tc=$1
		typeset tc_res=$2
		typeset tc_prefix="$(strL '|' 8 TC | sed 's/|/ /g')"
		print "[ $tc_res ] $tc_prefix $tc" >> $F_SUM
	else
		print "$*" >> $F_SUM
	fi
}

function log_summary_all
{
	typeset align=$1; shift
	typeset sin="${*}"
	typeset sout=""
	typeset width=80
	if (( ${#sin} == width )); then
		sout="$sin"
	else
		sin=$(print "$sin" | sed 's/ /|/g')
		sout=$(strLRM $align '|' $(( width - 4 )) "$sin" | \
		    sed "s/|/ /g")
		sout="* $sout *"
	fi

	log_summary "$sout"
	msg_highlight "$sout"
}

function log_journal
{
	print "$*" | sed 's/^/stdout| /g' >> $F_JNL
}

function log_cmd
{
	print "stdout| root# $*" >> $F_JNL
	eval "$*" | sed 's/^/stdout| /g' >> $F_JNL
	print "stdout|" >> $F_JNL
}

function log_tc_start
{
	typeset pid=$1
	typeset tc=$2
	print "Test_Case_Start| $pid $tc | $(date +"%H:%M:%S") |" >> $F_JNL
}

function log_tc_end
{
	typeset pid=$1
	typeset tc=$2
	typeset res=$3
	print "Test_Case_End| $pid $tc | $res | $(date +"%H:%M:%S") |" >> $F_JNL
}

#
# 4. public functions for tests
#

function _exec
{
	typeset func="_exec"

	typeset tc=$1
	typeset tc_res=""
	typeset -i pid i ret=0
	typeset f_log=$TMPDIR/$NAME.${func}.log.$$

	log_tc_start $pid $tc

	#
	# execute a TC
	#
	s_run=$(strL '.' 72 "Running root test case : $tc"); printf "$s_run"
	eval "$tc" > $f_log 2>&1 &
       	pid=$!
	i=0
	while (( i < g_timeout )); do
		ps -p $pid > /dev/null 2>&1
		(( $? != 0 )) && break
		sleep 1
		(( i += 1 ))
	done

	#
	# extract tc_res from log file
	#
	if (( i == g_timeout )); then
		msg_timeout ""
		tc_res="TIMED_OUT"
		ret=$STF_TIMED_OUT
		kill -9 $pid
		pkill $tc
	else
		typeset res=$(egrep ".*XRES.*:.*" $f_log)
		tc_res=$(print $res | awk '{print $NF}')
		[[ $tc_res == "PASS" ]] && ret=0 || ret=1
	fi

	print " $tc_res"

	#
	# log to journal and summary for TC
	#
	sed 's%^%stdout| %g' $f_log >> $F_JNL
	log_tc_end $pid $tc $tc_res

	log_summary "TC" $tc $tc_res

	return $ret
}

function tests_start
{
	typeset func="tests_start"

	typeset tag=$(date +"%Y-%m-%d-%H-%M-%S" | sed 's/-//g').$MACH
	export F_JNL=$RESULTS_DIR/journal.$tag
	export F_SUM=$RESULTS_DIR/summary.journal.$tag
	(( g_remove == 0 )) && rm -rf $RESULTS_DIR
	[[ ! -d $RESULTS_DIR ]] && mkdir -p $RESULTS_DIR
	> $F_JNL
	> $F_SUM

	typeset start_date=$(date +"%Y-%m-%d" | sed 's/-//g')
	typeset start_time=$(date +"%H:%M:%S")
	cat >> $F_JNL <<- EOF
		Start| $start_date $(id -un)($(id -u)) | $start_time |
		Start| $$ $(uname -a) |
	EOF

	# save env
	cat >> $F_JNL <<- EOF
		STC_ENV| STC_VERSION=$STC_VERSION
		STC_ENV| STC_NAME=$STC_NAME
		STC_ENV| ARCH=$ARCH
		STC_ENV| MACH=$MACH
		STC_ENV| LD_LIBRARY_PATH=$LD_LIBRARY_PATH
		STC_ENV| PATH=$PATH
		STC_ENV| RESULTS_DIR=$RESULTS_DIR
		STC_ENV| TIMEOUT=$g_timeout
	EOF

	print "\nJournal file: $F_JNL"
	if (( g_exec == 0 )); then
		# not print out summary if setup or cleanup
		print "Summary file: $F_SUM"
	fi
}

function tests_end
{
	typeset func="tests_end"

	print "End| $$ | $(date +"%H:%M:%S") |" >> $F_JNL

	if (( g_exec != 0 )); then
		# not print out summary if setup or cleanup
		return
	fi

	typeset f_sum=$TMPDIR/$NAME.${func}.sum.$$
	typeset f_tmp=$TMPDIR/$NAME.${func}.tmp.$$

	cp $F_SUM $f_sum
	grep " TC " $f_sum > $f_tmp
	typeset tc_num_total=$(grep   " TC "        $f_tmp | wc -l)
	typeset tc_num_pass=$(grep    " PASS "      $f_tmp | wc -l)
	typeset tc_num_fail=$(grep    " FAIL "      $f_tmp | wc -l)
	typeset tc_num_timeout=$(grep " TIMED_OUT " $f_tmp | wc -l)

	tc_num_total=$(strR   '-' 3 $tc_num_total   | sed "s/-/ /g")
	tc_num_pass=$(strR    '-' 3 $tc_num_pass    | sed "s/-/ /g")
	tc_num_fail=$(strR    '-' 3 $tc_num_fail    | sed "s/-/ /g")
	tc_num_timeout=$(strR '-' 3 $tc_num_timeout | sed "s/-/ /g")

	print
	log_summary_all 'L' "$(strX '*' 80)"
	log_summary_all 'L' ""
	log_summary_all 'M' "Summary"
	log_summary_all 'M' "======="
	log_summary_all 'L' ""
	log_summary_all 'L' "STC_VERSION  : $STC_VERSION"
	log_summary_all 'L' ""
	log_summary_all 'L' "Number of TC : $tc_num_total"
	log_summary_all 'L' "PASS         : $tc_num_pass"
	log_summary_all 'L' "FAIL         : $tc_num_fail"
	[[ $(print $tc_num_timeout) != '0' ]] && \
	log_summary_all 'L' "TIMEOUT      : $tc_num_timeout"
	log_summary_all 'L' "$(strX '*' 80)"

	rm -f $RESULTS_DIR/journal $RESULTS_DIR/summary
	ln -s $F_JNL $RESULTS_DIR/journal
	ln -s $F_SUM $RESULTS_DIR/summary
	print
	print "Journal file: $RESULTS_DIR/journal"
	print "Summary file: $RESULTS_DIR/summary"
	print
}

function tests_setup
{
	typeset func="tests_setup"

	typeset tc="setup"
	typeset pid=$$
	typeset tc_res="N/A"
	typeset s_run=""

	log_tc_start $pid $tc
	s_run=$(strL '.' 72 "Running root $tc : $tc"); printf "\n$s_run"

	typeset setup=$TESTS_PATH/$SETUP
	if [[ -x $setup ]]; then
		typeset f_log=$TMPDIR/$NAME.${func}.log.$$
		$setup > $f_log 2>&1
		egrep -v "\[m$" $f_log | sed 's/^/stdout| /g' >> $F_JNL
		typeset res=$(egrep ".*XRES.*:.*" $f_log)
		tc_res=$(print $res | awk '{print $NF}')
	fi

	printf " $tc_res\n"

	log_tc_end $pid $tc $tc_res
}

function tests_cleanup
{
	typeset func="tests_cleanup"

	typeset tc="cleanup"
	typeset pid=$$
	typeset tc_res="N/A"
	typeset s_run=""

	log_tc_start $pid $tc
	s_run=$(strL '.' 72 "Running root $tc : $tc"); printf "\n$s_run"

	typeset cleanup=$TESTS_PATH/$CLEANUP
	if [[ -x $cleanup ]]; then
		typeset f_log=$TMPDIR/$NAME.${func}.log.$$
		$cleanup > $f_log 2>&1
		egrep -v "\[m$" $f_log | sed 's/^/stdout| /g' >> $F_JNL
		typeset res=$(egrep ".*XRES.*:.*" $f_log)
		tc_res=$(print $res | awk '{print $NF}')
	fi

	printf " $tc_res\n"
	log_tc_end $pid $tc $tc_res
}

function tests_execute
{
	typeset func="tests_execute"

	typeset tc_list=$@
	[[ -z "$tc_list" ]] && tc_list=$(get_tc_list)
	typeset tc=""
	print
	for tc in $tc_list; do
		_exec $tc
		(( g_exitcode |= $? ))
	done
}

function usage
{
	print "$1: [-h] [-t timeout] <-s|-c|-e> [TC]" >&2
	print "\t-h: help" >&2
	print "\t-t: timeout for one TC" >&2
	print "\t-s: setup" >&2
	print "\t-c: cleanup" >&2
	print "\t-e: execute, run tests" >&2
}

function cleanup
{
	rm -rf $TMPDIR/*.$$
	exit ${1}
}

#
# 5. main()
#
g_init=1
g_fini=1
g_exec=1
g_timeout=1800
g_remove=1
g_exitcode=0

while getopts 'scet:rh' iopt; do
	case $iopt in
	s) g_init=0 ;;
	c) g_fini=0 ;;
	e) g_exec=0; g_init=0; g_fini=0 ;;
	t) g_timeout=$OPTARG ;;
	r) g_remove=0 ;;
	h|*) usage $NAME; cleanup 1 ;;
	esac
done
shift $((OPTIND - 1))

if (( g_init + g_fini + g_exec == 3 )); then
	usage $NAME
	cleanup 1
fi

if [[ $(id -un) != "root" ]]; then
	print "$NAME: must run as root" >&2
	cleanup 1
fi

tests_start
(( g_init == 0 )) && tests_setup
(( g_exec == 0 )) && tests_execute $@
(( g_fini == 0 )) && tests_cleanup
tests_end

cleanup $g_exitcode
