#include  <stdlib.h>
#include <types.h>

ssize_t getrandom (void *buffer, size_t length, unsigned int flags)
{
	size_t i;
	unsigned char d;
	unsigned char *buf;

	if (length<1)
		return -1;
	if (buffer==NULL)
		return -1;

	buf=(unsigned char*)buffer;
	for (i=0;i<=length-1;i++)
	{
		d=(unsigned char) (random() - random());
		buf[i]=d;
	}
	return length;
}


