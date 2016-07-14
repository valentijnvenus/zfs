#include <stdio.h>
#include <stdlib.h>

enum {
	SAS_STATUS = 0, 
	ATA_STATUS,
	SAS_TEMP,
	ATA_TEMP,
	SAS_UNCORR,
	SAS_NMEDIA,
	SAS_INVOKE,
	SMART_VAL_COUNT, /* Always make last element */
};

struct smart_info {
	struct smart_disk {
		char *dev;
		int64_t val[SMART_VAL_COUNT]; /* -1 for unused */
	} *disk;
	int count; /* Number of disks */
}

if disk[i][SMART_VAL_COUNT] > 0


if disk[i]->exists[ATA_TEMP]

void do_smart(void *data) {
	struct smart_val *sv = data;
	printf("hello world %s\n", sv->dev);
}





int main(int argc, char **argv) {
	int nspawn = 3;
	struct smart_info *sm;
	pthread_t *tid;
	int rc, i;
	char *devs[] = {"sda", "sdb", "sdc"};
		
	sm = calloc(nspawn, sizeof(*sm));
	tid = calloc(nspawn, sizeof(*tid));
	
	for (i = 0; i < nspawn; i++) {
		sm[i].dev = devs[i];
		rc = pthread_create(&tid[i], NULL, do_smart, &sm[i]);
		printf("%d rc=%d\n", i, rc);
	}

	free(tid);
	free(sm);
	return 0;
}

