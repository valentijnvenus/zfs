#ifndef	_LIBZUTIL_INTERNAL
#define	_LIBZUTIL_INTERNAL

#include <libzfs.h>

/* Vdev list functions */
typedef int (*pool_vdev_iter_f)(zpool_handle_t *, nvlist_t *, void *);
extern int for_each_vdev(zpool_handle_t *zhp, pool_vdev_iter_f func,
    void *data);
extern int for_each_vdev_in_nvlist(nvlist_t *nvroot, pool_vdev_iter_f func,
    void *data);

/* Only used by libzfs_config.c */
nvlist_t *
zpool_get_config_impl(zpool_handle_t *zhp, nvlist_t **oldconfig);

#endif
