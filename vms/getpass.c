#include <stdio.h>

	
char *
getpass (const char *prompt)
{
	static char pas[1024];
	puts(prompt);
	if ( fgets(pas,1023,stdin) != NULL )
	       	return pas;
	else
		return NULL;
}


			
