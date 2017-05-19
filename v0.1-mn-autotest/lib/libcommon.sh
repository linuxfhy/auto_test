#!/usr/bin/bash
#
# Copyright (c) 2017, Inspur. All rights reserved.
#

#
# SYNOPSIS
#	tc_assert <file>
#
# DESCRIPTION
#	Extract assertions from tp file
#
# RETURN
#	None
#
# NOTES
#	Assertions in TC file should comply with such template:
#
################################################################################
#
# __stc_assertion_start                                        [1]
#                                                              [2]
# ID:	XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX [3]
#
# DESCRIPTION:                                                 [4]
#	XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX [5]
#
# STRATEGY:
#	01. XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX [6]
#	    XXXXXXXXXXXXXXXXXXXXXXXXXXXXX                      [7]
#
# __stc_assertion_end                                          [8]
#
################################################################################
#
# [1] # __stc_assertion_start : *REQUIRED*, must comply
# [2] #                       : *Optional*, it is better to comply
# [3] # DESCRIPTION:          : *Optional*, it is better to comply
# [4] # ID:\tXXXXXXXX         : *Optional*, it is better to comply
# [5] #\tXXXXXXXXXXXX         : *Optional*, it is better to comply
# [6] #\t01. XXXXXXXX         : *Optional*, it is better to comply
# [7] #\t    XXXXXXXX         : *Optional*, it is better to comply
# [8] # __stc_assertion_end   : *REQUIRED*, must comply
#
function tc_assert
{
	typeset func="tc_assert"

	typeset tc_file=${1?"*** tc file"}

	typeset f_tmp1=$TMPDIR/$NAME.$func.tmp1.$$
	typeset f_tmp2=$TMPDIR/$NAME.$func.tmp2.$$

	# 1. extract assertion
	awk '$2 ~ /__stc_assertion_start/,/__stc_assertion_end/ {print $0}' \
	    $tc_file | sed "/__stc_assertion_/d" > $f_tmp1

	# 2. expand TAB characters to SPACE characters
	expand $f_tmp1 > $f_tmp2

	# 3. print to testlog
	typeset ht=$(printf "%080d" 0 | tr '0' '#')
	[[ -s $f_tmp2 ]] && print $ht

	typeset line=""
	while read line; do
		print "$line"
	done < $f_tmp2

	[[ -s $f_tmp2 ]] && print $ht

	rm -f $f_tmp1 $f_tmp2
}

#
# SYNOPSIS
#	tc_xres <rc>
#
# DESCRIPTION
#	Wrapper to log test case result
#
#	$1 - result code, e.g. 0
#
# RETURN
#	Return 1 if fail, else return 0
#
function tc_xres
{
	typeset func="tc_xres"

	typeset -i ret=${1?"*** result code, e.g. 0"}

	typeset -u res=""
	case $ret in
	$STF_PASS)		res="PASS" ;;
	$STF_FAIL)		res="FAIL" ;;
	$STF_UNRESOLVED)	res="UNRESOLVED" ;;
	$STF_NOTINUSE)		res="NOTINUSE" ;;
	$STF_UNSUPPORTED)	res="UNSUPPORTED" ;;
	$STF_UNTESTED)		res="UNTESTED" ;;
	$STF_UNINITIATED)	res="UNINITIATED" ;;
	$STF_NORESULT)		res="NORESULT" ;;
	$STF_WARNING)		res="FATAL" ;;
	$STF_TIMED_OUT)		res="TIMED_OUT" ;;
	$STF_OTHER)		res="OTHER" ;;
	esac

	typeset tc=${g_tc_name}
	typeset msg="$tc : $res"

	msg_xres "$msg"
}

function tc_start
{
	# result code
	export STF_PASS=0
	export STF_FAIL=1
	export STF_UNRESOLVED=2
	export STF_NOTINUSE=3
	export STF_UNSUPPORTED=4
	export STF_UNTESTED=5
	export STF_UNINITIATED=6
	export STF_NORESULT=7
	export STF_WARNING=8
	export STF_TIMED_OUT=9
	export STF_OTHER=10

	# extract assertion
	tc_assert $1

	# save tc name which will be used by tc_xres()
	g_tc_name=$(basename $1)
}

#
# SYNOPSIS
#	get_msg_prefix <msg_type>
#
# DESCRIPTION
#	To format the log, we define such types msg prefix:
# 	   1. stdout: "---1---:"
# 	   2. stderr: "---2---:"
# 	   3. common: "-------:"
#
#	$1 - msg_type in {stdout, stderr, common}
#
# RETURN
#	Always return 0 and print the msg prefix to stdout
#
function get_msg_prefix
{
	typeset -l msg_type=${1?"stdout or stderr or common"}

	typeset s=""
	case $msg_type in
	"stdout"|1|o) s=$(strM '-' 7 "1") ;;
	"stderr"|2|e) s=$(strM '-' 7 "2") ;;
	"common"|9|c) s=$(strX '-' 7) ;;
	esac

	print "$s:"
	return 0
}

#
# SYNOPSIS
#	RUN_POS ...
#	RUN_NEG ...
#	RUN_NEU ...
#	RUN_RAW ...
#
# DESCRIPTION
#	Wrapper to execute command but forbidden to call function
#
#	RUN_POS:
#	   cmd must pass definitely, this function always returns 0 if cmd pass,
#          else ruturn 1 and throw out stdout/stderr of cmd as well
#	RUN_NEG:
#	   cmd must fail definitely, this function always returns 0 if cmd fail,
#          else return 1 and throw out stdout/stderr of cmd as well
#	RUN_NEU:
#	   cmd may pass, may fail,   this function returns cmd's returned value
#          It is very helpful if we just want to have a try but don't care about
#          stdout/stderr of cmd, even the returned value of cmd
#          In addtion, "RUN_NEU $cmd" is the same as "eval $cmd >/dev/null 2>&1"
#          if verbose mode is not enabled
#	RUN_RAW:
#	   the similar to RUN_NEU, but never log anything even if verbose mode
#          is enabled.
#
# RETURN
#	Please refer to DESCRIPTION
#
# NOTES
#	Never use any these function to call a function
#
function RUN_POS { _RUN "POS" "$@"; return $?; } # positive
function RUN_NEG { _RUN "NEG" "$@"; return $?; } # negative
function RUN_NEU { _RUN "NEU" "$@"; return $?; } # neutral
function RUN_RAW { _RUN "RAW" "$@"; return $?; } # raw

function _RUN
{
	typeset func="_RUN"
	# don't have to enable debug

	typeset type=${1?}
	shift

	#
	# NOTE: _RUN supports some options for special test purposes.
	#       That is, these options in the following will not be specified
	#       generally
	#
	#       1. --retry   loop=N1,interval=<N2|auto>
	#          loop    : retry times, e.g. 10
	#          interval: sleep nsecs before retry, e.g. 2 or "auto"
	#                    for "auto", sleep i * 2 secs by default
	#                                      i = 1, 2, ..., loop
	#
	#       2.  --copyout stdout=F1,stderr=F2,redirect=<1to2|2to1|none>
	#       2.1 --copyout stdout=F1,stderr=,redirect=2to1
	#           similar to: eval "$cmd" > F1 2>&1
	#       2.2 --copyout stdout=,stderr=F2,redirect=1to2
	#           similar to: eval "$cmd" > F2 1>&2
	#       2.3 --copyout stdout=F1,stderr=F2,redirect=none
	#           similar to: eval "$cmd" > F1 2> F2
	#           --copyout stdout=F1,stderr=,redirect=none
	#      	    similar to: eval "$cmd" > F1 2> /dev/null
	#           --copyout stdout=,stderr=F2,redirect=none
	#      	    similar to: eval "$cmd" > /dev/null 2> F2
	#
	typeset s_retry=""
	typeset s_copyout=""
	typeset options=":R:(retry)C:(copyout)"
	while getopts $options iopt; do
		case $iopt in
		R) s_retry=$OPTARG ;;
		C) s_copyout=$OPTARG ;;
		:) print -u2 "Option '-$OPTARG' wants an argument"; return 1 ;;
		'?') print -u2 "Option '-$OPTARG' not supported"; return 1 ;;
		esac
	done
	shift $((OPTIND - 1))

	typeset cmd="$@"

	# get loop and interval from s_retry
	typeset nloop=1
	typeset interval=0
	if [[ -n $s_retry ]]; then
		typeset -l s_rt0=$(print $s_retry | awk -F',' '{print $1}')
		typeset -l s_rt1=$(print $s_retry | awk -F',' '{print $2}')
		loop=${s_rt0#*=}
		interval=${s_rt1#*=}
		nloop=$(( $loop + 1 ))
	fi

	# get f_copyout_stdout, f_copyout_sterr, ... from s_copyout
	typeset f_copyout_stdout=""
	typeset f_copyout_stderr=""
	typeset copyout_redirect=""
	if [[ -n $s_copyout ]]; then
		typeset -l s_co1=$(print $s_copyout | awk -F',' '{print $1}')
		typeset -l s_co2=$(print $s_copyout | awk -F',' '{print $2}')
		typeset -l s_co3=$(print $s_copyout | awk -F',' '{print $3}')

		f_copyout_stdout=${s_co1#*=}
		f_copyout_stderr=${s_co2#*=}
		copyout_redirect=${s_co3#*=}

		[[ -z $f_copyout_stdout ]] && f_copyout_stdout="auto"
		[[ -z $f_copyout_stderr ]] && f_copyout_stderr="auto"
	fi

	[[ -d $TMPDIR ]] || mkdir -p $TMPDIR

	typeset stamp=$(printf "%(%s)T\n")"."$(( RANDOM ))"."$$
	typeset f1=$TMPDIR/$func.out.$stamp
	typeset f2=$TMPDIR/$func.err.$stamp
	typeset f3=$TMPDIR/$func.tmp.$stamp
	typeset f4=$TMPDIR/$func.all.$stamp
	#trap "rm -f $f1 $f2 $f3 $f4" EXIT
	typeset s1=$(get_msg_prefix "stdout")
	typeset s2=$(get_msg_prefix "stderr")
	typeset s3=$(get_msg_prefix "common")

	typeset -i ret=0
	typeset res=""
	typeset -i retry_cnt=0
	while (( nloop > 0 )); do
		typeset tag=${func#_}"_"$type

		if [[ -n $s_copyout ]]; then
			case $copyout_redirect in
			# merge stdout to stderr, i.e. 1>&2
			1to2)	eval "$cmd" > $f3 1>&2;  ret=$?
				cat $f3 > $f2
				;;
			# merge stderr to stdout, i.e. 2>&1
			2to1)	eval "$cmd" > $f3 2>&1;  ret=$?
				cat $f3 > $f1
				;;
			# don't merge stdout/stderr
			none)	eval "$cmd" > $f1 2>$f3; ret=$?
				cat $f3 > $f2
				;;
			esac

			[[ $f_copyout_stdout != "auto" ]] && \
			    cp $f1 $f_copyout_stdout
			[[ $f_copyout_stderr != "auto" ]] && \
			    cp $f2 $f_copyout_stderr
		else # never copy stdout/stderr out
			eval "$cmd" > $f1 2>$f3; ret=$?
			cat $f3 > $f2
		fi

		#
		# If type == RAW, never write log to journal
		# and don't have to retry of course
		#
		if [[ $type == "RAW" ]]; then
			[[ -f $f1 ]] && cat $f1
			[[ -f $f1 ]] && cat $f2 >&2
			rm -f $f1 $f2 $f3 $f4
			return $ret
		fi

		#
		# Now handle type == @(POS|NEG|NEU)
		#

		[[ -f $f1 ]] && sed "s/^/$s1 /g" $f1  > $f3
		[[ -f $f2 ]] && sed "s/^/$s2 /g" $f2 >> $f3

		typeset -i flag=1
		if [[ $type == "POS" ]]; then
			flag=$ret
		elif [[ $type == "NEG" ]]; then
			flag=$(( ! $ret ))
		else # NEU
			flag=0
		fi

		# Break (a) if success (b) retry property was not set
		if (( flag == 0 )) || [[ -z $s_retry ]]; then
			f4=$f3
			break
		fi

		# Now start to retry
		(( nloop -= 1 ))
		cat $f3 >> $f4
		if (( nloop > 0 )); then
			print "$s3 Orz............\$?=$ret" >> $f4

			(( retry_cnt += 1 ))
			typeset nsecs=$interval
			[[ $interval == "auto" ]] && nsecs=$(( 1 * retry_cnt ))
			print "$s3 SLEEP ${nsecs}s" >> $f4
			sleep $nsecs
			print "$s3 $tag: $cmd #<--- RETRY${retry_cnt}" >> $f4
		fi
	done

	res=$ret
	(( retry_cnt > 0 )) && res+=" # WARNING: retry $retry_cnt times"

	if (( flag != 0 )); then
		msg_fail "$tag: $cmd # \$?=$res"
		cat $f4 >&2
		rm -f $f1 $f2 $f3 $f4
		return 1
	fi

	if isverbose; then
		case $type in
		POS) msg_pass "$tag: $cmd, passed definitely # \$?=$res"  >&2 ;;
		NEG) msg_pass "$tag: $cmd, failed as expected # \$?=$res" >&2 ;;
		NEU) msg_info "$tag: $cmd, skipped on purpose # \$?=$res" >&2 ;;
		esac

		cat $f4 >&2
	fi

	rm -f $f1 $f2 $f3 $f4

	# For NEU, we always return its original returned value on purpose
	[[ $type == "NEU" ]] && return $ret

	return 0
}

# XXX: always set VERBOSE = true
function isverbose { return 0; }
