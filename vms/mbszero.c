#include <wchar.h>

void
mbszero (mbstate_t *ps)
{
	  memset (ps, 0, sizeof (mbstate_t));
}

