#include <time.h>
#include <stdlib.h>
time_t
my_timegm(struct tm *tm)
{
	time_t ret;

	ret = mktime(tm);
	return ret;
}
