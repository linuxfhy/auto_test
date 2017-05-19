#!/usr/bin/ksh
#
# Copyright (c) 2017, Vector Li (idorax@126.com)
#

source ${.sh.file%/*}/include/libssh.ksh

export TMPDIR=/tmp
export ISATTY=auto

host=${1?"*** remote host"}
user=${2?"*** user"}
password=${3?"*** password"}
port=${4:-"22"}
if [[ $port != 22 ]]; then
	ssh_opts_default="  -o StrictHostKeyChecking=no"
	ssh_opts_default+=" -F /dev/null"
	export SSH_OPTS="-p $port $ssh_opts_default"
	export SCP_OPTS="-P $port $ssh_opts_default"
fi
ssh_setup $host $user $password
exit $?
