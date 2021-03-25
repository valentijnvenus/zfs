# This Makefile is provided for COPR (https://copr.fedorainfracloud.org) builds.
# COPR expects to be able to run 'make srpm' in a top-level .copr/ directory
# to generate SRPMS.  It also expects those SRPMs to be copied to $(outdir)
# when done.
#
# If you're planning to build ZFS with COPR, please use the 'make srpm'
# option in the packages tab in the COPR web interface.
srpm:
	dnf -y install rpm-build wget curl bc fio acl sysstat mdadm lsscsi \
		parted attr dbench watchdog ksh nfs-utils samba rng-tools \
		dkms kernel-devel zlib-devel libuuid-devel libblkid-devel \
		libselinux-devel xfsprogs-devel libattr-devel libacl-devel \
		libudev-devel device-mapper-devel openssl-devel libtirpc-devel \
		libffi-devel libaio-devel libmount-devel pam-devel pamtester \
		python-devel python-setuptools python-cffi python3 \
		python3-devel python3-setuptools python3-cffi libasan gcc make \
		autoconf automake libtool rpm-build dkms libtirpc-devel \
		libblkid-devel libuuid-devel libudev-devel openssl-devel \
		zlib-devel libaio-devel libattr-devel elfutils-libelf-devel \
		python3 python3-devel python3-setuptools python3-cffi \
		libffi-devel
	./autogen.sh 
	./configure --with-config=srpm
	make srpm 
	cp -a *.src.rpm $(outdir)
