#
# libzfs_internal is library that contains functions that are common to both
# userspace code (like zpool_main.c) and to the libraries themselves, but
# are not exported as in the ABI.
#
include $(top_srcdir)/config/Rules.am

DEFAULT_INCLUDES += -I$(srcdir) -I$(top_srcdir)/lib/libzfs

lib_LTLIBRARIES = libzfs_internal.la

dist_libzfs_internal_la_SOURCES = \
	libzfs_internal.c

libzfs_internal_la_LIBADD = \
	$(abs_top_builddir)/lib/libnvpair/libnvpair.la

include $(top_srcdir)/config/CppCheck.am
