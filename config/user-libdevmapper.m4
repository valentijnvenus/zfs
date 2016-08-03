dnl #
dnl # Check for libdevmapper
dnl #
AC_DEFUN([ZFS_AC_CONFIG_USER_LIBDEVMAPPER], [

	AC_CHECK_HEADER([libdevmapper.h], [], [AC_MSG_FAILURE([
	*** libdevmapper.h missing, device-mapper-devel package required])])

	AC_SUBST(LIBDEVMAPPER)
	
	LIBDEVMAPPER=`pkg-config --libs devmapper`
	AC_DEFINE([HAVE_LIBDEVMAPPER], 1, [Define if you have libdevmapper])
])
