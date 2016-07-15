#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <string.h>
#include <ctype.h>
#include <sys/smart.h>
#include <sys/sysmacros.h>

//#define ARRAY_SIZE(a) (sizeof(a)/sizeof(a[0]))

/*
  1 Raw_Read_Error_Rate     0x000f   114   100   006    Pre-fail  Always       -       59734408
  3 Spin_Up_Time            0x0003   100   097   000    Pre-fail  Always       -       0
  4 Start_Stop_Count        0x0032   100   100   020    Old_age   Always       -       43
  5 Reallocated_Sector_Ct   0x0033   100   100   036    Pre-fail  Always       -       0
  7 Seek_Error_Rate         0x000f   077   060   030    Pre-fail  Always       -       4346654182
  9 Power_On_Hours          0x0032   095   095   000    Old_age   Always       -       4388
 10 Spin_Retry_Count        0x0013   100   100   097    Pre-fail  Always       -       0
 12 Power_Cycle_Count       0x0032   100   100   020    Old_age   Always       -       31
183 Runtime_Bad_Block       0x0032   100   100   000    Old_age   Always       -       0
184 End-to-End_Error        0x0032   100   100   099    Old_age   Always       -       0
187 Reported_Uncorrect      0x0032   100   100   000    Old_age   Always       -       0
188 Command_Timeout         0x0032   100   100   000    Old_age   Always       -       0 0 0
189 High_Fly_Writes         0x003a   100   100   000    Old_age   Always       -       0
190 Airflow_Temperature_Cel 0x0022   068   060   045    Old_age   Always       -       32 (Min/Max 30/37)
194 Temperature_Celsius     0x0022   032   040   000    Old_age   Always       -       32 (0 9 0 0 0)
195 Hardware_ECC_Recovered  0x001a   040   025   000    Old_age   Always       -       59734408
197 Current_Pending_Sector  0x0012   100   100   000    Old_age   Always       -       0
198 Offline_Uncorrectable   0x0010   100   100   000    Old_age   Offline      -       0
199 UDMA_CRC_Error_Count    0x003e   200   200   000    Old_age   Always       -       0
240 Head_Flying_Hours       0x0000   100   253   000    Old_age   Offline      -       4389h+16m+00.490s
241 Total_LBAs_Written      0x0000   100   253   000    Old_age   Offline      -       165408423
242 Total_LBAs_Read         0x0000   100   253   000    Old_age   Offline      -       3534118629
*/

struct smart_table {
	char *name;
	unsigned int col;
	enum smart_type type;
} smart_table[] = {
	{"SMART overall-health self-assessment test result:", 1, SMART_STATUS},
	{"SMART Health Status:", 1, SMART_STATUS},	/* SATA */
	{"Current Drive Temperature:", 1, SMART_TEMP}, /* SAS */
	{"194 Temperature_Celsius", 8, SMART_TEMP}, /* SATA */
};

/* Return 1 if string is a number, 0 otherwise */
int isnumber(char *val) {
	int i;
	for (i = 0; i < strlen(val); i++) {
		if (!isdigit(val[i]))
			return 0;
	}
	return 1;
}

/*
 * Given a line like
 *
 * 190 Airflow_Temperature_Cel 0x0022   068   060   045    Old_age   Always       -       32 (Min/Max 30/37)
 *
 * Return string that is 'col' columns after 'name'.
 * So name = "Airflow_Temperature_Cel", col = 8, returns 32
 *
 * Special case:
 * Return 0 for "OK" or "PASSED" values, non-zero otherwise
 *
 * Returns -1 if unable to parse.
 */

int64_t
get_col_after(char *line, char *name, unsigned int col)
{
	char *line_cpy;
	char *token;
	int rc = -1;
//	printf("### Line ###\n");
//	printf("= %s\n", line);
	if (strstr(line, name) == NULL) {
		return -1;
	} else {
//		printf("Match %s\n", name);
	}

	/* Cut off our name from the line and tokenize the rest */
	line_cpy = strdup(&line[strlen(name)]);
	token = strtok(line_cpy, " ");
	
	if (col != 1) {
		while (token && col) {
			if (col == 1) {
//				printf("%d: token %s\n", col, token);
				break;
			}

			col--;
			token = strtok(NULL, " ");
		}
	}
//	printf("done iterating %s\n", token ? token : "NULL");
	if (token) {
//		printf("Special case? %s\n", token);
		/* Special case for SMART status */
		if (!isnumber(token)) {
			if (strstr(token, "OK") ||
		    	    strstr(token, "PASSED")) {
//				printf("hit passed special case\n");
				rc = 0;
			} else {
//				printf("Bad status '%s'\n", token);
				rc = 1;
			}
		} else {
//			printf("Got temp %s\n", token);
			rc = atoll(token);
		}
	}
	
	free(line_cpy);
	return rc;
}

void process_line(struct smart_disk *sd, char *line)
{
	int i;
	enum smart_type type;

	for (i = 0; i < ARRAY_SIZE(smart_table); i++) {
		type = smart_table[i].type;
		if (sd->val[type] == -1) {
			sd->val[type] = get_col_after(line, smart_table[i].name,
		    	    smart_table[i].col);
//			printf("sd->val[%d] assigned to %ld\n", type, sd->val[type]);

		} else {
//			printf("sd->val[%d] already %ld\n", type, sd->val[type]);
		}
	}
}

void * do_smart(void *data) {
	struct smart_disk *sd = data;
	char *line = NULL;
	char cmd[256];
	FILE *fp;
	size_t len = 0;
	int i;

	for (i = 0; i < ARRAY_SIZE(sd->val); i++)
		sd->val[i] = -1;

	sprintf(cmd, "cat %s", sd->dev);

	fp = popen(cmd, "r");

	while (getline(&line, &len, fp) != -1) {
		/* Chomp newline */
		char *pos;
		if ((pos=strchr(line, '\n')) != NULL)
		    *pos = '\0';
					
		process_line(sd, line);
	}

//	for (i = 0; i < ARRAY_SIZE(sd->val); i++) {
//		printf("%s smart_disk.val[%d] = %li\n", sd->dev, i, sd->val[i]);
//	}  

	free(line);

	pclose(fp);

	return NULL;
}

/* Populate smart_info.  Assumes smart_info[].devv is filled in */
int get_smart(struct smart_disk *sd, unsigned int cnt) {
	int nspawn = cnt;
	pthread_t *tid;
	int i;
	int rc;
	int ret = 0;
		
	tid = calloc(nspawn, sizeof(*tid));
	
	for (i = 0; i < nspawn; i++) {
		rc = pthread_create(&tid[i], NULL, do_smart, (void *) &sd[i]);
		if (rc)
			ret = rc;
//		printf("%d rc=%d\n", i, rc);
	}

	/* Wait for threads to finish */
	for (i = 0; i < nspawn; i++) {
		pthread_join(tid[i], NULL);
	}

	free(tid);
	return ret;
}

#if 0
int main(int argc, char **argv) {
	struct smart_disk sd[] = {
		{.dev = "sda"},
		{.dev = "sdb"},
		{.dev = "sdc"},
	};
	get_smart(sd, 2);
	
	return 0;
}
#endif


