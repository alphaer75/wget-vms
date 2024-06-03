#ifndef MY_VMS_STDINT
#define MY_VMS_STDINT
#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#define SIZE_MAX UINT_MAX
#define UINT32_MAX  4294967295u
#define UINT16_MAX             (65535)
#define UINT8_MAX                (255)
#define INT64_MAX (9223372036854775807LL)
# define INT64_MIN              ((-9223372036854775807LL)-1)
#ifdef INT64_MAX
# define _SCN64_PREFIX "ll"
# define _PRI64_PREFIX "ll"
# if !defined SCNd64
#  define SCNd64 _SCN64_PREFIX "d"
# endif
# if !defined SCNi64
#  define SCNi64 _SCN64_PREFIX "i"
# endif
# if !defined PRId64
#  define PRId64 _PRI64_PREFIX "d"
# endif
# if !defined PRIi64
#  define PRIi64 _PRI64_PREFIX "i"
# endif
#endif
#ifdef UINT64_MAX
# define _SCNu64_PREFIX "ll"
# define _PRIu64_PREFIX "ll"
# if !defined SCNo64
#  define SCNo64 _SCNu64_PREFIX "o"
# endif
# if !defined SCNu64
#  define SCNu64 _SCNu64_PREFIX "u"
# endif
# if !defined SCNx64
#  define SCNx64 _SCNu64_PREFIX "x"
# endif
# if !defined PRIu64
#  define PRIu64 _PRIu64_PREFIX "u"
# endif
# if !defined PRIx64
#  define PRIx64 _PRIu64_PREFIX "x"
# endif
#endif
#ifndef PRIu32
#  define PRIu32 "lu"
#endif
# if __WORDSIZE == 64
#  define PTRDIFF_MIN           (-9223372036854775807L-1)
#  define PTRDIFF_MAX           (9223372036854775807L)
# else
#  define PTRDIFF_MIN           (-2147483647-1)
#  define PTRDIFF_MAX           (2147483647)
# endif


typedef unsigned int 	uint_fast32_t ;
typedef int 		int_fast32_t ;
#endif
