#ifndef _SYS_SMART_H
#define _SYS_SMART_H

enum smart_type {
	SMART_STATUS,	/* 0 for "OK" or "PASSED", non-zero for bad */
	SMART_TEMP,	/* In Celsius */
	SMART_VAL_COUNT, /* Always make last element */
};

struct smart_disk {
	char *dev;
	int64_t val[SMART_VAL_COUNT]; /* -1 for unused */
};
/* Populate smart_info.  Assumes smart_info[].dev is filled in */
extern int get_smart(struct smart_disk *sd, unsigned int cnt);

#endif
