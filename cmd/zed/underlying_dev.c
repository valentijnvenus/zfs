#include <stdio.h>
#include <stdlib.h>
#include <libzfs.h>

void
usage(void)
{
	printf(
	"Lookup the underlying device for a device name\n"
	"\n"
	"USAGE:\n"
	"	underlying_dev DEVNAME\n"
	"\n"
	"NOTE: Must be run as root or else it can't resolve DM/multipath"
	);

}

int
main(int argc, char **argv)
{
	char *path;
	if (argc < 2) {
		usage();
		return (0);
	}

	path = get_underlying_dev(NULL, argv[1]);
	if (path) {
		printf("%s\n", path);
		free(path);
	}

	return (0);
}
