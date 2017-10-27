#!/bin/ksh -p
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#

#
# Copyright (c) 2017 by Lawrence Livermore National Security, LLC.
#

# DESCRIPTION:
#	Verify zpool status -d (delays) and -r (recovered) works.
#
# STRATEGY:
#	1. Create a mirrored pool
#	2. Inject delay/read/write/chksum errors into one of the drives
#	3. Verify errors are seen by zpool status [-r|-d]
#	4. Repeat 1-3 for a raidz pool
#

. $STF_SUITE/include/libtest.shlib
. $STF_SUITE/include/zpool_script.shlib

verify_runnable "both"

log_onexit cleanup

rm -fr /tmp/tmp*
sudo bash -c 'echo 1 > /sys/module/zfs/parameters/zfs_dbgmsg_enable'
sudo bash -c 'echo 1 > /sys/module/zfs/parameters/disable_error_event_ratelimit'
sudo bash -c 'echo 999999999 > /sys/module/zfs/parameters/zfs_zevent_len_max'

MOUNTDIR=$(mktemp -d)
VDEVDIR=$(mktemp -d)
VDEV1=$(mktemp -p $VDEVDIR)
VDEV2=$(mktemp -p $VDEVDIR)
VDEV3=$(mktemp -p $VDEVDIR)
POOL=tank
log_must mkfile $MINVDEVSIZE $VDEV1 $VDEV2 $VDEV3

function cleanup
{
	if poolexists $POOL ; then
		zinject -c all
		zpool destroy $POOL
	fi
	rm -f $VDEV1 $VDEV2 $VDEV3
	rmdir $MOUNTDIR

	sudo bash -c 'echo 0 > /sys/module/zfs/parameters/disable_error_event_ratelimit'
}

# Setup pool
# $1: 	"mirror" "raidz1"
function setup
{
	POOLTYPE="$1"
	log_must zpool create -m $MOUNTDIR -o failmode=continue $POOL $POOLTYPE $VDEV1 $VDEV2 $VDEV3
	log_must zfs set compression=off $POOL
}

function export_import
{
	log_must zpool export $POOL
	log_must zpool import -d $VDEVDIR $POOL
}

if zpool status | grep -q $POOL ; then
	cleanup
fi
zpool events -c


log_must eval echo 0 > /sys/module/zfs/parameters/zfs_spa_forced_spec_txgs_back
log_must eval echo 1 > /sys/module/zfs/parameters/disable_auto_resilver

if false ; then
for i in mirror raidz1 ; do
	setup "$i"

	# Mark any IOs greater than 10ms as delays 
	OLD_DELAY=$(cat /sys/module/zfs/parameters/zio_delay_max)
	log_must eval echo 10 > /sys/module/zfs/parameters/zio_delay_max

	# Create 20ms IOs
	log_must zinject -d $VDEV1 -D20:100 $POOL
	log_must mkfile 40960 $MOUNTDIR/file 
	sync
	log_must zinject -c all
	log_must eval echo $OLD_DELAY > /sys/module/zfs/parameters/zio_delay_max

	DELAYS=$(zpool status -p -d | grep "$POOL" | grep -v 'pool:' | awk '{print $6}')
	if [ "$DELAYS" -gt "0" ] ; then
		log_note "Correctly saw $DELAYS delays on $i"
	else
		log_fail "No delays seen"
		cleanup
	fi
	zpool destroy $POOL
done
fi

DEFAULT_FILESIZE=1048576
# Common function for running correctable/un-correctable read/write tests
#
# $1:	Operation to preform: "read" "write" or "scrub"
# $2:	Error to inject: "read" "write" or "corrupt" (checksum)
# $3	Recover or not: "recover" to test recoverable errors.  "error" to force
#	uncorrectable errors.
# $4	(optional) File size to write.  If not set, use $DEFAULT_FILESIZE.
function do_test {
	OP="$1"
	ERR="$2"
	RECOVER="$3"
	FILESIZE="$4"
	POOLTYPE=$(zpool status | grep -Eo -m 1 'mirror|raidz1')
	if [ -z "$FILESIZE" ] ; then
		FILESIZE="$DEFAULT_FILESIZE"
	fi

	if [ "$ERR" == "corrupt" ] ; then
		DEVERR="corrupt"
		RWERR="read"
	else
		DEVERR="io"
		RWERR="$ERR"
	fi

	log_note "${ERR} and $RECOVER errors on $POOLTYPE"
	zpool events -c
	log_must zinject -d $VDEV1 -e $DEVERR -T $RWERR -f 50 $POOL
	if [ "$RECOVER" != "recover" ] ; then
		log_must zinject -d $VDEV2 -e $DEVERR -T $RWERR -f 100 $POOL
		log_must zinject -d $VDEV3 -e $DEVERR -T $RWERR -f 100 $POOL
	fi

	if [ "$OP" == "read" ] ; then
		cat $MOUNTDIR/file > /dev/null || true
	elif [ "$OP" == "write" ] ; then
		log_must mkfile 100000 $MOUNTDIR/file || true
		sync
		log_note "$(zpool status -r)"
		log_must zinject -c all
		log_note "scrubbing..."
#		scrub_and_wait $POOL || true

		zpool clear $POOL
		for i in {1..10} ; do
			log_note "#### $i ####"
			log_note "$(zpool status -r)"
			sleep 1
		done
		zpool scrub $POOL
		sleep 1
#		scrub_and_wait $POOL || true
#		cat $MOUNTDIR/file &> /dev/null

		log_note "$(zpool status -r)"
	else
		scrub_and_wait $POOL || true
	fi
	sync

	if [ "$OP" == "scrub" ] ; then
		# Wait for the scrub
		while ! is_pool_scrubbed $POOL; do
		        sleep 1
		done
	fi

	log_note "$(zpool status -r)"

	# Get error stats line for the pool
	LINE=$(zpool status -p -r | grep $POOL | grep -v 'pool:')
	if [ "$ERR" == "read" ] ; then
		ERRORS=$(echo "$LINE" | awk '{print $3}')
	elif [ "$ERR" == "write" ] ; then
		ERRORS=$(echo "$LINE" | awk '{print $4}')
	else
		ERRORS=$(echo "$LINE" | awk '{print $5}')
	fi
	RECOVERED=$(echo "$LINE" | awk '{print $6}')

	if [ "$RECOVER" == "recover" ] ; then	
		if [ "$RECOVERED" -le 0 ] ; then
			log_note "ERROR: $RECOVERED recovered ${ERR}s while testing ${OP}s on $POOLTYPE"
			cleanup
			exit
		elif [ "$RECOVERED" -le "$ERRORS" ] ; then
			log_note "Correctly saw $RECOVERED recovered ${ERR}s <= $ERRORS errors while testing ${OP}s on $POOLTYPE"
		else
			log_note "ERROR: $RECOVERED recovered ${ERR}s > $ERRORS errors while testing ${OP}s on $POOLTYPE"
			cleanup
			exit
		fi
	else
		if [ "$ERRORS" -gt "$RECOVERED" ] ; then
			log_note "Correctly saw $ERRORS ${ERR} errors > $RECOVERED recovered while testing ${OP}s on $POOLTYPE"
		else
			log_note "ERROR: $ERRORS ${ERR} errors < $RECOVERED recovered while testing ${OP}s on $POOLTYPE"
			cleanup
			exit
		fi
	fi



	log_must zinject -c all
	log_must zpool clear $POOL
}

for i in raidz mirror ; do 
	setup "$i"
	log_must mkfile $DEFAULT_FILESIZE $MOUNTDIR/file

	export_import
	do_test write write recover


	break
	do_test read corrupt recover

	do_test scrub corrupt recover

	export_import
	do_test read corrupt error
	do_test scrub corrupt error

	export_import
	do_test read read recover
#	do_test write write recover
	log_must mkfile $DEFAULT_FILESIZE $MOUNTDIR/file
	export_import
	do_test scrub read recover
	export_import

	do_test read read error 
	do_test scrub read error
#	do_test write write error

	# Our last tests tested tons of write errors to our file, so we can't gurantee
	# the file is large enough to scrub.  Re-write the file.
	log_must mkfile $DEFAULT_FILESIZE $MOUNTDIR/file
	export_import

	zpool destroy $POOL
done
#cleanup

