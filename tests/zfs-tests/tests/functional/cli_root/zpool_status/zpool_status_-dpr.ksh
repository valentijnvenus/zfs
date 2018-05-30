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
# Copyright (c) 2018 by Lawrence Livermore National Security, LLC.
#

# DESCRIPTION:
#	Verify zpool status -d (delays) and -r (recovered) works.
#
# STRATEGY:
#	1. Create a pool (mirror and raidz)
#	2. Inject delays into the pool
#	3. Verify we can see the delays with "zpool status -d".
#	4. Destroy pool
#	5. Create a pool (mirror and raidz)
#	6. Inject IO corruption in one of the disks
#	7. Do reads, verify we see recovered errors
#	8. Do scrub, verify we see recovered errors
#	9. Inject IO corruption into all the other disks
#	10. Do reads & scrubs, verify we see unrecoverable errors.
#	11. Repeat 6-10, but check IO errors instead.
#

. $STF_SUITE/include/libtest.shlib
. $STF_SUITE/include/zpool_script.shlib

verify_runnable "both"

log_onexit cleanup

MOUNTDIR=$(mktemp -d)
VDEVDIR=$(mktemp -d)
VDEV1=$(mktemp -p $VDEVDIR)
VDEV2=$(mktemp -p $VDEVDIR)
VDEV3=$(mktemp -p $VDEVDIR)
POOL=tank
FILESIZE=1048576

OLD_LEN_MAX=$(cat /sys/module/zfs/parameters/zfs_zevent_len_max)
OLD_CHECKSUMS=$(cat /sys/module/zfs/parameters/zfs_checksums_per_second)
OLD_DELAYS=$(cat /sys/module/zfs/parameters/zfs_delays_per_second)
OLD_TXGS_BACK=$(cat /sys/module/zfs/parameters/zfs_spa_forced_spec_txgs_back)

log_must eval "echo 999999999 > /sys/module/zfs/parameters/zfs_zevent_len_max"
log_must eval "echo 999999999 > /sys/module/zfs/parameters/zfs_delays_per_second"
log_must eval "echo 999999999 > /sys/module/zfs/parameters/zfs_checksums_per_second"
log_must eval "echo 0 > /sys/module/zfs/parameters/zfs_spa_forced_spec_txgs_back"

function cleanup
{
	log_note "cleaning up"
	if poolexists $POOL ; then
		zinject -c all
		zpool destroy $POOL
	fi
	rm -fr "$VDEVDIR"
	rmdir $MOUNTDIR
	echo "$OLD_LEN_MAX" > /sys/module/zfs/parameters/zfs_zevent_len_max
	echo "$OLD_CHECKSUMS" > /sys/module/zfs/parameters/zfs_checksums_per_second
	echo "$OLD_DELAYS" >  /sys/module/zfs/parameters/zfs_delays_per_second
	echo "$OLD_TXGS_BACK" > /sys/module/zfs/parameters/zfs_spa_forced_spec_txgs_back
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

# Common function for running correctable/un-correctable read/write tests
#
# $1:	Operation to preform: "read" or "scrub"
# $2:	Error to inject: "io" or "corrupt" (checksum)
# $3	Recover or not: "recover" to test recoverable errors.  "error" to force
#	uncorrectable errors.
function do_test {
	OP="$1"
	ERR="$2"
	RECOVER="$3"
	POOLTYPE=$(zpool status | grep -Eo -m 1 'mirror|raidz1')

	log_note "${ERR} and $RECOVER errors on $POOLTYPE"
	zpool events -c
	log_must zinject -d $VDEV1 -e $ERR -T read -f 50 $POOL
	if [ "$RECOVER" != "recover" ] ; then
		log_must zinject -d $VDEV2 -e $ERR -T read -f 100 $POOL
		log_must zinject -d $VDEV3 -e $ERR -T read -f 100 $POOL
	fi

	if [ "$OP" == "read" ] ; then
		cat $MOUNTDIR/file > /dev/null || true
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

	# Get error stats line for the pool
	LINE=$(zpool status -p -r | grep $POOL | grep -v 'pool:')
	if [ "$ERR" == "read" ] ; then
		ERRORS=$(echo "$LINE" | awk '{print $3}')
	elif [ "$ERR" == "corrupt" ] ; then
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
	log_note "$(zpool status -dr)"
	log_must zpool clear $POOL
}

log_must mkfile $MINVDEVSIZE $VDEV1 $VDEV2 $VDEV3


# Test delays
for i in mirror raidz1 ; do
	log_note "delay setting up $i"
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

# Test IO errors
for i in raidz mirror ; do
	setup "$i"
	log_must mkfile $FILESIZE $MOUNTDIR/file

	# Test reading/scrubbing with corrupted data
	export_import
	do_test read corrupt recover
	do_test scrub corrupt recover
	export_import
	do_test read corrupt error
	do_test scrub corrupt error

	# Test reading/scrubbing with read IO errors
	export_import
	do_test read io recover
	log_must mkfile $FILESIZE $MOUNTDIR/file
	export_import
	do_test scrub io recover
	export_import
	do_test read io error
	do_test scrub io error

	zpool destroy $POOL
done

cleanup
