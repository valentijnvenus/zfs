#include <sys/fs/zfs.h>
#include <libzutil.h>
#include <libzfs.h>
#include <libzfs_impl.h>
#include <libzfs_internal.h>

/*
 * We want to call zpool_get_config() in this file, but that requires linking
 * against libzfs... which requires this file as a dependency.  We can't
 * just move zpool_get_config() to this file, since zpool_get_config() is part
 * of the ABI, and wouldn't get exposed here.
 *
 * To get around this, we add the zpool_get_config_impl() dummy function which
 * we can call directly in this file, and then update zpool_get_config() to
 * call zpool_get_config_impl().
 */
nvlist_t *
zpool_get_config_impl(zpool_handle_t *zhp, nvlist_t **oldconfig)
{
	if (oldconfig)
		*oldconfig = zhp->zpool_old_config;
	return (zhp->zpool_config);
}

static int
for_each_vdev_cb(zpool_handle_t *zhp, nvlist_t *nv, pool_vdev_iter_f func,
    void *data)
{
	nvlist_t **child;
	uint_t c, children;
	int ret = 0;
	int i;
	char *type;

	const char *list[] = {
	    ZPOOL_CONFIG_SPARES,
	    ZPOOL_CONFIG_L2CACHE,
	    ZPOOL_CONFIG_CHILDREN
	};

	for (i = 0; i < ARRAY_SIZE(list); i++) {
		if (nvlist_lookup_nvlist_array(nv, list[i], &child,
		    &children) == 0) {
			for (c = 0; c < children; c++) {
				uint64_t ishole = 0;

				(void) nvlist_lookup_uint64(child[c],
				    ZPOOL_CONFIG_IS_HOLE, &ishole);

				if (ishole)
					continue;

				ret |= for_each_vdev_cb(zhp, child[c], func,
				    data);
			}
		}
	}

	if (nvlist_lookup_string(nv, ZPOOL_CONFIG_TYPE, &type) != 0)
		return (ret);

	/* Don't run our function on root vdevs */
	if (strcmp(type, VDEV_TYPE_ROOT) != 0) {
		ret |= func(zhp, nv, data);
	}

	return (ret);
}

/*
 * This is the equivalent of for_each_pool() for vdevs.  It iterates through
 * all vdevs in the pool, ignoring root vdevs and holes, calling func() on
 * each one.
 *
 * @zhp:	Zpool handle
 * @func:	Function to call on each vdev
 * @data:	Custom data to pass to the function
 */
int
for_each_vdev(zpool_handle_t *zhp, pool_vdev_iter_f func, void *data)
{
	nvlist_t *config, *nvroot = NULL;

	if ((config = zpool_get_config_impl(zhp, NULL)) != NULL) {
		verify(nvlist_lookup_nvlist(config, ZPOOL_CONFIG_VDEV_TREE,
		    &nvroot) == 0);
	}
	return (for_each_vdev_cb(zhp, nvroot, func, data));
}

/*
 * Given an ZPOOL_CONFIG_VDEV_TREE nvpair, iterate over all the vdevs, calling
 * func() for each one.  func() is passed the vdev's nvlist and an optional
 * user-defined 'data' pointer.
 */
int
for_each_vdev_in_nvlist(nvlist_t *nvroot, pool_vdev_iter_f func, void *data)
{
	return (for_each_vdev_cb(NULL, nvroot, func, data));
}
