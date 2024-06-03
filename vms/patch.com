$INPUT_NAME=P1
$OUTPUT_NAME=P2
$copy 'INPUT_NAME' 'OUTPUT_NAME'
$WRITE SYS$OUTPUT "Making ", OUTPUT_NAME
$perl -p -i -e "s/\@GNULIB(.+)VARIABLE\@/LIBUNISTRING_DLL_VARIABLE/g" 'OUTPUT_NAME'
$perl -p -i -e "s/\@HAVE_UNISTRING_WOE32DLL_H\@/HAVE_UNISTRING_WOE32DLL_H/g" 'OUTPUT_NAME'
$perl -p -i -e "s/\@HAVE_ALLOCA_H\@/0/g" 'OUTPUT_NAME'
$perl -p -i      -e "s/\@GUARD_PREFIX@/GL/g" 'OUTPUT_NAME'
$perl -p -i      -e "s/\@HAVE_FNMATCH_H@/1/g" 'OUTPUT_NAME'
$perl -p -i      -e "s/\@INCLUDE_NEXT@//g" 'OUTPUT_NAME'
$perl -p -i      -e "s/\@PRAGMA_SYSTEM_HEADER@//g" 'OUTPUT_NAME'
$perl -p -i      -e "s/\@PRAGMA_COLUMNS@//g" 'OUTPUT_NAME'
$perl -p -i      -e "s/\@NEXT_FNMATCH_H@//g" 'OUTPUT_NAME'
$perl -p -i      -e "s/\@GNULIB_FNMATCH@/1/g" 'OUTPUT_NAME'
$perl -p -i      -e "s/\@HAVE_FNMATCH@/1/g" 'OUTPUT_NAME'
$perl -p -i      -e "s/\@REPLACE_FNMATCH@/1/g" 'OUTPUT_NAME'
$perl -p -i -e "s/\@GUARD_PREFIX\@/GL/g" 'OUTPUT_NAME'
$perl -p -i -e "s/\@PRAGMA_COLUMNS\@//g" 'OUTPUT_NAME'
$perl -p -i -e "s/\@HAVE_GETOPT_H\@/HAVE_GETOPT_H/g" 'OUTPUT_NAME'
$perl -p -i -e "s/\@HAVE_SYS_CDEFS_H\@/HAVE_SYS_CDEFS_H/g" 'OUTPUT_NAME'
$perl -p -i -e "s/\@NEXT_LIMITS_H\@/<limits.h>/g" 'OUTPUT_NAME'
$perl -p -i -e "s/\@HAVE_UCHAR_H\@/HAVE_UCHAR_H/g" 'OUTPUT_NAME'
$perl -p -i -e "s/\@CXX_HAS_CHAR8_TYPE\@/0/g" 'OUTPUT_NAME'
$perl -p -i -e "s/\@CXX_HAS_UCHAR_TYPES\@/0/g" 'OUTPUT_NAME'
$perl -p -i -e "s/__always_inline/inline/g" 'OUTPUT_NAME'
$perl -p -i -e "s/__glibc_likely/_GL_LIKELY/g" 'OUTPUT_NAME'
$perl -p -i -e "s/__glibc_unlikely/_GL_UNLIKELY/g" 'OUTPUT_NAME'
$perl -p -i -e "s/libc_hidden_proto .+\)$//g" 'OUTPUT_NAME'
$!perl -p -i -e "s/__always_inline//g" 'OUTPUT_NAME'
$purge 'OUTPUT_NAME'
