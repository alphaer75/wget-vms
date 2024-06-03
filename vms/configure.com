$! Configure procedure 
$! (c) Alexey Chupahin  11-APR-2024
$! alexey@vaxman.de, alexey_chupahin@mail.ru
$!
$!
$ SET NOON
$SET NOVER
$WRITE SYS$OUTPUT " "
$WRITE SYS$OUTPUT "Configuring WGET for OpenVMS  "
$WRITE SYS$OUTPUT "(c) Alexey Chupahin   CHAPG"
$WRITE SYS$OUTPUT " "
$! Checking architecture
$DECC = F$SEARCH("SYS$SYSTEM:DECC$COMPILER.EXE") .NES. ""
$    IF F$GETSYI("ARCH_TYPE").EQ.1 THEN CPU = "VAX"
$    IF F$GETSYI("ARCH_TYPE").EQ.2 THEN CPU = "Alpha"
$    IF F$GETSYI("ARCH_TYPE").EQ.3 THEN CPU = "I64"
$    IF F$GETSYI("ARCH_TYPE").EQ.4 THEN CPU = "x86"
$WRITE SYS$OUTPUT "Checking architecture 	...  ", CPU
$IF ( (CPU.EQS."Alpha").OR.(CPU.EQS."I64").OR(CPU.EQS."x86") )
$  THEN
$       SHARED=64
$  ELSE
$       SHARED=32
$ENDIF
$!
$IF (DECC) THEN $WRITE SYS$OUTPUT  "Compiler		...  DEC C"
$IF (.NOT. DECC) THEN $WRITE SYS$OUTPUT  "BAD compiler" GOTO EXIT
$MMS = F$SEARCH("SYS$SYSTEM:MMS.EXE") .NES. ""
$MMK = F$TYPE(MMK) 
$IF (MMS .OR. MMK.NES."") THEN GOTO TEST_LIBRARIES
$! I cant find any make tool
$ WRITE SYS$OUTPUT "Install MMS or MMK"
$GOTO EXIT
$PERL = F$TYPE(MMK) 
$IF (PERL.NES."") THEN GOTO TEST_LIBRARIES
$WRITE SYS$OUTPUT "Install PERL"
$GOTO EXIT
$!
$!
$! Is it package root directory? If no, go to [-]
$ IF (F$SEARCH("[]VMS.DIR").EQS."") .AND. (F$SEARCH("[]vms.dir").EQS."")
$  THEN
$       SET DEF [-]
$ ENDIF
$!
$TEST_LIBRARIES:
$!   Setting as MAKE utility one of MMS or MMK. I prefer MMS.
$IF (MMK.NES."") THEN MAKE="MMK"
$IF (MMS) THEN MAKE="MMS"
$WRITE SYS$OUTPUT "Checking build utility	...  ''MAKE'"
$WRITE SYS$OUTPUT "Checking PERL		...  found"
$WRITE SYS$OUTPUT " "
$!
$!
$!"Checking for CHAPG zlib library    "
$DEFINE SYS$ERROR _NLA0:
$DEFINE SYS$OUTPUT _NLA0:
$ CC/OBJECT=TEST.OBJ/INCLUDE=(ZLIB) SYS$INPUT
      #include <stdlib.h>
      #include <stdio.h>
      #include <string.h>
      #include <zlib.h>
   int main()
     {
        printf("checking version zlib:  %s\n",zlibVersion());
       // printf("checking zlib is correct ");
     }

$TMP = $STATUS
$DEASS SYS$ERROR
$DEAS  SYS$OUTPUT
$IF (TMP .NE. %X10B90001)
$  THEN
$       HAVE_ZLIB=0
$       GOTO ERR4
$ENDIF
$DEFINE SYS$ERROR _NLA0:
$DEFINE SYS$OUTPUT _NLA0:
$!
$LINK/EXE=TEST TEST,ZLIB:ZLIB.OPT/OPT
$TMP = $STATUS
$DEAS SYS$ERROR
$DEAS SYS$OUTPUT
$IF (TMP .NE. %X10000001)
$  THEN
$       HAVE_ZLIB=0
$       GOTO ERR4
$  ELSE
$       HAVE_ZLIB=1
$ENDIF
$ERR4:
$IF (HAVE_ZLIB.EQ.1)
$  THEN
$       WRITE SYS$OUTPUT "Checking for CHAPG zlib library ...   Yes"
$       RUN TEST
$       GOTO NEXT5
$  ELSE
$       WRITE SYS$OUTPUT "Checking for CHAPG zlib library ...   No"
$!       WRITE SYS$OUTPUT "Please install ZLIB from"
$!       WRITE SYS$OUTPUT "http://fafner.dyndns.org/~alexey/libsdl/required.html"
$!       GOTO EXIT
$ENDIF
$!
$NEXT5:
$!
$!Checking SSL
$COPY SYS$INPUT [.VMS]SSL.OPT
SYS$SHARE:SSL$LIBSSL_SHR/SHARE
SYS$SHARE:SSL$LIBCRYPTO_SHR/SHARE
$!
$DEFINE SYS$ERROR _NLA0:
$DEFINE SYS$OUTPUT _NLA0:
$ CC/OBJECT=TEST.OBJ/NOWARN SYS$INPUT
#include <stdio.h>
#include <openssl/ssl.h>
main()
{

        printf ("%s\n",OpenSSL_version( OPENSSL_VERSION));
}

$TMP = $STATUS
$DEASS SYS$ERROR
$DEAS  SYS$OUTPUT
$IF (TMP .NE. %X10B90001)
$  THEN
$       HAVE_SSL=0
$       GOTO NEXT_SSL
$ENDIF
$DEFINE SYS$ERROR _NLA0:
$DEFINE SYS$OUTPUT _NLA0:
$!
$LINK/EXE=TEST TEST,[.VMS]SSL.OPT/OPT
$TMP = $STATUS
$DEAS SYS$ERROR
$DEAS SYS$OUTPUT
$IF (TMP .NE. %X10000001)
$  THEN
$       HAVE_SSL=0
$       GOTO NEXT_SSL
$  ELSE
$       HAVE_SSL=1
$	RU TEST
$	GOTO NEXT6
$ENDIF
$!
$NEXT_SSL:
$DEL [.VMS]SSL.OPT;*
$DEL TEST.OBJ;*
$DEL TEST.EXE;*
$OPEN/WRITE F [.VMS]SSL.OPT
$FILES=F$SEARCH("OSSL$SHARE:*LIBSSL*.EXE")
$ WHILE1:
$       FILES1=F$SEARCH("OSSL$SHARE:*LIBSSL*.EXE")
$       IF ( FILES1 .EQS. "" ) THEN GOTO WHILE1_END
$	FILES1_DATE=F$CVTIME(F$FILE_ATTRIBUTES( FILES1,"RDT" ),"COMPARISON")
$	FILES_DATE=F$CVTIME(F$FILE_ATTRIBUTES( FILES,"RDT" ),"COMPARISON")
$	IF ( FILES1_DATE .GTS. FILES_DATE ) THEN FILES=FILES1
$ GOTO WHILE1
$WHILE1_END:
$WRITE F FILES,"/SHARE"
$FILES=F$SEARCH("OSSL$SHARE:*LIBCRYPTO*.EXE")
$ WHILE2:
$       FILES1=F$SEARCH("OSSL$SHARE:*LIBCRYPTO*.EXE")
$       IF ( FILES1 .EQS. "" ) THEN GOTO WHILE2_END
$	FILES1_DATE=F$CVTIME(F$FILE_ATTRIBUTES( FILES1,"RDT" ),"COMPARISON")
$	FILES_DATE=F$CVTIME(F$FILE_ATTRIBUTES( FILES,"RDT" ),"COMPARISON")
$	IF ( FILES1_DATE .GTS. FILES_DATE ) THEN FILES=FILES1
$ GOTO WHILE2
$WHILE2_END:
$WRITE F FILES, "/SHARE"
$CLOSE F
$DEFINE SYS$ERROR _NLA0:
$DEFINE SYS$OUTPUT _NLA0:
$ CC/OBJECT=TEST.OBJ SYS$INPUT
#include <stdio.h>
#include <openssl/ssl.h>
main()
{

        printf ("%s\n",OpenSSL_version( OPENSSL_VERSION));
}

$TMP = $STATUS
$DEASS SYS$ERROR
$DEAS  SYS$OUTPUT
$IF (TMP .NE. %X10B90001)
$  THEN
$       HAVE_SSL=0
$ENDIF
$DEFINE SYS$ERROR _NLA0:
$DEFINE SYS$OUTPUT _NLA0:
$!
$LINK/EXE=TEST TEST,[.VMS]SSL.OPT/OPT
$TMP = $STATUS
$DEAS SYS$ERROR
$DEAS SYS$OUTPUT
$IF (TMP .NE. %X10000001)
$  THEN
$       HAVE_SSL=0
$  ELSE
$       HAVE_SSL=1
$ENDIF
$IF (HAVE_SSL.EQ.1)
$  THEN
$       WRITE SYS$OUTPUT "Checking for SSL  library       ...   Yes"
$       RUN TEST
$       GOTO NEXT6
$  ELSE
$       WRITE SYS$OUTPUT "Checking for SSL  library       ...   No"
$       WRITE SYS$OUTPUT "Please install OpenSSL"
$       GOTO EXIT
$ENDIF
$NEXT6:
$!
$!"Checking for CHAPG idn2 library    "
$DEFINE SYS$ERROR _NLA0:
$DEFINE SYS$OUTPUT _NLA0:
$DEL TEST.OBJ;*
$DEL TEST.EXE;*
$ CC/OBJECT=TEST.OBJ/INCLUDE=(IDN2LIB) SYS$INPUT
#include <stdio.h>
#include <idn2.h>
main()
{

printf("checking version idn2: %s\n",IDN2_VERSION);

}

$TMP = $STATUS
$DEASS SYS$ERROR
$DEAS  SYS$OUTPUT
$IF (TMP .NE. %X10B90001)
$  THEN
$       HAVE_IDN2=0
$ENDIF
$DEFINE SYS$ERROR _NLA0:
$DEFINE SYS$OUTPUT _NLA0:
$!
$LINK/EXE=TEST TEST,IDN2LIB:IDN2.OPT/OPT
$TMP = $STATUS
$DEAS SYS$ERROR
$DEAS SYS$OUTPUT
$IF (TMP .NE. %X10000001)
$  THEN
$       HAVE_IDN2=0
$  ELSE
$       HAVE_IDN2=1
$ENDIF
$IF (HAVE_IDN2.EQ.1)
$  THEN
$       WRITE SYS$OUTPUT "Checking for CHAPG idn2 library ...   Yes"
$       RUN TEST
$       GOTO NEXT7
$  ELSE
$       WRITE SYS$OUTPUT "Checking for CHAPG idn2 library ...   No"
$       WRITE SYS$OUTPUT "Please install IDN2 from"
$       WRITE SYS$OUTPUT "https://vaxvms.org/wget/"
$       GOTO EXIT
$ENDIF
$!
$NEXT7:
$!WRITING BUILD FILES
$OPEN/WRITE OUT BUILD.COM
$WRITE OUT "$","COPY [.LIB]STDCKDINT.IN_H [.LIB]STDCKDINT.H"
$WRITE OUT "$","copy [.LIB]stdckdint.in_h [.LIB]stdckdint.h"
$WRITE OUT "$","copy [.LIB]unitypes.in_h [.LIB]unitypes.h"
$WRITE OUT "$","copy [.LIB]unistr.in_h [.LIB]unistr.h"
$!copy [.LIB]SPECIAL-CASING.IN_H [.LIB]SPECIAL-CASING.H
$WRITE OUT "$","copy [.LIB]uniwidth.in_h [.LIB]uniwidth.h"
$WRITE OUT "$","copy [.LIB]byteswap.in_h [.LIB]byteswap.h"
$WRITE OUT "$","copy/concat [.VMS]dynarray_patch.h,[.LIB.MALLOC]dynarray.h [.LIB.MALLOC]dynarray.h1"
$WRITE OUT "$","ren [.LIB.MALLOC]dynarray.h1 [.LIB.MALLOC]dynarray.h"
$WRITE OUT "$","perl -p -i -e ""s/scratch_buffer\.gl\.h/scratch_buffer\.gl_h/g"" [.LIB]SCRATCH_BUFFER.H"
$WRITE OUT "$","@[.vms]patch [.LIB]ALLOCA.IN_H [.LIB]ALLOCA.H"
$WRITE OUT "$","@[.vms]patch [.LIB]unicase.IN_H [.LIB]unicase.H"
$WRITE OUT "$","@[.vms]patch [.LIB]uninorm.IN_H [.LIB]uninorm.H"
$WRITE OUT "$","@[.vms]patch [.LIB]unictype.in_h [.LIB]unictype.h"
$WRITE OUT "$","@[.vms]patch [.LIB.MALLOC]scratch_buffer.h [.LIB.MALLOC]scratch_buffer.gl_h"
$ WRITE OUT "$","SET DEF [.LIB.MALLOC]"
$ WRITE OUT "$",MAKE
$ WRITE OUT "$","SET DEF [-]"
$ WRITE OUT "$",MAKE
$ WRITE OUT "$","SET DEF [-.SRC]"
$ WRITE OUT "$",MAKE,"/IGN=WAR"
$ WRITE OUT "$ CURRENT = F$ENVIRONMENT (""DEFAULT"") "
$ WRITE OUT "$","SET DEF [-]"
$ WRITE OUT "$CLAM=CURRENT"
$ WRITE OUT "$OPEN/WRITE OUTT WGET$STARTUP.COM"
$ WRITE OUT "$WRITE OUTT ""DEFINE WGET_SRC ","'","'","CLAM'"" "
$ WRITE OUT "$WRITE OUTT ""WGET:==$", "'","'","CLAM'WGET.EXE"""
$ WRITE OUT "$CLOSE OUTT"
$ WRITE OUT "$WRITE SYS$OUTPUT "" "" "
$ WRITE OUT "$WRITE SYS$OUTPUT ""***************************************************************************** "" "
$ WRITE OUT "$WRITE SYS$OUTPUT ""Compilation is completed."" "
$ WRITE OUT "$WRITE SYS$OUTPUT ""WGET$STARTUP.COM is created. "" "
$ WRITE OUT "$WRITE SYS$OUTPUT ""This file setups all logicals needed."" " 
$ WRITE OUT "$WRITE SYS$OUTPUT ""It should be executed before using WGET. "" "
$ WRITE OUT "$WRITE SYS$OUTPUT ""***************************************************************************** "" "
$CLOSE OUT 
$! BUILD.COM finished
$ WRITE SYS$OUTPUT "BUILD.COM has been created"
$!
$!
$COPY SYS$INPUT [.SRC]CONFIG.H
/* src/config.h.in.  Generated from configure.ac by autoheader.  */

/* Witness that <config.h> has been included.  */
#define _GL_CONFIG_H_INCLUDED 1


/* Define if access does not correctly handle trailing slashes. */
#undef ACCESS_TRAILING_SLASH_BUG

/* Define if building universal (internal helper macro) */
#undef AC_APPLE_UNIVERSAL_BUILD

/* Define if no multithread safety and no multithreading is desired. */
#define AVOID_ANY_THREADS

/* Define to the number of bits in type 'ptrdiff_t'. */
#define BITSIZEOF_PTRDIFF_T 32

/* Define to the number of bits in type 'sig_atomic_t'. */
#define BITSIZEOF_SIG_ATOMIC_T 32

/* Define to the number of bits in type 'size_t'. */
#define BITSIZEOF_SIZE_T 32

/* Define to the number of bits in type 'wchar_t'. */
#define BITSIZEOF_WCHAR_T 4

/* Define to the number of bits in type 'wint_t'. */
#define BITSIZEOF_WINT_T 32

/* Define to 1 if using 'alloca.c'. */
#undef C_ALLOCA

/* the name of the file descriptor member of DIR */
#undef DIR_FD_MEMBER_NAME

#ifdef DIR_FD_MEMBER_NAME
# define DIR_TO_FD(Dir_p) ((Dir_p)->DIR_FD_MEMBER_NAME)
#else
# define DIR_TO_FD(Dir_p) -1
#endif


/* Define to 1 if // is a file system root distinct from /. */
#undef DOUBLE_SLASH_IS_DISTINCT_ROOT

/* Define if struct dirent has a member d_ino that actually works. */
#undef D_INO_IN_DIRENT

/* Define if you want the debug output support compiled in. */
#define ENABLE_DEBUG 1

/* Define if you want the HTTP Digest Authorization compiled in. */
#define ENABLE_DIGEST 1

/* Define if IPv6 support is enabled. */
//#define ENABLE_IPV6 1

/* Define if IRI support is enabled. */
#define ENABLE_IRI 1

/* Define to 1 if translation of program messages to the user's native
   language is requested. */
//#define ENABLE_NLS 0

/* Define if you want the NTLM authorization support compiled in. */
#define ENABLE_NTLM 1

/* Define if you want Opie support for FTP compiled in. */
#define ENABLE_OPIE 1

/* Define if you want file meta-data storing into POSIX Extended Attributes
   compiled in. */
#undef ENABLE_XATTR

/* Define this to 1 if F_DUPFD behavior does not match POSIX */
#undef FCNTL_DUPFD_BUGGY

/* Define to nothing if C supports flexible array members, and to 1 if it does
   not. That way, with a declaration like 'struct s { int n; short
   d[FLEXIBLE_ARRAY_MEMBER]; };', the struct hack can be used with pre-C99
   compilers. Use 'FLEXSIZEOF (struct s, d, N * sizeof (short))' to calculate
   the size in bytes of such a struct containing an N-element array. */
#define FLEXIBLE_ARRAY_MEMBER 1

/* Define to 1 if fopen() fails to recognize a trailing slash. */
#undef FOPEN_TRAILING_SLASH_BUG

/* Define to 1 if the system's ftello function has the Solaris bug. */
#undef FTELLO_BROKEN_AFTER_SWITCHING_FROM_READ_TO_WRITE

/* Define to 1 if the system's ftello function has the macOS bug. */
#undef FTELLO_BROKEN_AFTER_UNGETC

/* Define to 1 if fflush is known to work on stdin as per POSIX.1-2008, 0 if
   fflush is known to not work, -1 if unknown. */
#undef FUNC_FFLUSH_STDIN

/* Define to 1 if mkdir mistakenly creates a directory given with a trailing
   dot component. */
#undef FUNC_MKDIR_DOT_BUG

/* Define to 1 if nl_langinfo (YESEXPR) returns a non-empty string. */
#undef FUNC_NL_LANGINFO_YESEXPR_WORKS

/* Define to 1 if realpath() can malloc memory, always gives an absolute path,
   and handles a trailing slash correctly. */
#undef FUNC_REALPATH_NEARLY_WORKS

/* Define to 1 if realpath() can malloc memory, always gives an absolute path,
   and handles leading slashes and a trailing slash correctly. */
#define FUNC_REALPATH_WORKS 1

/* Define to 1 if ungetc is broken when used on arbitrary bytes. */
#undef FUNC_UNGETC_BROKEN

/* Define to 1 if futimesat mishandles a NULL file name. */
#undef FUTIMESAT_NULL_BUG

/* Define to 1 if this is a fuzzing build */
#undef FUZZING

/* Define to the type of elements in the array argument to 'getgroups'.
   Usually this is either 'int' or 'gid_t'. */
#define GETGROUPS_T gid_t

/* Define this to 1 if getgroups(0,NULL) does not return the number of groups.
   */
#undef GETGROUPS_ZERO_BUG

/* Define this to 'void' or 'struct timezone' to match the system's
   declaration of the second argument to gettimeofday. */
#define GETTIMEOFDAY_TIMEZONE void

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module canonicalize shall be considered present. */
#undef GNULIB_CANONICALIZE

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module canonicalize-lgpl shall be considered present. */
#undef GNULIB_CANONICALIZE_LGPL

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module dirname shall be considered present. */
#undef GNULIB_DIRNAME

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module fdopendir shall be considered present. */
#undef GNULIB_FDOPENDIR

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module fd-safer-flag shall be considered present. */
#undef GNULIB_FD_SAFER_FLAG

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module fflush shall be considered present. */
#undef GNULIB_FFLUSH

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module fnmatch-gnu shall be considered present. */
#undef GNULIB_FNMATCH_GNU

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module fopen-gnu shall be considered present. */
#undef GNULIB_FOPEN_GNU

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module fscanf shall be considered present. */
#undef GNULIB_FSCANF

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module getcwd shall be considered present. */
#undef GNULIB_GETCWD

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module isblank shall be considered present. */
#undef GNULIB_ISBLANK

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module lock shall be considered present. */
#undef GNULIB_LOCK

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module mkostemp shall be considered present. */
#undef GNULIB_MKOSTEMP

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module msvc-nothrow shall be considered present. */
#undef GNULIB_MSVC_NOTHROW

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module openat shall be considered present. */
#undef GNULIB_OPENAT

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module pipe2-safer shall be considered present. */
#undef GNULIB_PIPE2_SAFER

/* Define to 1 if printf and friends should be labeled with attribute
   "__gnu_printf__" instead of "__printf__" */
#undef GNULIB_PRINTF_ATTRIBUTE_FLAVOR_GNU

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module reallocarray shall be considered present. */
#define GNULIB_REALLOCARRAY 1

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module scanf shall be considered present. */
#undef GNULIB_SCANF

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module sigpipe shall be considered present. */
#undef GNULIB_SIGPIPE

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module snprintf shall be considered present. */
#undef GNULIB_SNPRINTF

/* Define to 1 if you want the FILE stream functions getc, putc, etc. to use
   unlocked I/O if available, throughout the package. Unlocked I/O can improve
   performance, sometimes dramatically. But unlocked I/O is safe only in
   single-threaded programs, as well as in multithreaded programs for which
   you can guarantee that every FILE stream, including stdin, stdout, stderr,
   is used only in a single thread. */
#define GNULIB_STDIO_SINGLE_THREAD 1

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module strerror shall be considered present. */
#undef GNULIB_STRERROR

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module strerror_r-posix shall be considered present. */
#undef GNULIB_STRERROR_R_POSIX

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module tempname shall be considered present. */
#undef GNULIB_TEMPNAME

/* Define to 1 when the gnulib module accept should be tested. */
#undef GNULIB_TEST_ACCEPT

/* Define to 1 when the gnulib module access should be tested. */
#undef GNULIB_TEST_ACCESS

/* Define to 1 when the gnulib module bind should be tested. */
#undef GNULIB_TEST_BIND

/* Define to 1 when the gnulib module btoc32 should be tested. */
#undef GNULIB_TEST_BTOC32

/* Define to 1 when the gnulib module btowc should be tested. */
#undef GNULIB_TEST_BTOWC

/* Define to 1 when the gnulib module c32isalnum should be tested. */
#undef GNULIB_TEST_C32ISALNUM

/* Define to 1 when the gnulib module c32isalpha should be tested. */
#undef GNULIB_TEST_C32ISALPHA

/* Define to 1 when the gnulib module c32isblank should be tested. */
#undef GNULIB_TEST_C32ISBLANK

/* Define to 1 when the gnulib module c32iscntrl should be tested. */
#undef GNULIB_TEST_C32ISCNTRL

/* Define to 1 when the gnulib module c32isdigit should be tested. */
#undef GNULIB_TEST_C32ISDIGIT

/* Define to 1 when the gnulib module c32isgraph should be tested. */
#undef GNULIB_TEST_C32ISGRAPH

/* Define to 1 when the gnulib module c32islower should be tested. */
#undef GNULIB_TEST_C32ISLOWER

/* Define to 1 when the gnulib module c32isprint should be tested. */
#undef GNULIB_TEST_C32ISPRINT

/* Define to 1 when the gnulib module c32ispunct should be tested. */
#undef GNULIB_TEST_C32ISPUNCT

/* Define to 1 when the gnulib module c32isspace should be tested. */
#undef GNULIB_TEST_C32ISSPACE

/* Define to 1 when the gnulib module c32isupper should be tested. */
#undef GNULIB_TEST_C32ISUPPER

/* Define to 1 when the gnulib module c32isxdigit should be tested. */
#undef GNULIB_TEST_C32ISXDIGIT

/* Define to 1 when the gnulib module c32tolower should be tested. */
#undef GNULIB_TEST_C32TOLOWER

/* Define to 1 when the gnulib module c32width should be tested. */
#undef GNULIB_TEST_C32WIDTH

/* Define to 1 when the gnulib module c32_apply_type_test should be tested. */
#undef GNULIB_TEST_C32_APPLY_TYPE_TEST

/* Define to 1 when the gnulib module c32_get_type_test should be tested. */
#undef GNULIB_TEST_C32_GET_TYPE_TEST

/* Define to 1 when the gnulib module calloc-gnu should be tested. */
#undef GNULIB_TEST_CALLOC_GNU

/* Define to 1 when the gnulib module calloc-posix should be tested. */
#undef GNULIB_TEST_CALLOC_POSIX

/* Define to 1 when the gnulib module canonicalize should be tested. */
#undef GNULIB_TEST_CANONICALIZE

/* Define to 1 when the gnulib module canonicalize_file_name should be tested.
   */
#undef GNULIB_TEST_CANONICALIZE_FILE_NAME

/* Define to 1 when the gnulib module chdir should be tested. */
#undef GNULIB_TEST_CHDIR

/* Define to 1 when the gnulib module cloexec should be tested. */
#undef GNULIB_TEST_CLOEXEC

/* Define to 1 when the gnulib module close should be tested. */
#undef GNULIB_TEST_CLOSE

/* Define to 1 when the gnulib module closedir should be tested. */
#undef GNULIB_TEST_CLOSEDIR

/* Define to 1 when the gnulib module connect should be tested. */
#undef GNULIB_TEST_CONNECT

/* Define to 1 when the gnulib module dirfd should be tested. */
#undef GNULIB_TEST_DIRFD

/* Define to 1 when the gnulib module dup should be tested. */
#undef GNULIB_TEST_DUP

/* Define to 1 when the gnulib module dup2 should be tested. */
#undef GNULIB_TEST_DUP2

/* Define to 1 when the gnulib module environ should be tested. */
#undef GNULIB_TEST_ENVIRON

/* Define to 1 when the gnulib module fchdir should be tested. */
#undef GNULIB_TEST_FCHDIR

/* Define to 1 when the gnulib module fcntl should be tested. */
#undef GNULIB_TEST_FCNTL

/* Define to 1 when the gnulib module fdopendir should be tested. */
#undef GNULIB_TEST_FDOPENDIR

/* Define to 1 when the gnulib module fflush should be tested. */
#undef GNULIB_TEST_FFLUSH

/* Define to 1 when the gnulib module fgetc should be tested. */
#undef GNULIB_TEST_FGETC

/* Define to 1 when the gnulib module fgets should be tested. */
#undef GNULIB_TEST_FGETS

/* Define to 1 when the gnulib module fnmatch should be tested. */
#undef GNULIB_TEST_FNMATCH

/* Define to 1 when the gnulib module fopen should be tested. */
#undef GNULIB_TEST_FOPEN

/* Define to 1 when the gnulib module fopen-gnu should be tested. */
#undef GNULIB_TEST_FOPEN_GNU

/* Define to 1 when the gnulib module fprintf should be tested. */
#undef GNULIB_TEST_FPRINTF

/* Define to 1 when the gnulib module fpurge should be tested. */
#undef GNULIB_TEST_FPURGE

/* Define to 1 when the gnulib module fputc should be tested. */
#undef GNULIB_TEST_FPUTC

/* Define to 1 when the gnulib module fputs should be tested. */
#undef GNULIB_TEST_FPUTS

/* Define to 1 when the gnulib module fread should be tested. */
#undef GNULIB_TEST_FREAD

/* Define to 1 when the gnulib module free-posix should be tested. */
#undef GNULIB_TEST_FREE_POSIX

/* Define to 1 when the gnulib module fscanf should be tested. */
#undef GNULIB_TEST_FSCANF

/* Define to 1 when the gnulib module fseek should be tested. */
#undef GNULIB_TEST_FSEEK

/* Define to 1 when the gnulib module fseeko should be tested. */
#undef GNULIB_TEST_FSEEKO

/* Define to 1 when the gnulib module fstat should be tested. */
#undef GNULIB_TEST_FSTAT

/* Define to 1 when the gnulib module fstatat should be tested. */
#undef GNULIB_TEST_FSTATAT

/* Define to 1 when the gnulib module ftell should be tested. */
#undef GNULIB_TEST_FTELL

/* Define to 1 when the gnulib module ftello should be tested. */
#undef GNULIB_TEST_FTELLO

/* Define to 1 when the gnulib module futimens should be tested. */
#undef GNULIB_TEST_FUTIMENS

/* Define to 1 when the gnulib module fwrite should be tested. */
#undef GNULIB_TEST_FWRITE

/* Define to 1 when the gnulib module getaddrinfo should be tested. */
#undef GNULIB_TEST_GETADDRINFO

/* Define to 1 when the gnulib module getc should be tested. */
#undef GNULIB_TEST_GETC

/* Define to 1 when the gnulib module getchar should be tested. */
#undef GNULIB_TEST_GETCHAR

/* Define to 1 when the gnulib module getcwd should be tested. */
#undef GNULIB_TEST_GETCWD

/* Define to 1 when the gnulib module getdelim should be tested. */
#undef GNULIB_TEST_GETDELIM

/* Define to 1 when the gnulib module getdtablesize should be tested. */
#undef GNULIB_TEST_GETDTABLESIZE

/* Define to 1 when the gnulib module getgroups should be tested. */
#undef GNULIB_TEST_GETGROUPS

/* Define to 1 when the gnulib module getline should be tested. */
#undef GNULIB_TEST_GETLINE

/* Define to 1 when the gnulib module getopt-posix should be tested. */
#undef GNULIB_TEST_GETOPT_POSIX

/* Define to 1 when the gnulib module getpass should be tested. */
#undef GNULIB_TEST_GETPASS

/* Define to 1 when the gnulib module getpass-gnu should be tested. */
#undef GNULIB_TEST_GETPASS_GNU

/* Define to 1 when the gnulib module getpeername should be tested. */
#undef GNULIB_TEST_GETPEERNAME

/* Define to 1 when the gnulib module getprogname should be tested. */
#undef GNULIB_TEST_GETPROGNAME

/* Define to 1 when the gnulib module getrandom should be tested. */
#undef GNULIB_TEST_GETRANDOM

/* Define to 1 when the gnulib module getsockname should be tested. */
#undef GNULIB_TEST_GETSOCKNAME

/* Define to 1 when the gnulib module gettimeofday should be tested. */
#undef GNULIB_TEST_GETTIMEOFDAY

/* Define to 1 when the gnulib module group-member should be tested. */
#undef GNULIB_TEST_GROUP_MEMBER

/* Define to 1 when the gnulib module ioctl should be tested. */
#undef GNULIB_TEST_IOCTL

/* Define to 1 when the gnulib module iswblank should be tested. */
#undef GNULIB_TEST_ISWBLANK

/* Define to 1 when the gnulib module iswctype should be tested. */
#undef GNULIB_TEST_ISWCTYPE

/* Define to 1 when the gnulib module iswdigit should be tested. */
#undef GNULIB_TEST_ISWDIGIT

/* Define to 1 when the gnulib module iswpunct should be tested. */
#undef GNULIB_TEST_ISWPUNCT

/* Define to 1 when the gnulib module iswxdigit should be tested. */
#undef GNULIB_TEST_ISWXDIGIT

/* Define to 1 when the gnulib module link should be tested. */
#undef GNULIB_TEST_LINK

/* Define to 1 when the gnulib module listen should be tested. */
#undef GNULIB_TEST_LISTEN

/* Define to 1 when the gnulib module localeconv should be tested. */
#undef GNULIB_TEST_LOCALECONV

/* Define to 1 when the gnulib module lseek should be tested. */
#undef GNULIB_TEST_LSEEK

/* Define to 1 when the gnulib module lstat should be tested. */
#undef GNULIB_TEST_LSTAT

/* Define to 1 when the gnulib module malloc-gnu should be tested. */
#undef GNULIB_TEST_MALLOC_GNU

/* Define to 1 when the gnulib module malloc-posix should be tested. */
#undef GNULIB_TEST_MALLOC_POSIX

/* Define to 1 when the gnulib module mbrtoc32 should be tested. */
#undef GNULIB_TEST_MBRTOC32

/* Define to 1 when the gnulib module mbrtowc should be tested. */
#undef GNULIB_TEST_MBRTOWC

/* Define to 1 when the gnulib module mbsinit should be tested. */
#undef GNULIB_TEST_MBSINIT

/* Define to 1 when the gnulib module mbsrtoc32s should be tested. */
#undef GNULIB_TEST_MBSRTOC32S

/* Define to 1 when the gnulib module mbsrtowcs should be tested. */
#undef GNULIB_TEST_MBSRTOWCS

/* Define to 1 when the gnulib module mbszero should be tested. */
#undef GNULIB_TEST_MBSZERO

/* Define to 1 when the gnulib module mbtowc should be tested. */
#undef GNULIB_TEST_MBTOWC

/* Define to 1 when the gnulib module memchr should be tested. */
#undef GNULIB_TEST_MEMCHR

/* Define to 1 when the gnulib module mempcpy should be tested. */
#undef GNULIB_TEST_MEMPCPY

/* Define to 1 when the gnulib module memrchr should be tested. */
#undef GNULIB_TEST_MEMRCHR

/* Define to 1 when the gnulib module mkdir should be tested. */
#undef GNULIB_TEST_MKDIR

/* Define to 1 when the gnulib module mkostemp should be tested. */
#undef GNULIB_TEST_MKOSTEMP

/* Define to 1 when the gnulib module mkstemp should be tested. */
#undef GNULIB_TEST_MKSTEMP

/* Define to 1 when the gnulib module mktime should be tested. */
#undef GNULIB_TEST_MKTIME

/* Define to 1 when the gnulib module nanosleep should be tested. */
#undef GNULIB_TEST_NANOSLEEP

/* Define to 1 when the gnulib module nl_langinfo should be tested. */
#undef GNULIB_TEST_NL_LANGINFO

/* Define to 1 when the gnulib module open should be tested. */
#undef GNULIB_TEST_OPEN

/* Define to 1 when the gnulib module openat should be tested. */
#undef GNULIB_TEST_OPENAT

/* Define to 1 when the gnulib module opendir should be tested. */
#undef GNULIB_TEST_OPENDIR

/* Define to 1 when the gnulib module pipe should be tested. */
#undef GNULIB_TEST_PIPE

/* Define to 1 when the gnulib module pipe2 should be tested. */
#undef GNULIB_TEST_PIPE2

/* Define to 1 when the gnulib module posix_spawn should be tested. */
#undef GNULIB_TEST_POSIX_SPAWN

/* Define to 1 when the gnulib module posix_spawnattr_destroy should be
   tested. */
#undef GNULIB_TEST_POSIX_SPAWNATTR_DESTROY

/* Define to 1 when the gnulib module posix_spawnattr_init should be tested.
   */
#undef GNULIB_TEST_POSIX_SPAWNATTR_INIT

/* Define to 1 when the gnulib module posix_spawnattr_setflags should be
   tested. */
#undef GNULIB_TEST_POSIX_SPAWNATTR_SETFLAGS

/* Define to 1 when the gnulib module posix_spawnattr_setpgroup should be
   tested. */
#undef GNULIB_TEST_POSIX_SPAWNATTR_SETPGROUP

/* Define to 1 when the gnulib module posix_spawnattr_setsigmask should be
   tested. */
#undef GNULIB_TEST_POSIX_SPAWNATTR_SETSIGMASK

/* Define to 1 when the gnulib module posix_spawnp should be tested. */
#undef GNULIB_TEST_POSIX_SPAWNP

/* Define to 1 when the gnulib module posix_spawn_file_actions_addchdir should
   be tested. */
#undef GNULIB_TEST_POSIX_SPAWN_FILE_ACTIONS_ADDCHDIR

/* Define to 1 when the gnulib module posix_spawn_file_actions_addclose should
   be tested. */
#undef GNULIB_TEST_POSIX_SPAWN_FILE_ACTIONS_ADDCLOSE

/* Define to 1 when the gnulib module posix_spawn_file_actions_adddup2 should
   be tested. */
#undef GNULIB_TEST_POSIX_SPAWN_FILE_ACTIONS_ADDDUP2

/* Define to 1 when the gnulib module posix_spawn_file_actions_addopen should
   be tested. */
#undef GNULIB_TEST_POSIX_SPAWN_FILE_ACTIONS_ADDOPEN

/* Define to 1 when the gnulib module posix_spawn_file_actions_destroy should
   be tested. */
#undef GNULIB_TEST_POSIX_SPAWN_FILE_ACTIONS_DESTROY

/* Define to 1 when the gnulib module posix_spawn_file_actions_init should be
   tested. */
#undef GNULIB_TEST_POSIX_SPAWN_FILE_ACTIONS_INIT

/* Define to 1 when the gnulib module printf should be tested. */
#undef GNULIB_TEST_PRINTF

/* Define to 1 when the gnulib module pselect should be tested. */
#undef GNULIB_TEST_PSELECT

/* Define to 1 when the gnulib module pthread_sigmask should be tested. */
#undef GNULIB_TEST_PTHREAD_SIGMASK

/* Define to 1 when the gnulib module putc should be tested. */
#undef GNULIB_TEST_PUTC

/* Define to 1 when the gnulib module putchar should be tested. */
#undef GNULIB_TEST_PUTCHAR

/* Define to 1 when the gnulib module puts should be tested. */
#undef GNULIB_TEST_PUTS

/* Define to 1 when the gnulib module raise should be tested. */
#undef GNULIB_TEST_RAISE

/* Define to 1 when the gnulib module rawmemchr should be tested. */
#undef GNULIB_TEST_RAWMEMCHR

/* Define to 1 when the gnulib module readdir should be tested. */
#undef GNULIB_TEST_READDIR

/* Define to 1 when the gnulib module readlink should be tested. */
#undef GNULIB_TEST_READLINK

/* Define to 1 when the gnulib module reallocarray should be tested. */
#undef GNULIB_TEST_REALLOCARRAY

/* Define to 1 when the gnulib module realloc-gnu should be tested. */
#undef GNULIB_TEST_REALLOC_GNU

/* Define to 1 when the gnulib module realloc-posix should be tested. */
#undef GNULIB_TEST_REALLOC_POSIX

/* Define to 1 when the gnulib module realpath should be tested. */
#undef GNULIB_TEST_REALPATH

/* Define to 1 when the gnulib module recv should be tested. */
#undef GNULIB_TEST_RECV

/* Define to 1 when the gnulib module rename should be tested. */
#undef GNULIB_TEST_RENAME

/* Define to 1 when the gnulib module rewinddir should be tested. */
#undef GNULIB_TEST_REWINDDIR

/* Define to 1 when the gnulib module rmdir should be tested. */
#undef GNULIB_TEST_RMDIR

/* Define to 1 when the gnulib module scanf should be tested. */
#undef GNULIB_TEST_SCANF

/* Define to 1 when the gnulib module secure_getenv should be tested. */
#undef GNULIB_TEST_SECURE_GETENV

/* Define to 1 when the gnulib module select should be tested. */
#undef GNULIB_TEST_SELECT

/* Define to 1 when the gnulib module send should be tested. */
#undef GNULIB_TEST_SEND

/* Define to 1 when the gnulib module setlocale_null should be tested. */
#undef GNULIB_TEST_SETLOCALE_NULL

/* Define to 1 when the gnulib module setsockopt should be tested. */
#undef GNULIB_TEST_SETSOCKOPT

/* Define to 1 when the gnulib module sigaction should be tested. */
#undef GNULIB_TEST_SIGACTION

/* Define to 1 when the gnulib module sigprocmask should be tested. */
#undef GNULIB_TEST_SIGPROCMASK

/* Define to 1 when the gnulib module snprintf should be tested. */
#undef GNULIB_TEST_SNPRINTF

/* Define to 1 when the gnulib module socket should be tested. */
#undef GNULIB_TEST_SOCKET

/* Define to 1 when the gnulib module stat should be tested. */
#undef GNULIB_TEST_STAT

/* Define to 1 when the gnulib module stpcpy should be tested. */
#undef GNULIB_TEST_STPCPY

/* Define to 1 when the gnulib module strchrnul should be tested. */
#undef GNULIB_TEST_STRCHRNUL

/* Define to 1 when the gnulib module strdup should be tested. */
#undef GNULIB_TEST_STRDUP

/* Define to 1 when the gnulib module strerror should be tested. */
#undef GNULIB_TEST_STRERROR

/* Define to 1 when the gnulib module strerror_r should be tested. */
#undef GNULIB_TEST_STRERROR_R

/* Define to 1 when the gnulib module strndup should be tested. */
#undef GNULIB_TEST_STRNDUP

/* Define to 1 when the gnulib module strnlen should be tested. */
#undef GNULIB_TEST_STRNLEN

/* Define to 1 when the gnulib module strpbrk should be tested. */
#undef GNULIB_TEST_STRPBRK

/* Define to 1 when the gnulib module strptime should be tested. */
#undef GNULIB_TEST_STRPTIME

/* Define to 1 when the gnulib module strtok_r should be tested. */
#undef GNULIB_TEST_STRTOK_R

/* Define to 1 when the gnulib module strtol should be tested. */
#undef GNULIB_TEST_STRTOL

/* Define to 1 when the gnulib module strtoll should be tested. */
#undef GNULIB_TEST_STRTOLL

/* Define to 1 when the gnulib module symlink should be tested. */
#undef GNULIB_TEST_SYMLINK

/* Define to 1 when the gnulib module timegm should be tested. */
#undef GNULIB_TEST_TIMEGM

/* Define to 1 when the gnulib module time_r should be tested. */
#undef GNULIB_TEST_TIME_R

/* Define to 1 when the gnulib module uninorm/u8-normalize should be tested.
   */
#undef GNULIB_TEST_UNINORM_U8_NORMALIZE

/* Define to 1 when the gnulib module unlink should be tested. */
#undef GNULIB_TEST_UNLINK

/* Define to 1 when the gnulib module utime should be tested. */
#undef GNULIB_TEST_UTIME

/* Define to 1 when the gnulib module vasprintf should be tested. */
#undef GNULIB_TEST_VASPRINTF

/* Define to 1 when the gnulib module vfprintf should be tested. */
#undef GNULIB_TEST_VFPRINTF

/* Define to 1 when the gnulib module vprintf should be tested. */
#undef GNULIB_TEST_VPRINTF

/* Define to 1 when the gnulib module vsnprintf should be tested. */
#undef GNULIB_TEST_VSNPRINTF

/* Define to 1 when the gnulib module waitpid should be tested. */
#undef GNULIB_TEST_WAITPID

/* Define to 1 when the gnulib module wcrtomb should be tested. */
#undef GNULIB_TEST_WCRTOMB

/* Define to 1 when the gnulib module wctype should be tested. */
#undef GNULIB_TEST_WCTYPE

/* Define to 1 when the gnulib module wcwidth should be tested. */
#undef GNULIB_TEST_WCWIDTH

/* Define to 1 when the gnulib module wmemchr should be tested. */
#undef GNULIB_TEST_WMEMCHR

/* Define to 1 when the gnulib module wmempcpy should be tested. */
#undef GNULIB_TEST_WMEMPCPY

/* Define to 1 when the gnulib module write should be tested. */
#undef GNULIB_TEST_WRITE

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module unistr/u8-mbtouc-unsafe shall be considered
   present. */
#undef GNULIB_UNISTR_U8_MBTOUC_UNSAFE

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module unistr/u8-uctomb shall be considered present. */
#undef GNULIB_UNISTR_U8_UCTOMB

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module xalloc shall be considered present. */
#define GNULIB_XALLOC 1

/* Define to a C preprocessor expression that evaluates to 1 or 0, depending
   whether the gnulib module xalloc-die shall be considered present. */
#define GNULIB_XALLOC_DIE 1

/* Define to 1 if you have 'alloca' after including <alloca.h>, a header that
   may be supplied by this distribution. */
#undef HAVE_ALLOCA

/* Define to 1 if <alloca.h> works. */
#undef HAVE_ALLOCA_H

/* Define to 1 if you have the <arpa/inet.h> header file. */
#define HAVE_ARPA_INET_H 1

/* Define to 1 if you have the <bcrypt.h> header file. */
#undef HAVE_BCRYPT_H 

/* Define to 1 if you have the <bp-sym.h> header file. */
#undef HAVE_BP_SYM_H

/* Define to 1 if you have the 'btowc' function. */
#undef HAVE_BTOWC

/* Define to 1 if nanosleep mishandles large arguments. */
#undef HAVE_BUG_BIG_NANOSLEEP

/* Define to 1 if you have the <byteswap.h> header file. */
#undef HAVE_BYTESWAP_H

/* Define to 1 if you have the 'canonicalize_file_name' function. */
#undef HAVE_CANONICALIZE_FILE_NAME

/* Define to 1 if you have the `catgets' function. */
#undef HAVE_CATGETS

/* Define to 1 if you have the Mac OS X function
   CFLocaleCopyPreferredLanguages in the CoreFoundation framework. */
#undef HAVE_CFLOCALECOPYPREFERREDLANGUAGES

/* Define to 1 if you have the Mac OS X function CFPreferencesCopyAppValue in
   the CoreFoundation framework. */
#undef HAVE_CFPREFERENCESCOPYAPPVALUE

/* Define to 1 if you have the 'clock_getres' function. */
#define HAVE_CLOCK_GETRES 1

/* Define to 1 if you have the 'clock_gettime' function. */
#define HAVE_CLOCK_GETTIME 1

/* Define to 1 if you have the 'clock_settime' function. */
#define HAVE_CLOCK_SETTIME 1

/* Define to 1 if you have the 'closedir' function. */
#define HAVE_CLOSEDIR 1

/* Define to 1 if you have the 'confstr' function. */
#define HAVE_CONFSTR 1

/* Define to 1 if you have the <crtdefs.h> header file. */
#undef HAVE_CRTDEFS_H

/* Define to 1 if the alignas and alignof keywords work. */
#undef HAVE_C_ALIGNASOF

/* Define to 1 if bool, true and false work as per C2023. */
#undef HAVE_C_BOOL

/* Define to 1 if the static_assert keyword works. */
#define HAVE_C_STATIC_ASSERT 1

/* Define to 1 if C supports variable-length arrays. */
#undef HAVE_C_VARARRAYS

/* Define if the GNU dcgettext() function is already present or preinstalled.
   */
#undef HAVE_DCGETTEXT

/* Define to 1 if you have the declaration of 'alarm', and to 0 if you don't.
   */
#undef HAVE_DECL_ALARM

/* Define to 1 if you have the declaration of 'clearerr_unlocked', and to 0 if
   you don't. */
#undef HAVE_DECL_CLEARERR_UNLOCKED

/* Define to 1 if you have the declaration of 'dirfd', and to 0 if you don't.
   */
#undef HAVE_DECL_DIRFD

/* Define to 1 if you have the declaration of 'ecvt', and to 0 if you don't.
   */
#undef HAVE_DECL_ECVT

/* Define to 1 if you have the declaration of 'execvpe', and to 0 if you
   don't. */
#undef HAVE_DECL_EXECVPE

/* Define to 1 if you have the declaration of 'fchdir', and to 0 if you don't.
   */
#undef HAVE_DECL_FCHDIR

/* Define to 1 if you have the declaration of 'fcloseall', and to 0 if you
   don't. */
#undef HAVE_DECL_FCLOSEALL

/* Define to 1 if you have the declaration of 'fcvt', and to 0 if you don't.
   */
#undef HAVE_DECL_FCVT

/* Define to 1 if you have the declaration of 'fdopendir', and to 0 if you
   don't. */
#undef HAVE_DECL_FDOPENDIR

/* Define to 1 if you have the declaration of 'feof_unlocked', and to 0 if you
   don't. */
#undef HAVE_DECL_FEOF_UNLOCKED

/* Define to 1 if you have the declaration of 'ferror_unlocked', and to 0 if
   you don't. */
#undef HAVE_DECL_FERROR_UNLOCKED

/* Define to 1 if you have the declaration of 'fflush_unlocked', and to 0 if
   you don't. */
#undef HAVE_DECL_FFLUSH_UNLOCKED

/* Define to 1 if you have the declaration of 'fgets_unlocked', and to 0 if
   you don't. */
#undef HAVE_DECL_FGETS_UNLOCKED

/* Define to 1 if you have the declaration of 'flockfile', and to 0 if you
   don't. */
#define HAVE_DECL_FLOCKFILE 1

/* Define to 1 if you have the declaration of 'fpurge', and to 0 if you don't.
   */
#undef HAVE_DECL_FPURGE

/* Define to 1 if you have the declaration of 'fputc_unlocked', and to 0 if
   you don't. */
#undef HAVE_DECL_FPUTC_UNLOCKED

/* Define to 1 if you have the declaration of 'fputs_unlocked', and to 0 if
   you don't. */
#undef HAVE_DECL_FPUTS_UNLOCKED

/* Define to 1 if you have the declaration of 'fread_unlocked', and to 0 if
   you don't. */
#undef HAVE_DECL_FREAD_UNLOCKED

/* Define to 1 if you have the declaration of 'freeaddrinfo', and to 0 if you
   don't. */
#undef HAVE_DECL_FREEADDRINFO

/* Define to 1 if you have the declaration of 'fseeko', and to 0 if you don't.
   */
#undef HAVE_DECL_FSEEKO

/* Define to 1 if you have the declaration of 'ftello', and to 0 if you don't.
   */
#undef HAVE_DECL_FTELLO

/* Define to 1 if you have the declaration of 'funlockfile', and to 0 if you
   don't. */
#undef HAVE_DECL_FUNLOCKFILE

/* Define to 1 if you have the declaration of 'fwrite_unlocked', and to 0 if
   you don't. */
#undef HAVE_DECL_FWRITE_UNLOCKED

/* Define to 1 if you have the declaration of 'gai_strerror', and to 0 if you
   don't. */
#undef HAVE_DECL_GAI_STRERROR

/* Define to 1 if you have the declaration of 'gai_strerrorA', and to 0 if you
   don't. */
#undef HAVE_DECL_GAI_STRERRORA

/* Define to 1 if you have the declaration of 'gcvt', and to 0 if you don't.
   */
#undef HAVE_DECL_GCVT

/* Define to 1 if you have the declaration of 'getaddrinfo', and to 0 if you
   don't. */
#undef HAVE_DECL_GETADDRINFO

/* Define to 1 if you have the declaration of 'getchar_unlocked', and to 0 if
   you don't. */
#undef HAVE_DECL_GETCHAR_UNLOCKED

/* Define to 1 if you have the declaration of 'getcwd', and to 0 if you don't.
   */
#undef HAVE_DECL_GETCWD

/* Define to 1 if you have the declaration of 'getc_unlocked', and to 0 if you
   don't. */
#undef HAVE_DECL_GETC_UNLOCKED

/* Define to 1 if you have the declaration of 'getdelim', and to 0 if you
   don't. */
#undef HAVE_DECL_GETDELIM

/* Define to 1 if you have the declaration of 'getdtablesize', and to 0 if you
   don't. */
#undef HAVE_DECL_GETDTABLESIZE

/* Define to 1 if you have the declaration of 'getline', and to 0 if you
   don't. */
#undef HAVE_DECL_GETLINE

/* Define to 1 if you have the declaration of 'getnameinfo', and to 0 if you
   don't. */
#undef HAVE_DECL_GETNAMEINFO

/* Define to 1 if you have the declaration of 'getw', and to 0 if you don't.
   */
#undef HAVE_DECL_GETW

/* Define to 1 if you have the declaration of 'h_errno', and to 0 if you
   don't. */
#undef HAVE_DECL_H_ERRNO

/* Define to 1 if you have the declaration of 'inet_ntop', and to 0 if you
   don't. */
#undef HAVE_DECL_INET_NTOP

/* Define to 1 if you have the declaration of 'isblank', and to 0 if you
   don't. */
#undef HAVE_DECL_ISBLANK

/* Define to 1 if you have the declaration of 'iswblank', and to 0 if you
   don't. */
#undef HAVE_DECL_ISWBLANK

/* Define to 1 if you have the declaration of 'localtime_r', and to 0 if you
   don't. */
#undef HAVE_DECL_LOCALTIME_R

/* Define to 1 if you have the declaration of 'mbrtowc', and to 0 if you
   don't. */
#undef HAVE_DECL_MBRTOWC

/* Define to 1 if you have the declaration of 'mbsinit', and to 0 if you
   don't. */
#undef HAVE_DECL_MBSINIT

/* Define to 1 if you have the declaration of 'mbsrtowcs', and to 0 if you
   don't. */
#undef HAVE_DECL_MBSRTOWCS

/* Define to 1 if you have the declaration of 'memrchr', and to 0 if you
   don't. */
#undef HAVE_DECL_MEMRCHR

/* Define to 1 if you have the declaration of 'posix_spawn', and to 0 if you
   don't. */
#undef HAVE_DECL_POSIX_SPAWN

/* Define to 1 if you have the declaration of 'program_invocation_name', and
   to 0 if you don't. */
#undef HAVE_DECL_PROGRAM_INVOCATION_NAME

/* Define to 1 if you have the declaration of 'program_invocation_short_name',
   and to 0 if you don't. */
#undef HAVE_DECL_PROGRAM_INVOCATION_SHORT_NAME

/* Define to 1 if you have the declaration of 'putchar_unlocked', and to 0 if
   you don't. */
#undef HAVE_DECL_PUTCHAR_UNLOCKED

/* Define to 1 if you have the declaration of 'putc_unlocked', and to 0 if you
   don't. */
#undef HAVE_DECL_PUTC_UNLOCKED

/* Define to 1 if you have the declaration of 'putw', and to 0 if you don't.
   */
#undef HAVE_DECL_PUTW

/* Define to 1 if you have the declaration of 'snprintf', and to 0 if you
   don't. */
#undef HAVE_DECL_SNPRINTF

/* Define to 1 if you have the declaration of 'strdup', and to 0 if you don't.
   */
#undef HAVE_DECL_STRDUP

/* Define to 1 if you have the declaration of 'strerror_r', and to 0 if you
   don't. */
#undef HAVE_DECL_STRERROR_R

/* Define to 1 if you have the declaration of 'strncasecmp', and to 0 if you
   don't. */
#undef HAVE_DECL_STRNCASECMP

/* Define to 1 if you have the declaration of 'strndup', and to 0 if you
   don't. */
#undef HAVE_DECL_STRNDUP

/* Define to 1 if you have the declaration of 'strnlen', and to 0 if you
   don't. */
#undef HAVE_DECL_STRNLEN

/* Define to 1 if you have the declaration of 'strtok_r', and to 0 if you
   don't. */
#undef HAVE_DECL_STRTOK_R

/* Define to 1 if you have the declaration of 'towlower', and to 0 if you
   don't. */
#undef HAVE_DECL_TOWLOWER

/* Define to 1 if you have the declaration of 'vsnprintf', and to 0 if you
   don't. */
#undef HAVE_DECL_VSNPRINTF

/* Define to 1 if you have the declaration of 'wcrtomb', and to 0 if you
   don't. */
#undef HAVE_DECL_WCRTOMB

/* Define to 1 if you have the declaration of 'wcsdup', and to 0 if you don't.
   */
#undef HAVE_DECL_WCSDUP

/* Define to 1 if you have the declaration of 'wcwidth', and to 0 if you
   don't. */
#undef HAVE_DECL_WCWIDTH

/* Define to 1 if you have the declaration of '_fseeki64', and to 0 if you
   don't. */
#undef HAVE_DECL__FSEEKI64

/* Define to 1 if you have the declaration of '_snprintf', and to 0 if you
   don't. */
#undef HAVE_DECL__SNPRINTF

/* Define to 1 if you have the declaration of '__argv', and to 0 if you don't.
   */
#undef HAVE_DECL___ARGV

/* Define to 1 if you have the declaration of '__fsetlocking', and to 0 if you
   don't. */
#undef HAVE_DECL___FSETLOCKING

/* Define to 1 if you have the <dirent.h> header file. */
#define HAVE_DIRENT_H 1

/* Define to 1 if you have the 'dirfd' function. */
#undef HAVE_DIRFD

/* Define to 1 if you have the <dlfcn.h> header file. */
#define HAVE_DLFCN_H 1

/* Define to 1 if you have the 'drand48' function. */
#define HAVE_DRAND48 1

/* Define if you have the declaration of environ. */
#undef HAVE_ENVIRON_DECL

/* Define to 1 if you have the `error' function. */
#define HAVE_ERROR 1

/* Define to 1 if you have the <error.h> header file. */
#define HAVE_ERROR_H 1

/* Define to 1 if you have the `faccessat' function. */
#undef HAVE_FACCESSAT

/* Define to 1 if you have the 'fchdir' function. */
#undef HAVE_FCHDIR

/* Define to 1 if you have the 'fcntl' function. */
#define HAVE_FCNTL 1

/* Define to 1 if you have the 'fdopendir' function. */
#undef HAVE_FDOPENDIR

/* Define to 1 if you have the <features.h> header file. */
#undef HAVE_FEATURES_H

/* Define to 1 if you have the 'flock' function. */
//#define HAVE_FLOCK 1

/* Define to 1 if you have the 'flockfile' function. */
#define HAVE_FLOCKFILE 1

/* Define to 1 if you have the 'fmemopen' function. */
#undef HAVE_FMEMOPEN

/* Define to 1 if you have the 'fnmatch' function. */
#undef HAVE_FNMATCH

//CHAPG

/* Define to 1 if you have the <fnmatch.h> header file. */
#undef HAVE_FNMATCH_H

/* Define to 1 if you have the 'fpurge' function. */
#undef HAVE_FPURGE

/* Define if the 'free' function is guaranteed to preserve errno. */
#undef HAVE_FREE_POSIX

/* Define to 1 if fseeko (and ftello) are declared in stdio.h. */
#undef HAVE_FSEEKO

/* Define to 1 if you have the 'fstatat' function. */
#undef HAVE_FSTATAT

/* Define to 1 if you have the 'ftello' function. */
#undef HAVE_FTELLO

/* Define to 1 if you have the 'funlockfile' function. */
#undef HAVE_FUNLOCKFILE

/* Define to 1 if you have the `futimens' function. */
#undef HAVE_FUTIMENS

/* Define to 1 if you have the `futimes' function. */
#undef HAVE_FUTIMES

/* Define to 1 if you have the `futimesat' function. */
#undef HAVE_FUTIMESAT

/* Define to 1 if getaddrinfo exists, or to 0 otherwise. */
#undef HAVE_GETADDRINFO

/* Define to 1 if you have the 'getcwd' function. */
#undef HAVE_GETCWD

/* Define to 1 if getcwd works, but with shorter paths than is generally
   tested with the replacement. */
#undef HAVE_GETCWD_SHORTER

/* Define to 1 if you have the `getdelim' function. */
#undef HAVE_GETDELIM

/* Define to 1 if you have the 'getdtablesize' function. */
#undef HAVE_GETDTABLESIZE

/* Define to 1 if you have the 'getegid' function. */
#undef HAVE_GETEGID

/* Define to 1 if you have the 'geteuid' function. */
#undef HAVE_GETEUID

/* Define to 1 if you have the 'getexecname' function. */
#undef HAVE_GETEXECNAME

/* Define to 1 if you have the 'getgid' function. */
#undef HAVE_GETGID

/* Define to 1 if your system has a working `getgroups' function. */
#undef HAVE_GETGROUPS

/* Define to 1 if you have the 'gethostbyname' function. */
#undef HAVE_GETHOSTBYNAME

/* Define to 1 if you have the `getline' function. */
#undef HAVE_GETLINE

/* Define to 1 if you have the <getopt.h> header file. */
#undef HAVE_GETOPT_H

/* Define to 1 if you have the 'getopt_long_only' function. */
#undef HAVE_GETOPT_LONG_ONLY

/* Define to 1 if you have the 'getpagesize' function. */
#undef HAVE_GETPAGESIZE

/* Define to 1 if you have the 'getpass' function. */
#undef HAVE_GETPASS

/* Define to 1 if you have the `getprogname' function. */
#undef HAVE_GETPROGNAME

/* Define to 1 if you have the `getrandom' function. */
#undef HAVE_GETRANDOM

/* Define to 1 if you have the 'getservbyname' function. */
#undef HAVE_GETSERVBYNAME

/* Define if the GNU gettext() function is already present or preinstalled. */
#undef HAVE_GETTEXT

/* Define to 1 if you have the 'gettimeofday' function. */
#undef HAVE_GETTIMEOFDAY

/* Define to 1 if you have the 'getuid' function. */
#undef HAVE_GETUID

/* Define to 1 if you have the 'gnutls_priority_set_direct' function. */
#undef HAVE_GNUTLS_PRIORITY_SET_DIRECT

/* Define if GPGME is available. */
#undef HAVE_GPGME

/* Define if you have the iconv() function and it works. */
#undef HAVE_ICONV

/* Define to 1 if you have the <iconv.h> header file. */
#undef HAVE_ICONV_H

/* Define to 1 if you have the 'inet_ntop' function. */
#undef HAVE_INET_NTOP

/* Define to 1 if the compiler supports one of the keywords 'inline',
   '__inline__', '__inline' and effectively inlines functions marked as such.
   */
#undef HAVE_INLINE

/* Define to 1 if the system has the type 'int64_t'. */
#undef HAVE_INT64_T

/* Define if you have the 'intmax_t' type in <stdint.h> or <inttypes.h>. */
#undef HAVE_INTMAX_T

/* Define to 1 if the system has the type 'intptr_t'. */
#undef HAVE_INTPTR_T

/* Define to 1 if you have the <inttypes.h> header file. */
#undef HAVE_INTTYPES_H

/* Define if <inttypes.h> exists, doesn't clash with <sys/types.h>, and
   declares uintmax_t. */
#undef HAVE_INTTYPES_H_WITH_UINTMAX

/* Define to 1 if you have the 'ioctl' function. */
#undef HAVE_IOCTL

/* Define to 1 if <sys/socket.h> defines AF_INET. */
#undef HAVE_IPV4

/* Define to 1 if <sys/socket.h> defines AF_INET6. */
#undef HAVE_IPV6

/* Define to 1 if you have the 'isatty' function. */
#undef HAVE_ISATTY

/* Define to 1 if you have the 'isblank' function. */
#undef HAVE_ISBLANK

/* Define to 1 if you have the `issetugid' function. */
#undef HAVE_ISSETUGID

/* Define to 1 if you have the `iswblank' function. */
#undef HAVE_ISWBLANK

/* Define to 1 if you have the 'iswcntrl' function. */
#undef HAVE_ISWCNTRL

/* Define to 1 if you have the 'iswctype' function. */
#undef HAVE_ISWCTYPE

/* Define if you have <langinfo.h> and nl_langinfo(CODESET). */
#undef HAVE_LANGINFO_CODESET

/* Define to 1 if you have the <langinfo.h> header file. */
#undef HAVE_LANGINFO_H

/* Define if libcares is available. */
#undef HAVE_LIBCARES

/* Define to 1 if you have the 'dl' library (-ldl). */
#undef HAVE_LIBDL

/* Define to 1 if you have the 'eay32' library (-leay32). */
#undef HAVE_LIBEAY32

/* Define if you have the libgnutls library. */
#undef HAVE_LIBGNUTLS

/* Define to 1 if you have the <libintl.h> header file. */
#undef HAVE_LIBINTL_H

/* Define if libpcre is available. */
#undef HAVE_LIBPCRE

/* Define if libpcre2 is available. */
#undef HAVE_LIBPCRE2

/* Define if using libproxy. */
#undef HAVE_LIBPROXY

/* PSL support enabled */
#undef HAVE_LIBPSL

/* Define if you have the libssl library. */
#define HAVE_LIBSSL

/* Define to 1 if you have the 'ssl32' library (-lssl32). */
#undef HAVE_LIBSSL32

/* Define if you have the libunistring library. */
#undef HAVE_LIBUNISTRING

/* Define if using libuuid. */
#undef HAVE_LIBUUID

/* Define if using zlib. */
#define HAVE_LIBZ 1

/* Define to 1 if the bcrypt library is guaranteed to be present. */
#undef HAVE_LIB_BCRYPT

/* Define to 1 if you have the <limits.h> header file. */
#undef HAVE_LIMITS_H

/* Define to 1 if you have the 'link' function. */
#undef HAVE_LINK

/* Define to 1 if you have 'struct sockaddr_alg' defined. */
#undef HAVE_LINUX_IF_ALG_H

/* Define to 1 if you have the 'localtime_r' function. */
#undef HAVE_LOCALTIME_R

/* Define to 1 if the system has the type 'long long int'. */
#undef HAVE_LONG_LONG_INT

/* Define to 1 if you have the 'lstat' function. */
#undef HAVE_LSTAT

/* Define to 1 if you have the `lutimes' function. */
#undef HAVE_LUTIMES

/* Define to 1 if you have the <malloc.h> header file. */
#undef HAVE_MALLOC_H

/* Define if malloc, realloc, and calloc set errno on allocation failure. */
#undef HAVE_MALLOC_POSIX

/* Define to 1 if mmap()'s MAP_ANONYMOUS flag is available after including
   config.h and <sys/mman.h>. */
#undef HAVE_MAP_ANONYMOUS

/* Define to 1 if you have the 'mbrtowc' function. */
#undef HAVE_MBRTOWC

/* Define to 1 if you have the 'mbsinit' function. */
#undef HAVE_MBSINIT

/* Define to 1 if you have the 'mbsrtowcs' function. */
#undef HAVE_MBSRTOWCS

/* Define to 1 if <wchar.h> declares mbstate_t. */
#undef HAVE_MBSTATE_T

/* Define to 1 if you have the 'mbtowc' function. */
#undef HAVE_MBTOWC

/* Define to 1 if you have the `mempcpy' function. */
#undef HAVE_MEMPCPY

/* Define to 1 if you have the 'memrchr' function. */
#undef HAVE_MEMRCHR

/* Define if using metalink. */
#undef HAVE_METALINK

/* Define to 1 if getcwd minimally works, that is, its result can be trusted
   when it succeeds. */
#undef HAVE_MINIMALLY_WORKING_GETCWD

/* Define to 1 if you have the <minix/config.h> header file. */
#undef HAVE_MINIX_CONFIG_H

/* Define to 1 if <limits.h> defines the MIN and MAX macros. */
#undef HAVE_MINMAX_IN_LIMITS_H

/* Define to 1 if <sys/param.h> defines the MIN and MAX macros. */
#undef HAVE_MINMAX_IN_SYS_PARAM_H

/* Define to 1 if you have the `mkostemp' function. */
#undef HAVE_MKOSTEMP

/* Define to 1 if you have the 'mkstemp' function. */
#undef HAVE_MKSTEMP

/* Define to 1 if you have a working 'mmap' system call. */
#undef HAVE_MMAP

/* Define to 1 if you have the 'mprotect' function. */
#undef HAVE_MPROTECT

/* Define to 1 on MSVC platforms that have the "invalid parameter handler"
   concept. */
#undef HAVE_MSVC_INVALID_PARAMETER_HANDLER

/* Define to 1 if you have the <netdb.h> header file. */
#undef HAVE_NETDB_H

/* Define to 1 if you have the <netinet/in.h> header file. */
#undef HAVE_NETINET_IN_H

/* Use libnettle */
#undef HAVE_NETTLE

/* Define to 1 if you have the `nl_langinfo' function. */
#undef HAVE_NL_LANGINFO

/* Define to 1 if you have the 'openat' function. */
#undef HAVE_OPENAT

/* Define to 1 if you have the 'opendir' function. */
#define HAVE_OPENDIR 1

/* Define to 1 if libcrypto is used for MD5. */
#define HAVE_OPENSSL_MD5 1

/* Define to 1 if you have the <openssl/md5.h> header file. */
#define HAVE_OPENSSL_MD5_H 1

/* Define to 1 if libcrypto is used for SHA1. */
#define HAVE_OPENSSL_SHA1 1

/* Define to 1 if libcrypto is used for SHA256. */
#define HAVE_OPENSSL_SHA256 1

/* Define to 1 if libcrypto is used for SHA512. */
#define HAVE_OPENSSL_SHA512 1

/* Define to 1 if you have the <openssl/sha.h> header file. */
#define HAVE_OPENSSL_SHA_H 1

/* Define to 1 if getcwd works, except it sometimes fails when it shouldn't,
   setting errno to ERANGE, ENAMETOOLONG, or ENOENT. */
#undef HAVE_PARTLY_WORKING_GETCWD

/* Define to 1 if you have the 'pathconf' function. */
#undef HAVE_PATHCONF

/* Define to 1 if you have the <paths.h> header file. */
#undef HAVE_PATHS_H

/* Define to 1 if you have the 'pipe' function. */
#undef HAVE_PIPE

/* Define to 1 if you have the `pipe2' function. */
#undef HAVE_PIPE2

/* Define to 1 if you have the `posix_spawn' function. */
#undef HAVE_POSIX_SPAWN

/* Define to 1 if the system has the type 'posix_spawnattr_t'. */
#undef HAVE_POSIX_SPAWNATTR_T

/* Define to 1 if you have the 'posix_spawn_file_actions_addchdir' function.
   */
#undef HAVE_POSIX_SPAWN_FILE_ACTIONS_ADDCHDIR

/* Define to 1 if you have the `posix_spawn_file_actions_addchdir_np'
   function. */
#undef HAVE_POSIX_SPAWN_FILE_ACTIONS_ADDCHDIR_NP

/* Define to 1 if the system has the type 'posix_spawn_file_actions_t'. */
#undef HAVE_POSIX_SPAWN_FILE_ACTIONS_T

/* Define to 1 if you have the 'pselect' function. */
#undef HAVE_PSELECT

/* Define to 1 if you have the 'psl_latest' function. */
#undef HAVE_PSL_LATEST

/* Define if you have the <pthread.h> header and the POSIX threads API. */
#undef HAVE_PTHREAD_API

/* Define if the <pthread.h> defines PTHREAD_MUTEX_RECURSIVE. */
#undef HAVE_PTHREAD_MUTEX_RECURSIVE

/* Define if the POSIX multithreading library has read/write locks. */
#undef HAVE_PTHREAD_RWLOCK

/* Define if the 'pthread_rwlock_rdlock' function prefers a writer to a
   reader. */
#undef HAVE_PTHREAD_RWLOCK_RDLOCK_PREFER_WRITER

/* Define to 1 if the pthread_sigmask function can be used (despite bugs). */
#undef HAVE_PTHREAD_SIGMASK

/* Define to 1 if you have the <pwd.h> header file. */
#define HAVE_PWD_H 1

/* Define to 1 if you have the 'raise' function. */
#undef HAVE_RAISE

/* Define to 1 if you have the 'random' function. */
#undef HAVE_RANDOM

/* Define to 1 if you have the 'RAND_egd' function. */
#undef HAVE_RAND_EGD

/* Define to 1 if you have the 'rawmemchr' function. */
#undef HAVE_RAWMEMCHR

/* Define to 1 if you have the 'readdir' function. */
#undef HAVE_READDIR

/* Define to 1 if you have the 'readlink' function. */
#undef HAVE_READLINK

/* Define to 1 if you have the `reallocarray' function. */
#undef HAVE_REALLOCARRAY

/* Define to 1 if you have the 'realpath' function. */
#undef HAVE_REALPATH

/* Define to 1 if you have the 'rewinddir' function. */
#undef HAVE_REWINDDIR

/* Define to 1 if the system has the type 'sa_family_t'. */
#undef HAVE_SA_FAMILY_T

/* Define to 1 if you have the <sched.h> header file. */
#undef HAVE_SCHED_H

/* Define to 1 if you have the 'sched_setparam' function. */
#undef HAVE_SCHED_SETPARAM

/* Define to 1 if you have the 'sched_setscheduler' function. */
#undef HAVE_SCHED_SETSCHEDULER

/* Define to 1 if you have the <sdkddkver.h> header file. */
#undef HAVE_SDKDDKVER_H

/* Define to 1 if you have the 'secure_getenv' function. */
#undef HAVE_SECURE_GETENV

/* Define to 1 if you have the 'setdtablesize' function. */
#undef HAVE_SETDTABLESIZE

/* Define to 1 if you have the 'setegid' function. */
#undef HAVE_SETEGID

/* Define to 1 if you have the 'seteuid' function. */
#undef HAVE_SETEUID

/* Define to 1 if you have the 'shutdown' function. */
#undef HAVE_SHUTDOWN

/* Define to 1 if you have the 'sigaction' function. */
#undef HAVE_SIGACTION

/* Define to 1 if you have the 'sigaltstack' function. */
#undef HAVE_SIGALTSTACK

/* Define to 1 if you have the 'sigblock' function. */
#undef HAVE_SIGBLOCK

/* Define to 1 if the system has the type 'siginfo_t'. */
#undef HAVE_SIGINFO_T

/* Define to 1 if you have the 'siginterrupt' function. */
#undef HAVE_SIGINTERRUPT

/* Define to 1 if 'sig_atomic_t' is a signed integer type. */
#undef HAVE_SIGNED_SIG_ATOMIC_T

/* Define to 1 if 'wchar_t' is a signed integer type. */
#undef HAVE_SIGNED_WCHAR_T

/* Define to 1 if 'wint_t' is a signed integer type. */
#undef HAVE_SIGNED_WINT_T

/* Define to 1 if you have the 'sigsetjmp' function. */
#undef HAVE_SIGSETJMP

/* Define to 1 if the system has the type 'sigset_t'. */
#undef HAVE_SIGSET_T

/* Define to 1 if the system has the type 'sig_atomic_t'. */
#undef HAVE_SIG_ATOMIC_T

/* Define to 1 if you have the 'sleep' function. */
#undef HAVE_SLEEP

/* Define to 1 if you have the 'snprintf' function. */
#undef HAVE_SNPRINTF

/* Define if the return value of the snprintf function is the number of of
   bytes (excluding the terminating NUL) that would have been produced if the
   buffer had been large enough. */
#undef HAVE_SNPRINTF_RETVAL_C99

/* Define if the string produced by the snprintf function is always NUL
   terminated. */
#undef HAVE_SNPRINTF_TRUNCATION_C99

/* Define if struct sockaddr_in6 has the sin6_scope_id member */
#undef HAVE_SOCKADDR_IN6_SCOPE_ID

/* Define to 1 if you have the <spawn.h> header file. */
#undef HAVE_SPAWN_H

/* Define to 1 if you have the <stdbool.h> header file. */
#define HAVE_STDBOOL_H 1

/* Define to 1 if you have the <stdckdint.h> header file. */
#undef HAVE_STDCKDINT_H

/* Define to 1 if you have the <stdint.h> header file. */
#define HAVE_STDINT_H 1

/* Define if <stdint.h> exists, doesn't clash with <sys/types.h>, and declares
   uintmax_t. */
#undef HAVE_STDINT_H_WITH_UINTMAX

/* Define to 1 if you have the <stdio_ext.h> header file. */
#undef HAVE_STDIO_EXT_H

/* Define to 1 if you have the <stdio.h> header file. */
#define HAVE_STDIO_H 1

/* Define to 1 if you have the <stdlib.h> header file. */
#define HAVE_STDLIB_H 1

/* Define to 1 if you have the `stpcpy' function. */
#define HAVE_STPCPY 1



/* Define to 1 if you have the 'strcasecmp' function. */
#define HAVE_STRCASECMP 1

/* Define to 1 if you have the `strchrnul' function. */
#define HAVE_STRCHRNUL 1

/* Define to 1 if you have the 'strdup' function. */
#define HAVE_STRDUP 1

/* Define to 1 if you have the `strerror_r' function. */
#undef HAVE_STRERROR_R

/* Define to 1 if you have the <strings.h> header file. */
#define HAVE_STRINGS_H 1

/* Define to 1 if you have the <string.h> header file. */
#define HAVE_STRING_H 1

/* Define to 1 if you have the 'strlcpy' function. */
//#define HAVE_STRLCPY 1

/* Define to 1 if you have the 'strncasecmp' function. */
#define HAVE_STRNCASECMP 1

/* Define to 1 if you have the 'strndup' function. */
#undef HAVE_STRNDUP

/* Define to 1 if you have the 'strnlen' function. */
#undef HAVE_STRNLEN

/* Define to 1 if you have the 'strpbrk' function. */
#undef HAVE_STRPBRK

/* Define to 1 if you have the 'strptime' function. */
#undef HAVE_STRPTIME

/* Define to 1 if you have the 'strtok_r' function. */
#undef HAVE_STRTOK_R

/* Define to 1 if you have the 'strtol' function. */
#define HAVE_STRTOL 1

/* Define to 1 if you have the 'strtoll' function. */
#define HAVE_STRTOLL 1

/* Define to 1 if the system has the type 'struct addrinfo'. */
#define HAVE_STRUCT_ADDRINFO 1

/* Define to 1 if 'l_type' is a member of 'struct flock'. */
#define HAVE_STRUCT_FLOCK_L_TYPE 1

/* Define to 1 if 'decimal_point' is a member of 'struct lconv'. */
#undef HAVE_STRUCT_LCONV_DECIMAL_POINT

/* Define to 1 if 'int_p_cs_precedes' is a member of 'struct lconv'. */
#undef HAVE_STRUCT_LCONV_INT_P_CS_PRECEDES

/* Define to 1 if 'sa_sigaction' is a member of 'struct sigaction'. */
#undef HAVE_STRUCT_SIGACTION_SA_SIGACTION

/* Define to 1 if the system has the type 'struct sockaddr_in6'. */
#define HAVE_STRUCT_SOCKADDR_IN6 1

/* Define to 1 if 'sa_len' is a member of 'struct sockaddr'. */
#define HAVE_STRUCT_SOCKADDR_SA_LEN 1

/* Define to 1 if the system has the type 'struct sockaddr_storage'. */
#undef HAVE_STRUCT_SOCKADDR_STORAGE

/* Define to 1 if 'ss_family' is a member of 'struct sockaddr_storage'. */
#undef HAVE_STRUCT_SOCKADDR_STORAGE_SS_FAMILY

/* Define to 1 if 'st_atimensec' is a member of 'struct stat'. */
#undef HAVE_STRUCT_STAT_ST_ATIMENSEC

/* Define to 1 if 'st_atimespec.tv_nsec' is a member of 'struct stat'. */
#undef HAVE_STRUCT_STAT_ST_ATIMESPEC_TV_NSEC

/* Define to 1 if 'st_atim.st__tim.tv_nsec' is a member of 'struct stat'. */
#undef HAVE_STRUCT_STAT_ST_ATIM_ST__TIM_TV_NSEC

/* Define to 1 if 'st_atim.tv_nsec' is a member of 'struct stat'. */
#undef HAVE_STRUCT_STAT_ST_ATIM_TV_NSEC

/* Define to 1 if 'st_birthtimensec' is a member of 'struct stat'. */
#undef HAVE_STRUCT_STAT_ST_BIRTHTIMENSEC

/* Define to 1 if 'st_birthtimespec.tv_nsec' is a member of 'struct stat'. */
#undef HAVE_STRUCT_STAT_ST_BIRTHTIMESPEC_TV_NSEC

/* Define to 1 if 'st_birthtim.tv_nsec' is a member of 'struct stat'. */
#undef HAVE_STRUCT_STAT_ST_BIRTHTIM_TV_NSEC

/* Define to 1 if you have the 'symlink' function. */
#define HAVE_SYMLINK 1

/* Define to 1 if you have the <sys/bitypes.h> header file. */
#define HAVE_SYS_BITYPES_H 1

/* Define to 1 if you have the <sys/cdefs.h> header file. */
#define HAVE_SYS_CDEFS_H 1

/* Define to 1 if you have the <sys/file.h> header file. */
#define HAVE_SYS_FILE_H 1

/* Define to 1 if you have the <sys/inttypes.h> header file. */
#define HAVE_SYS_INTTYPES_H 1

/* Define to 1 if you have the <sys/ioctl.h> header file. */
#define HAVE_SYS_IOCTL_H 1

/* Define to 1 if you have the <sys/mman.h> header file. */
#undef HAVE_SYS_MMAN_H

/* Define to 1 if you have the <sys/param.h> header file. */
#define HAVE_SYS_PARAM_H 1

/* Define to 1 if you have the <sys/random.h> header file. */
#undef HAVE_SYS_RANDOM_H

/* Define to 1 if you have the <sys/select.h> header file. */
#undef HAVE_SYS_SELECT_H

/* Define to 1 if you have the <sys/single_threaded.h> header file. */
#undef HAVE_SYS_SINGLE_THREADED_H

/* Define to 1 if you have the <sys/socket.h> header file. */
#define HAVE_SYS_SOCKET_H 1

/* Define to 1 if you have the <sys/stat.h> header file. */
#define HAVE_SYS_STAT_H 1

/* Define to 1 if you have the <sys/time.h> header file. */
#define HAVE_SYS_TIME_H 1

/* Define to 1 if you have the <sys/types.h> header file. */
#define HAVE_SYS_TYPES_H 1

/* Define to 1 if you have the <sys/uio.h> header file. */
#undef HAVE_SYS_UIO_H

/* Define to 1 if you have the <sys/wait.h> header file. */
#undef HAVE_SYS_WAIT_H

/* Define to 1 if the system has the 'tcgetattr' function. */
#undef HAVE_TCGETATTR

/* Define to 1 if the system has the 'tcsetattr' function. */
#undef HAVE_TCSETATTR

/* Define to 1 if you have the <termios.h> header file. */
#undef HAVE_TERMIOS_H

/* Define to 1 if you have the `thrd_create' function. */
#undef HAVE_THRD_CREATE

/* Define to 1 if you have the <threads.h> header file. */
//#define HAVE_THREADS_H 1

/* Define to 1 if you have the 'timegm' function. */
#define HAVE_TIMEGM 1

/* Define if you have the timespec_get function. */
#undef HAVE_TIMESPEC_GET

/* Define if struct tm has the tm_gmtoff member. */
#undef HAVE_TM_GMTOFF

/* Define to 1 if you have the 'towlower' function. */
#undef HAVE_TOWLOWER

/* Define to 1 if you have the <uchar.h> header file. */
#undef HAVE_UCHAR_H

/* Define to 1 if the system has the type 'uint32_t'. */
#define HAVE_UINT32_T 1

/* Define to 1 if the system has the type 'uintptr_t'. */
#define HAVE_UINTPTR_T 1

/* Define to 1 if you have the <unistd.h> header file. */
#define HAVE_UNISTD_H 1

/* Define to 1 if you have the <unistring/woe32dll.h> header file. */
#undef HAVE_UNISTRING_WOE32DLL_H

/* Define to 1 if the system has the type 'unsigned long long int'. */
#undef HAVE_UNSIGNED_LONG_LONG_INT

/* Define to 1 if you have the 'usleep' function. */
#define HAVE_USLEEP 1

/* Define to 1 if you have the 'utime' function. */
#undef HAVE_UTIME

/* Define to 1 if you have the `utimensat' function. */
#undef HAVE_UTIMENSAT

/* Define to 1 if you have the <utime.h> header file. */
#undef HAVE_UTIME_H

/* Define if uuid_create is available. */
#undef HAVE_UUID_CREATE

/* Define if you have a global __progname variable */
#undef HAVE_VAR___PROGNAME

/* Define to 1 if you have the 'vasnprintf' function. */
#undef HAVE_VASNPRINTF

/* Define to 1 if you have the 'vasprintf' function. */
#undef HAVE_VASPRINTF 

/* Define to 1 if you have the 'vfork' function. */
#define HAVE_VFORK 1

/* Define to 1 or 0, depending whether the compiler supports simple visibility
   declarations. */
#undef HAVE_VISIBILITY

/* Define to 1 if you have the 'vsnprintf' function. */
#define HAVE_VSNPRINTF 1

/* Define to 1 if you have the 'waitid' function. */
#define HAVE_WAITID 1

/* Define to 1 if you have the <wchar.h> header file. */
#define HAVE_WCHAR_H 1

/* Define if you have the 'wchar_t' type. */
#define HAVE_WCHAR_T 1

/* Define to 1 if you have the 'wcrtomb' function. */
#undef HAVE_WCRTOMB

/* Define to 1 if you have the 'wcslen' function. */
#undef HAVE_WCSLEN

/* Define to 1 if you have the <wctype.h> header file. */
#undef HAVE_WCTYPE_H

/* Define to 1 if you have the 'wcwidth' function. */
#undef HAVE_WCWIDTH

/* Define to 1 if the compiler and linker support weak declarations of
   symbols. */
#undef HAVE_WEAK_SYMBOLS

/* Define to 1 if you have the <winsock2.h> header file. */
#undef HAVE_WINSOCK2_H

/* Define if you have the 'wint_t' type. */
#undef HAVE_WINT_T

/* Define to 1 if you have the `wmempcpy' function. */
#undef HAVE_WMEMPCPY

/* Define to 1 if fstatat (..., 0) works. For example, it does not work in AIX
   7.1. */
#undef HAVE_WORKING_FSTATAT_ZERO_FLAG

/* Define if the mbrtoc32 function basically works. */
#undef HAVE_WORKING_MBRTOC32

/* Define to 1 if O_NOATIME works. */
#undef HAVE_WORKING_O_NOATIME

/* Define to 1 if O_NOFOLLOW works. */
#undef HAVE_WORKING_O_NOFOLLOW

/* Define if utimes works properly. */
#undef HAVE_WORKING_UTIMES

/* Define to 1 if you have the <ws2tcpip.h> header file. */
#undef HAVE_WS2TCPIP_H

/* Define to 1 if you have the <xlocale.h> header file. */
#undef HAVE_XLOCALE_H

/* Define to 1 if the system has the type '_Bool'. */
#undef HAVE__BOOL

/* Define to 1 if you have the '_fseeki64' function. */
#undef HAVE__FSEEKI64

/* Define to 1 if you have the '_ftelli64' function. */
#undef HAVE__FTELLI64

/* Define to 1 if you have the '_set_invalid_parameter_handler' function. */
#undef HAVE__SET_INVALID_PARAMETER_HANDLER

/* Define to 1 if the compiler supports __builtin_expect,
   and to 2 if <builtins.h> does.  */
#undef HAVE___BUILTIN_EXPECT
#ifndef HAVE___BUILTIN_EXPECT
# define __builtin_expect(e, c) (e)
#elif HAVE___BUILTIN_EXPECT == 2
# include <builtins.h>
#endif
    

/* Define to 1 if you have the `__fpurge' function. */
#undef HAVE___FPURGE

/* Define to 1 if you have the `__freading' function. */
#undef HAVE___FREADING

/* Define to 1 if you have the `__fsetlocking' function. */
#undef HAVE___FSETLOCKING

/* Define to 1 if ctype.h defines __header_inline. */
#undef HAVE___HEADER_INLINE

/* Please see the Gnulib manual for how to use these macros.

   Suppress extern inline with HP-UX cc, as it appears to be broken; see
   <https://lists.gnu.org/r/bug-texinfo/2013-02/msg00030.html>.

   Suppress extern inline with Sun C in standards-conformance mode, as it
   mishandles inline functions that call each other.  E.g., for 'inline void f
   (void) { } inline void g (void) { f (); }', c99 incorrectly complains
   'reference to static identifier "f" in extern inline function'.
   This bug was observed with Oracle Developer Studio 12.6
   (Sun C 5.15 SunOS_sparc 2017/05/30).

   Suppress extern inline (with or without __attribute__ ((__gnu_inline__)))
   on configurations that mistakenly use 'static inline' to implement
   functions or macros in standard C headers like <ctype.h>.  For example,
   if isdigit is mistakenly implemented via a static inline function,
   a program containing an extern inline function that calls isdigit
   may not work since the C standard prohibits extern inline functions
   from calling static functions (ISO C 99 section 6.7.4.(3).
   This bug is known to occur on:

     OS X 10.8 and earlier; see:
     https://lists.gnu.org/r/bug-gnulib/2012-12/msg00023.html

     DragonFly; see
     http://muscles.dragonflybsd.org/bulk/clang-master-potential/20141111_102002/logs/ah-tty-0.3.12.log

     FreeBSD; see:
     https://lists.gnu.org/r/bug-gnulib/2014-07/msg00104.html

   OS X 10.9 has a macro __header_inline indicating the bug is fixed for C and
   for clang but remains for g++; see <https://trac.macports.org/ticket/41033>.
   Assume DragonFly and FreeBSD will be similar.

   GCC 4.3 and above with -std=c99 or -std=gnu99 implements ISO C99
   inline semantics, unless -fgnu89-inline is used.  It defines a macro
   __GNUC_STDC_INLINE__ to indicate this situation or a macro
   __GNUC_GNU_INLINE__ to indicate the opposite situation.
   GCC 4.2 with -std=c99 or -std=gnu99 implements the GNU C inline
   semantics but warns, unless -fgnu89-inline is used:
     warning: C99 inline functions are not supported; using GNU89
     warning: to disable this warning use -fgnu89-inline or the gnu_inline function attribute
   It defines a macro __GNUC_GNU_INLINE__ to indicate this situation.
 */
#if (((defined __APPLE__ && defined __MACH__) \
      || defined __DragonFly__ || defined __FreeBSD__) \
     && (defined HAVE___HEADER_INLINE \
         ? (defined __cplusplus && defined __GNUC_STDC_INLINE__ \
            && ! defined __clang__) \
         : ((! defined _DONT_USE_CTYPE_INLINE_ \
             && (defined __GNUC__ || defined __cplusplus)) \
            || (defined _FORTIFY_SOURCE && 0 < _FORTIFY_SOURCE \
                && defined __GNUC__ && ! defined __cplusplus))))
# define _GL_EXTERN_INLINE_STDHEADER_BUG
#endif
#if ((__GNUC__ \
      ? (defined __GNUC_STDC_INLINE__ && __GNUC_STDC_INLINE__ \
         && !defined __PCC__) \
      : (199901L <= __STDC_VERSION__ \
         && !defined __HP_cc \
         && !defined __PGI \
         && !(defined __SUNPRO_C && __STDC__))) \
     && !defined _GL_EXTERN_INLINE_STDHEADER_BUG)
# define _GL_INLINE inline
# define _GL_EXTERN_INLINE extern inline
# define _GL_EXTERN_INLINE_IN_USE
#elif (2 < __GNUC__ + (7 <= __GNUC_MINOR__) && !defined __STRICT_ANSI__ \
       && !defined __PCC__ \
       && !defined _GL_EXTERN_INLINE_STDHEADER_BUG)
# if defined __GNUC_GNU_INLINE__ && __GNUC_GNU_INLINE__
   /* __gnu_inline__ suppresses a GCC 4.2 diagnostic.  */
#  define _GL_INLINE extern inline __attribute__ ((__gnu_inline__))
# else
#  define _GL_INLINE extern inline
# endif
# define _GL_EXTERN_INLINE extern
# define _GL_EXTERN_INLINE_IN_USE
#else
# define _GL_INLINE _GL_UNUSED static
# define _GL_EXTERN_INLINE _GL_UNUSED static
#endif

/* In GCC 4.6 (inclusive) to 5.1 (exclusive),
   suppress bogus "no previous prototype for 'FOO'"
   and "no previous declaration for 'FOO'" diagnostics,
   when FOO is an inline function in the header; see
   <https://gcc.gnu.org/bugzilla/show_bug.cgi?id=54113> and
   <https://gcc.gnu.org/bugzilla/show_bug.cgi?id=63877>.  */
#if __GNUC__ == 4 && 6 <= __GNUC_MINOR__
# if defined __GNUC_STDC_INLINE__ && __GNUC_STDC_INLINE__
#  define _GL_INLINE_HEADER_CONST_PRAGMA
# else
#  define _GL_INLINE_HEADER_CONST_PRAGMA \
     _Pragma ("GCC diagnostic ignored \"-Wsuggest-attribute=const\"")
# endif
# define _GL_INLINE_HEADER_BEGIN \
    _Pragma ("GCC diagnostic push") \
    _Pragma ("GCC diagnostic ignored \"-Wmissing-prototypes\"") \
    _Pragma ("GCC diagnostic ignored \"-Wmissing-declarations\"") \
    _GL_INLINE_HEADER_CONST_PRAGMA
# define _GL_INLINE_HEADER_END \
    _Pragma ("GCC diagnostic pop")
#else
# define _GL_INLINE_HEADER_BEGIN
# define _GL_INLINE_HEADER_END
#endif

/* Define to 1 if the compiler supports the keyword '__inline'. */
#undef HAVE___INLINE

/* Define to 1 if you have the '__secure_getenv' function. */
#undef HAVE___SECURE_GETENV

/* Define to 1 if you have the '__xpg_strerror_r' function. */
#undef HAVE___XPG_STRERROR_R

/* Define as const if the declaration of iconv() needs const. */
#undef ICONV_CONST

/* Define to 1 if lseek does not detect pipes. */
#undef LSEEK_PIPE_BROKEN

/* Define to 1 if 'lstat' dereferences a symlink specified with a trailing
   slash. */
#undef LSTAT_FOLLOWS_SLASHED_SYMLINK

/* If malloc(0) is != NULL, define this to 1. Otherwise define this to 0. */
#undef MALLOC_0_IS_NONNULL

/* Define to a substitute value for mmap()'s MAP_ANONYMOUS flag. */
#undef MAP_ANONYMOUS

/* Define if the mbrtoc32 function does not return (size_t) -2 for empty
   input. */
#undef MBRTOC32_EMPTY_INPUT_BUG

/* Define if the mbrtoc32 function may signal encoding errors in the C locale.
   */
#undef MBRTOC32_IN_C_LOCALE_MAYBE_EILSEQ

/* Define if the mbrtowc function does not return (size_t) -2 for empty input.
   */
#undef MBRTOWC_EMPTY_INPUT_BUG

/* Define if the mbrtowc function may signal encoding errors in the C locale.
   */
#undef MBRTOWC_IN_C_LOCALE_MAYBE_EILSEQ

/* Define if the mbrtowc function has the NULL pwc argument bug. */
#undef MBRTOWC_NULL_ARG1_BUG

/* Define if the mbrtowc function has the NULL string argument bug. */
#undef MBRTOWC_NULL_ARG2_BUG

/* Define if the mbrtowc function does not return 0 for a NUL character. */
#undef MBRTOWC_NUL_RETVAL_BUG

/* Define if the mbrtowc function returns a wrong return value. */
#undef MBRTOWC_RETVAL_BUG

/* Define if the mbrtowc function stores a wide character when reporting
   incomplete input. */
#undef MBRTOWC_STORES_INCOMPLETE_BUG

/* Use GNU style printf and scanf.  */
#ifndef __USE_MINGW_ANSI_STDIO
# undef __USE_MINGW_ANSI_STDIO
#endif


/* Define to 1 on musl libc. */
#undef MUSL_LIBC

/* Define if the compilation of mktime.c should define 'mktime_internal'. */
#define NEED_MKTIME_INTERNAL 1

/* Define if the compilation of mktime.c should define 'mktime' with the
   native Windows TZ workaround. */
#undef NEED_MKTIME_WINDOWS

/* Define if the compilation of mktime.c should define 'mktime' with the
   algorithmic workarounds. */
#undef NEED_MKTIME_WORKING

/* Define to 1 if nl_langinfo is multithread-safe. */
#undef NL_LANGINFO_MTSAFE

/* Define to 1 on Android. */
#undef NO_INLINE_GETPASS

/* Define to 1 if open() fails to recognize a trailing slash. */
#undef OPEN_TRAILING_SLASH_BUG

/* Define to be the name of the operating system. */
#define OS_TYPE "VMS"

/* Name of package */
#define PACKAGE "wget"

/* Define to the address where bug reports for this package should be sent. */
#define PACKAGE_BUGREPORT ""

/* Define to the full name of this package. */
#define PACKAGE_NAME "wget"

/* Define to the full name and version of this package. */
#define PACKAGE_STRING "wget 1.24.5-vms"

/* Define to the one symbol short name of this package. */
#define PACKAGE_TARNAME ""

/* Define to the home page for this package. */
#define PACKAGE_URL ""

/* Define to the version of this package. */
#define PACKAGE_VERSION "1.24.5"

/* Define to the type that is the result of default argument promotions of
   type mode_t. */
#undef PROMOTED_MODE_T

/* Define if the pthread_in_use() detection is hard. */
#undef PTHREAD_IN_USE_DETECTION_HARD

/* Define to 1 if pthread_sigmask(), when it fails, returns -1 and sets errno.
   */
#undef PTHREAD_SIGMASK_FAILS_WITH_ERRNO

/* Define to 1 if pthread_sigmask may return 0 and have no effect. */
#undef PTHREAD_SIGMASK_INEFFECTIVE

/* Define to 1 if pthread_sigmask() unblocks signals incorrectly. */
#undef PTHREAD_SIGMASK_UNBLOCK_BUG

/* Define to l, ll, u, ul, ull, etc., as suitable for constants of type
   'ptrdiff_t'. */
#undef PTRDIFF_T_SUFFIX

/* Define to 1 if readlink fails to recognize a trailing slash. */
#undef READLINK_TRAILING_SLASH_BUG

/* Define to 1 if readlink sets errno instead of truncating a too-long link.
   */
#undef READLINK_TRUNCATE_BUG

/* Define if rename does not work when the destination file exists, as on
   Cygwin 1.5 or Windows. */
#undef RENAME_DEST_EXISTS_BUG

/* Define if rename fails to leave hard links alone, as on NetBSD 1.6 or
   Cygwin 1.5. */
#undef RENAME_HARD_LINK_BUG

/* Define if rename does not correctly handle slashes on the destination
   argument, such as on Solaris 11 or NetBSD 1.6. */
#undef RENAME_TRAILING_SLASH_DEST_BUG

/* Define if rename does not correctly handle slashes on the source argument,
   such as on Solaris 9 or cygwin 1.5. */
#undef RENAME_TRAILING_SLASH_SOURCE_BUG

/* Define to 1 if gnulib's fchdir() replacement is used. */
#undef REPLACE_FCHDIR

/* Define to 1 if stat needs help when passed a file name with a trailing
   slash */
#undef REPLACE_FUNC_STAT_FILE

/* Define to 1 if utime needs help when passed a file name with a trailing
   slash */
#undef REPLACE_FUNC_UTIME_FILE

/* Define if nl_langinfo exists but is overridden by gnulib. */
#undef REPLACE_NL_LANGINFO

/* Define to 1 if open() should work around the inability to open a directory.
   */
#undef REPLACE_OPEN_DIRECTORY

/* Define if gnulib uses its own posix_spawn and posix_spawnp functions. */
#undef REPLACE_POSIX_SPAWN

/* Define to 1 if strerror(0) does not return a message implying success. */
#undef REPLACE_STRERROR_0

/* Define if vasnprintf exists but is overridden by gnulib. */
#undef REPLACE_VASNPRINTF

/* Define to 1 if setlocale (LC_ALL, NULL) is multithread-safe. */
#undef SETLOCALE_NULL_ALL_MTSAFE

/* Define to 1 if setlocale (category, NULL) is multithread-safe. */
#undef SETLOCALE_NULL_ONE_MTSAFE

/* File name of the Bourne shell.  */
#if (defined _WIN32 && !defined __CYGWIN__) || defined __CYGWIN__ || defined __ANDROID__
/* Omit the directory part because
   - For native Windows programs in a Cygwin environment, the Cygwin mounts
     are not visible.
   - For 32-bit Cygwin programs in a 64-bit Cygwin environment, the Cygwin
     mounts are not visible.
   - On Android, /bin/sh does not exist. It's /system/bin/sh instead.  */
# define BOURNE_SHELL "sh"
#else
# define BOURNE_SHELL "/bin/sh"
#endif

/* Define to l, ll, u, ul, ull, etc., as suitable for constants of type
   'sig_atomic_t'. */
#undef SIG_ATOMIC_T_SUFFIX

/* The size of 'long', as computed by sizeof. */
#undef SIZEOF_LONG

/* The size of 'off_t', as computed by sizeof. */
#undef SIZEOF_OFF_T

/* Define as the maximum value of type 'size_t', if the system doesn't define
   it. */
#ifndef SIZE_MAX
# undef SIZE_MAX
#endif

/* Define to l, ll, u, ul, ull, etc., as suitable for constants of type
   'size_t'. */
#undef SIZE_T_SUFFIX

/* If using the C implementation of alloca, define if you know the
   direction of stack growth for your system; otherwise it will be
   automatically deduced at runtime.
	STACK_DIRECTION > 0 => grows toward higher addresses
	STACK_DIRECTION < 0 => grows toward lower addresses
	STACK_DIRECTION = 0 => direction of growth unknown */
#undef STACK_DIRECTION

/* Define to 1 if the 'S_IS*' macros in <sys/stat.h> do not work properly. */
#undef STAT_MACROS_BROKEN

/* Define to 1 if all of the C89 standard headers exist (not just the ones
   required in a freestanding environment). This macro is provided for
   backward compatibility; new code need not use it. */
#undef STDC_HEADERS

/* Define to 1 if strerror_r returns char *. */
#undef STRERROR_R_CHAR_P

/* Define to 1 if time_t is signed. */
#undef TIME_T_IS_SIGNED

/* Define to 1 if the type of the st_atim member of a struct stat is struct
   timespec. */
#undef TYPEOF_STRUCT_STAT_ST_ATIM_IS_STRUCT_TIMESPEC

/* Define to 1 if unlink() on a parent directory may succeed */
#undef UNLINK_PARENT_BUG

/* Define to the prefix of C symbols at the assembler and linker level, either
   an underscore or empty. */
#undef USER_LABEL_PREFIX

/* Define if the combination of the ISO C and POSIX multithreading APIs can be
   used. */
#undef USE_ISOC_AND_POSIX_THREADS

/* Define if the ISO C multithreading library can be used. */
#undef USE_ISOC_THREADS

/* Define to 1 if you want to use the Linux kernel cryptographic API. */
#undef USE_LINUX_CRYPTO_API

/* Define if the POSIX multithreading library can be used. */
#undef USE_POSIX_THREADS

/* Define if references to the POSIX multithreading library are satisfied by
   libc. */
#undef USE_POSIX_THREADS_FROM_LIBC

/* Define if references to the POSIX multithreading library should be made
   weak. */
#undef USE_POSIX_THREADS_WEAK

/* Enable extensions on AIX, Interix, z/OS.  */
#ifndef _ALL_SOURCE
# undef _ALL_SOURCE
#endif
/* Enable general extensions on macOS.  */
#ifndef _DARWIN_C_SOURCE
# undef _DARWIN_C_SOURCE
#endif
/* Enable general extensions on Solaris.  */
#ifndef __EXTENSIONS__
# undef __EXTENSIONS__
#endif
/* Enable GNU extensions on systems that have them.  */
#ifndef _GNU_SOURCE
# undef _GNU_SOURCE
#endif
/* Enable X/Open compliant socket functions that do not require linking
   with -lxnet on HP-UX 11.11.  */
#ifndef _HPUX_ALT_XOPEN_SOCKET_API
# undef _HPUX_ALT_XOPEN_SOCKET_API
#endif
/* Identify the host operating system as Minix.
   This macro does not affect the system headers' behavior.
   A future release of Autoconf may stop defining this macro.  */
#ifndef _MINIX
# undef _MINIX
#endif
/* Enable general extensions on NetBSD.
   Enable NetBSD compatibility extensions on Minix.  */
#ifndef _NETBSD_SOURCE
# undef _NETBSD_SOURCE
#endif
/* Enable OpenBSD compatibility extensions on NetBSD.
   Oddly enough, this does nothing on OpenBSD.  */
#ifndef _OPENBSD_SOURCE
# undef _OPENBSD_SOURCE
#endif
/* Define to 1 if needed for POSIX-compatible behavior.  */
#ifndef _POSIX_SOURCE
# undef _POSIX_SOURCE
#endif
/* Define to 2 if needed for POSIX-compatible behavior.  */
#ifndef _POSIX_1_SOURCE
# undef _POSIX_1_SOURCE
#endif
/* Enable POSIX-compatible threading on Solaris.  */
#ifndef _POSIX_PTHREAD_SEMANTICS
# undef _POSIX_PTHREAD_SEMANTICS
#endif
/* Enable extensions specified by ISO/IEC TS 18661-5:2014.  */
#ifndef __STDC_WANT_IEC_60559_ATTRIBS_EXT__
# undef __STDC_WANT_IEC_60559_ATTRIBS_EXT__
#endif
/* Enable extensions specified by ISO/IEC TS 18661-1:2014.  */
#ifndef __STDC_WANT_IEC_60559_BFP_EXT__
# undef __STDC_WANT_IEC_60559_BFP_EXT__
#endif
/* Enable extensions specified by ISO/IEC TS 18661-2:2015.  */
#ifndef __STDC_WANT_IEC_60559_DFP_EXT__
# undef __STDC_WANT_IEC_60559_DFP_EXT__
#endif
/* Enable extensions specified by C23 Annex F.  */
#ifndef __STDC_WANT_IEC_60559_EXT__
# undef __STDC_WANT_IEC_60559_EXT__
#endif
/* Enable extensions specified by ISO/IEC TS 18661-4:2015.  */
#ifndef __STDC_WANT_IEC_60559_FUNCS_EXT__
# undef __STDC_WANT_IEC_60559_FUNCS_EXT__
#endif
/* Enable extensions specified by C23 Annex H and ISO/IEC TS 18661-3:2015.  */
#ifndef __STDC_WANT_IEC_60559_TYPES_EXT__
# undef __STDC_WANT_IEC_60559_TYPES_EXT__
#endif
/* Enable extensions specified by ISO/IEC TR 24731-2:2010.  */
#ifndef __STDC_WANT_LIB_EXT2__
# undef __STDC_WANT_LIB_EXT2__
#endif
/* Enable extensions specified by ISO/IEC 24747:2009.  */
#ifndef __STDC_WANT_MATH_SPEC_FUNCS__
# undef __STDC_WANT_MATH_SPEC_FUNCS__
#endif
/* Enable extensions on HP NonStop.  */
#ifndef _TANDEM_SOURCE
# undef _TANDEM_SOURCE
#endif
/* Enable X/Open extensions.  Define to 500 only if necessary
   to make mbstate_t available.  */
#ifndef _XOPEN_SOURCE
# undef _XOPEN_SOURCE
#endif


/* An alias of GNULIB_STDIO_SINGLE_THREAD. */
#undef USE_UNLOCKED_IO

/* Define if the native Windows multithreading API can be used. */
#undef USE_WINDOWS_THREADS

/* Version number of package */
#define VERSION "1.24.5"

/* Define to l, ll, u, ul, ull, etc., as suitable for constants of type
   'wchar_t'. */
#undef WCHAR_T_SUFFIX

/* Define if the wcrtomb function does not work in the C locale. */
#undef WCRTOMB_C_LOCALE_BUG

/* Define if the wcrtomb function has an incorrect return value. */
#undef WCRTOMB_RETVAL_BUG

/* Define if WSAStartup is needed. */
#undef WINDOWS_SOCKETS

/* Define to l, ll, u, ul, ull, etc., as suitable for constants of type
   'wint_t'. */
#undef WINT_T_SUFFIX

/* Define WORDS_BIGENDIAN to 1 if your processor stores words with the most
   significant byte first (like Motorola and SPARC, unlike Intel). */
#if defined AC_APPLE_UNIVERSAL_BUILD
# if defined __BIG_ENDIAN__
#  define WORDS_BIGENDIAN 1
# endif
#else
# ifndef WORDS_BIGENDIAN
#  undef WORDS_BIGENDIAN
# endif
#endif

/* Define to 1 if 'lex' declares 'yytext' as a 'char *' by default, not a
   'char[]'. */
#undef YYTEXT_POINTER

/* Number of bits in a file offset, on hosts where this is settable. */
#undef _FILE_OFFSET_BITS

/* True if the compiler says it groks GNU C version MAJOR.MINOR.  */
#if defined __GNUC__ && defined __GNUC_MINOR__
# define _GL_GNUC_PREREQ(major, minor) \
    ((major) < __GNUC__ + ((minor) <= __GNUC_MINOR__))
#else
# define _GL_GNUC_PREREQ(major, minor) 0
#endif


/* Define to enable the declarations of ISO C 11 types and functions. */
#undef _ISOC11_SOURCE

/* Define to 1 if necessary to make fseeko visible. */
#undef _LARGEFILE_SOURCE

/* Define to 1 on platforms where this makes off_t a 64-bit type. */
#undef _LARGE_FILES

/* Define to 1 on Solaris. */
#undef _LCONV_C99

/* The _Noreturn keyword of C11.  */
#ifndef _Noreturn
# if (defined __cplusplus \
      && ((201103 <= __cplusplus && !(__GNUC__ == 4 && __GNUC_MINOR__ == 7)) \
          || (defined _MSC_VER && 1900 <= _MSC_VER)) \
      && 0)
    /* [[noreturn]] is not practically usable, because with it the syntax
         extern _Noreturn void func (...);
       would not be valid; such a declaration would only be valid with 'extern'
       and '_Noreturn' swapped, or without the 'extern' keyword.  However, some
       AIX system header files and several gnulib header files use precisely
       this syntax with 'extern'.  */
#  define _Noreturn [[noreturn]]
# elif (defined __clang__ && __clang_major__ < 16 \
        && defined _GL_WORK_AROUND_LLVM_BUG_59792)
   /* Compile with -D_GL_WORK_AROUND_LLVM_BUG_59792 to work around
      that rare LLVM bug, though you may get many false-alarm warnings.  */
#  define _Noreturn
# elif ((!defined __cplusplus || defined __clang__) \
        && (201112 <= (defined __STDC_VERSION__ ? __STDC_VERSION__ : 0) \
            || (!defined __STRICT_ANSI__ \
                && (_GL_GNUC_PREREQ (4, 7) \
                    || (defined __apple_build_version__ \
                        ? 6000000 <= __apple_build_version__ \
                        : 3 < __clang_major__ + (5 <= __clang_minor__))))))
   /* _Noreturn works as-is.  */
# elif _GL_GNUC_PREREQ (2, 8) || defined __clang__ || 0x5110 <= __SUNPRO_C
#  define _Noreturn __attribute__ ((__noreturn__))
# elif 1200 <= (defined _MSC_VER ? _MSC_VER : 0)
#  define _Noreturn __declspec (noreturn)
# else
#  define _Noreturn
# endif
#endif


/* Define to 1 in order to get the POSIX compatible declarations of socket
   functions. */
#undef _POSIX_PII_SOCKET

/* Define if you want <regex.h> to include <limits.h>, so that it consistently
   overrides <limits.h>'s RE_DUP_MAX. */
#undef _REGEX_INCLUDE_LIMITS_H

/* Define if you want regoff_t to be at least as wide POSIX requires. */
#undef _REGEX_LARGE_OFFSETS

/* Number of bits in time_t, on hosts where this is settable. */
#undef _TIME_BITS

/* For standard stat data types on VMS. */
#undef _USE_STD_STAT

/* Define to rpl_ if the getopt replacement functions and variables should be
   used. */
#undef __GETOPT_PREFIX

/* Define to 1 on platforms where this makes time_t a 64-bit type. */
#undef __MINGW_USE_VC2005_COMPAT

/* Define to 1 if the system <stdint.h> predates C++11. */
#undef __STDC_CONSTANT_MACROS

/* Define to 1 if the system <stdint.h> predates C++11. */
#undef __STDC_LIMIT_MACROS

/* Define to 1 if C does not support variable-length arrays, and if the
   compiler does not already define this. */
#undef __STDC_NO_VLA__

/* The _GL_ASYNC_SAFE marker should be attached to functions that are
   signal handlers (for signals other than SIGABRT, SIGPIPE) or can be
   invoked from such signal handlers.  Such functions have some restrictions:
     * All functions that it calls should be marked _GL_ASYNC_SAFE as well,
       or should be listed as async-signal-safe in POSIX
       <https://pubs.opengroup.org/onlinepubs/9699919799/functions/V2_chap02.html#tag_15_04>
       section 2.4.3.  Note that malloc(), sprintf(), and fwrite(), in
       particular, are NOT async-signal-safe.
     * All memory locations (variables and struct fields) that these functions
       access must be marked 'volatile'.  This holds for both read and write
       accesses.  Otherwise the compiler might optimize away stores to and
       reads from such locations that occur in the program, depending on its
       data flow analysis.  For example, when the program contains a loop
       that is intended to inspect a variable set from within a signal handler
           while (!signal_occurred)
             ;
       the compiler is allowed to transform this into an endless loop if the
       variable 'signal_occurred' is not declared 'volatile'.
   Additionally, recall that:
     * A signal handler should not modify errno (except if it is a handler
       for a fatal signal and ends by raising the same signal again, thus
       provoking the termination of the process).  If it invokes a function
       that may clobber errno, it needs to save and restore the value of
       errno.  */
#define _GL_ASYNC_SAFE


/* Attributes.  */
/* Define _GL_HAS_ATTRIBUTE only once, because on FreeBSD, with gcc < 5, if
   <config.h> gets included once again after <sys/cdefs.h>, __has_attribute(x)
   expands to 0 always, and redefining _GL_HAS_ATTRIBUTE would turn off all
   attributes.  */
#ifndef _GL_HAS_ATTRIBUTE
# if (defined __has_attribute \
      && (!defined __clang_minor__ \
          || (defined __apple_build_version__ \
              ? 7000000 <= __apple_build_version__ \
              : 5 <= __clang_major__)))
#  define _GL_HAS_ATTRIBUTE(attr) __has_attribute (__##attr##__)
# else
#  define _GL_HAS_ATTRIBUTE(attr) _GL_ATTR_##attr
#  define _GL_ATTR_alloc_size _GL_GNUC_PREREQ (4, 3)
#  define _GL_ATTR_always_inline _GL_GNUC_PREREQ (3, 2)
#  define _GL_ATTR_artificial _GL_GNUC_PREREQ (4, 3)
#  define _GL_ATTR_cold _GL_GNUC_PREREQ (4, 3)
#  define _GL_ATTR_const _GL_GNUC_PREREQ (2, 95)
#  define _GL_ATTR_deprecated _GL_GNUC_PREREQ (3, 1)
#  define _GL_ATTR_diagnose_if 0
#  define _GL_ATTR_error _GL_GNUC_PREREQ (4, 3)
#  define _GL_ATTR_externally_visible _GL_GNUC_PREREQ (4, 1)
#  define _GL_ATTR_fallthrough _GL_GNUC_PREREQ (7, 0)
#  define _GL_ATTR_format _GL_GNUC_PREREQ (2, 7)
#  define _GL_ATTR_leaf _GL_GNUC_PREREQ (4, 6)
#  define _GL_ATTR_malloc _GL_GNUC_PREREQ (3, 0)
#  ifdef _ICC
#   define _GL_ATTR_may_alias 0
#  else
#   define _GL_ATTR_may_alias _GL_GNUC_PREREQ (3, 3)
#  endif
#  define _GL_ATTR_noinline _GL_GNUC_PREREQ (3, 1)
#  define _GL_ATTR_nonnull _GL_GNUC_PREREQ (3, 3)
#  define _GL_ATTR_nonstring _GL_GNUC_PREREQ (8, 0)
#  define _GL_ATTR_nothrow _GL_GNUC_PREREQ (3, 3)
#  define _GL_ATTR_packed _GL_GNUC_PREREQ (2, 7)
#  define _GL_ATTR_pure _GL_GNUC_PREREQ (2, 96)
#  define _GL_ATTR_returns_nonnull _GL_GNUC_PREREQ (4, 9)
#  define _GL_ATTR_sentinel _GL_GNUC_PREREQ (4, 0)
#  define _GL_ATTR_unused _GL_GNUC_PREREQ (2, 7)
#  define _GL_ATTR_warn_unused_result _GL_GNUC_PREREQ (3, 4)
# endif
#endif

/* Use __has_c_attribute if available.  However, do not use with
   pre-C23 GCC, which can issue false positives if -Wpedantic.  */
#if (defined __has_c_attribute \
     && ! (_GL_GNUC_PREREQ (4, 6) \
           && (defined __STDC_VERSION__ ? __STDC_VERSION__ : 0) <= 201710))
# define _GL_HAVE___HAS_C_ATTRIBUTE 1
#else
# define _GL_HAVE___HAS_C_ATTRIBUTE 0
#endif

/* Define if, in a function declaration, the attributes in bracket syntax
   [[...]] must come before the attributes in __attribute__((...)) syntax.
   If this is defined, it is best to avoid the bracket syntax, so that the
   various _GL_ATTRIBUTE_* can be cumulated on the same declaration in any
   order.  */
#ifdef __cplusplus
# if defined __clang__
#  define _GL_BRACKET_BEFORE_ATTRIBUTE 1
# endif
#else
# if defined __GNUC__ && !defined __clang__
#  define _GL_BRACKET_BEFORE_ATTRIBUTE 1
# endif
#endif

/* _GL_ATTRIBUTE_ALLOC_SIZE ((N)) declares that the Nth argument of the function
   is the size of the returned memory block.
   _GL_ATTRIBUTE_ALLOC_SIZE ((M, N)) declares that the Mth argument multiplied
   by the Nth argument of the function is the size of the returned memory block.
 */
/* Applies to: function, pointer to function, function types.  */
#ifndef _GL_ATTRIBUTE_ALLOC_SIZE
# if _GL_HAS_ATTRIBUTE (alloc_size)
#  define _GL_ATTRIBUTE_ALLOC_SIZE(args) __attribute__ ((__alloc_size__ args))
# else
#  define _GL_ATTRIBUTE_ALLOC_SIZE(args)
# endif
#endif

/* _GL_ATTRIBUTE_ALWAYS_INLINE tells that the compiler should always inline the
   function and report an error if it cannot do so.  */
/* Applies to: function.  */
#ifndef _GL_ATTRIBUTE_ALWAYS_INLINE
# if _GL_HAS_ATTRIBUTE (always_inline)
#  define _GL_ATTRIBUTE_ALWAYS_INLINE __attribute__ ((__always_inline__))
# else
#  define _GL_ATTRIBUTE_ALWAYS_INLINE
# endif
#endif

/* _GL_ATTRIBUTE_ARTIFICIAL declares that the function is not important to show
    in stack traces when debugging.  The compiler should omit the function from
    stack traces.  */
/* Applies to: function.  */
#ifndef _GL_ATTRIBUTE_ARTIFICIAL
# if _GL_HAS_ATTRIBUTE (artificial)
#  define _GL_ATTRIBUTE_ARTIFICIAL __attribute__ ((__artificial__))
# else
#  define _GL_ATTRIBUTE_ARTIFICIAL
# endif
#endif

/* _GL_ATTRIBUTE_COLD declares that the function is rarely executed.  */
/* Applies to: functions.  */
/* Avoid __attribute__ ((cold)) on MinGW; see thread starting at
   <https://lists.gnu.org/r/emacs-devel/2019-04/msg01152.html>.
   Also, Oracle Studio 12.6 requires 'cold' not '__cold__'.  */
#ifndef _GL_ATTRIBUTE_COLD
# if _GL_HAS_ATTRIBUTE (cold) && !defined __MINGW32__
#  ifndef __SUNPRO_C
#   define _GL_ATTRIBUTE_COLD __attribute__ ((__cold__))
#  else
#   define _GL_ATTRIBUTE_COLD __attribute__ ((cold))
#  endif
# else
#  define _GL_ATTRIBUTE_COLD
# endif
#endif

/* _GL_ATTRIBUTE_CONST declares that it is OK for a compiler to omit duplicate
   calls to the function with the same arguments.
   This attribute is safe for a function that neither depends on nor affects
   observable state, and always returns exactly once - e.g., does not loop
   forever, and does not call longjmp.
   (This attribute is stricter than _GL_ATTRIBUTE_PURE.)  */
/* Applies to: functions.  */
#ifndef _GL_ATTRIBUTE_CONST
# if _GL_HAS_ATTRIBUTE (const)
#  define _GL_ATTRIBUTE_CONST __attribute__ ((__const__))
# else
#  define _GL_ATTRIBUTE_CONST
# endif
#endif

/* _GL_ATTRIBUTE_DEALLOC (F, I) declares that the function returns pointers
   that can be freed by passing them as the Ith argument to the
   function F.
   _GL_ATTRIBUTE_DEALLOC_FREE declares that the function returns pointers that
   can be freed via 'free'; it can be used only after declaring 'free'.  */
/* Applies to: functions.  Cannot be used on inline functions.  */
#ifndef _GL_ATTRIBUTE_DEALLOC
# if _GL_GNUC_PREREQ (11, 0)
#  define _GL_ATTRIBUTE_DEALLOC(f, i) __attribute__ ((__malloc__ (f, i)))
# else
#  define _GL_ATTRIBUTE_DEALLOC(f, i)
# endif
#endif
/* If gnulib's <string.h> or <wchar.h> has already defined this macro, continue
   to use this earlier definition, since <stdlib.h> may not have been included
   yet.  */
#ifndef _GL_ATTRIBUTE_DEALLOC_FREE
# if defined __cplusplus && defined __GNUC__ && !defined __clang__
/* Work around GCC bug <https://gcc.gnu.org/bugzilla/show_bug.cgi?id=108231> */
#  define _GL_ATTRIBUTE_DEALLOC_FREE \
     _GL_ATTRIBUTE_DEALLOC ((void (*) (void *)) free, 1)
# else
#  define _GL_ATTRIBUTE_DEALLOC_FREE \
     _GL_ATTRIBUTE_DEALLOC (free, 1)
# endif
#endif

/* _GL_ATTRIBUTE_DEPRECATED: Declares that an entity is deprecated.
   The compiler may warn if the entity is used.  */
/* Applies to:
     - function, variable,
     - struct, union, struct/union member,
     - enumeration, enumeration item,
     - typedef,
   in C++ also: namespace, class, template specialization.  */
#ifndef _GL_ATTRIBUTE_DEPRECATED
# ifndef _GL_BRACKET_BEFORE_ATTRIBUTE
#  if _GL_HAVE___HAS_C_ATTRIBUTE
#   if __has_c_attribute (__deprecated__)
#    define _GL_ATTRIBUTE_DEPRECATED [[__deprecated__]]
#   endif
#  endif
# endif
# if !defined _GL_ATTRIBUTE_DEPRECATED && _GL_HAS_ATTRIBUTE (deprecated)
#  define _GL_ATTRIBUTE_DEPRECATED __attribute__ ((__deprecated__))
# endif
# ifndef _GL_ATTRIBUTE_DEPRECATED
#  define _GL_ATTRIBUTE_DEPRECATED
# endif
#endif

/* _GL_ATTRIBUTE_ERROR(msg) requests an error if a function is called and
   the function call is not optimized away.
   _GL_ATTRIBUTE_WARNING(msg) requests a warning if a function is called and
   the function call is not optimized away.  */
/* Applies to: functions.  */
#if !(defined _GL_ATTRIBUTE_ERROR && defined _GL_ATTRIBUTE_WARNING)
# if _GL_HAS_ATTRIBUTE (error)
#  define _GL_ATTRIBUTE_ERROR(msg) __attribute__ ((__error__ (msg)))
#  define _GL_ATTRIBUTE_WARNING(msg) __attribute__ ((__warning__ (msg)))
# elif _GL_HAS_ATTRIBUTE (diagnose_if)
#  define _GL_ATTRIBUTE_ERROR(msg) __attribute__ ((__diagnose_if__ (1, msg, "error")))
#  define _GL_ATTRIBUTE_WARNING(msg) __attribute__ ((__diagnose_if__ (1, msg, "warning")))
# else
#  define _GL_ATTRIBUTE_ERROR(msg)
#  define _GL_ATTRIBUTE_WARNING(msg)
# endif
#endif

/* _GL_ATTRIBUTE_EXTERNALLY_VISIBLE declares that the entity should remain
   visible to debuggers etc., even with '-fwhole-program'.  */
/* Applies to: functions, variables.  */
#ifndef _GL_ATTRIBUTE_EXTERNALLY_VISIBLE
# if _GL_HAS_ATTRIBUTE (externally_visible)
#  define _GL_ATTRIBUTE_EXTERNALLY_VISIBLE __attribute__ ((externally_visible))
# else
#  define _GL_ATTRIBUTE_EXTERNALLY_VISIBLE
# endif
#endif

/* _GL_ATTRIBUTE_FALLTHROUGH declares that it is not a programming mistake if
   the control flow falls through to the immediately following 'case' or
   'default' label.  The compiler should not warn in this case.  */
/* Applies to: Empty statement (;), inside a 'switch' statement.  */
/* Always expands to something.  */
#ifndef _GL_ATTRIBUTE_FALLTHROUGH
# if _GL_HAVE___HAS_C_ATTRIBUTE
#  if __has_c_attribute (__fallthrough__)
#   define _GL_ATTRIBUTE_FALLTHROUGH [[__fallthrough__]]
#  endif
# endif
# if !defined _GL_ATTRIBUTE_FALLTHROUGH && _GL_HAS_ATTRIBUTE (fallthrough)
#  define _GL_ATTRIBUTE_FALLTHROUGH __attribute__ ((__fallthrough__))
# endif
# ifndef _GL_ATTRIBUTE_FALLTHROUGH
#  define _GL_ATTRIBUTE_FALLTHROUGH ((void) 0)
# endif
#endif

/* _GL_ATTRIBUTE_FORMAT ((ARCHETYPE, STRING-INDEX, FIRST-TO-CHECK))
   declares that the STRING-INDEXth function argument is a format string of
   style ARCHETYPE, which is one of:
     printf, gnu_printf
     scanf, gnu_scanf,
     strftime, gnu_strftime,
     strfmon,
   or the same thing prefixed and suffixed with '__'.
   If FIRST-TO-CHECK is not 0, arguments starting at FIRST-TO_CHECK
   are suitable for the format string.  */
/* Applies to: functions.  */
#ifndef _GL_ATTRIBUTE_FORMAT
# if _GL_HAS_ATTRIBUTE (format)
#  define _GL_ATTRIBUTE_FORMAT(spec) __attribute__ ((__format__ spec))
# else
#  define _GL_ATTRIBUTE_FORMAT(spec)
# endif
#endif

/* _GL_ATTRIBUTE_LEAF declares that if the function is called from some other
   compilation unit, it executes code from that unit only by return or by
   exception handling.  This declaration lets the compiler optimize that unit
   more aggressively.  */
/* Applies to: functions.  */
#ifndef _GL_ATTRIBUTE_LEAF
# if _GL_HAS_ATTRIBUTE (leaf)
#  define _GL_ATTRIBUTE_LEAF __attribute__ ((__leaf__))
# else
#  define _GL_ATTRIBUTE_LEAF
# endif
#endif

/* _GL_ATTRIBUTE_MALLOC declares that the function returns a pointer to freshly
   allocated memory.  */
/* Applies to: functions.  */
#ifndef _GL_ATTRIBUTE_MALLOC
# if _GL_HAS_ATTRIBUTE (malloc)
#  define _GL_ATTRIBUTE_MALLOC __attribute__ ((__malloc__))
# else
#  define _GL_ATTRIBUTE_MALLOC
# endif
#endif

/* _GL_ATTRIBUTE_MAY_ALIAS declares that pointers to the type may point to the
   same storage as pointers to other types.  Thus this declaration disables
   strict aliasing optimization.  */
/* Applies to: types.  */
/* Oracle Studio 12.6 mishandles may_alias despite __has_attribute OK.  */
#ifndef _GL_ATTRIBUTE_MAY_ALIAS
# if _GL_HAS_ATTRIBUTE (may_alias) && !defined __SUNPRO_C
#  define _GL_ATTRIBUTE_MAY_ALIAS __attribute__ ((__may_alias__))
# else
#  define _GL_ATTRIBUTE_MAY_ALIAS
# endif
#endif

/* _GL_ATTRIBUTE_MAYBE_UNUSED declares that it is not a programming mistake if
   the entity is not used.  The compiler should not warn if the entity is not
   used.  */
/* Applies to:
     - function, variable,
     - struct, union, struct/union member,
     - enumeration, enumeration item,
     - typedef,
   in C++ also: class.  */
/* In C++ and C23, this is spelled [[__maybe_unused__]].
   GCC's syntax is __attribute__ ((__unused__)).
   clang supports both syntaxes.  Except that with clang ≥ 6, < 10, in C++ mode,
   __has_c_attribute (__maybe_unused__) yields true but the use of
   [[__maybe_unused__]] nevertheless produces a warning.  */
#ifndef _GL_ATTRIBUTE_MAYBE_UNUSED
# ifndef _GL_BRACKET_BEFORE_ATTRIBUTE
#  if defined __clang__ && defined __cplusplus
#   if !defined __apple_build_version__ && __clang_major__ >= 10
#    define _GL_ATTRIBUTE_MAYBE_UNUSED [[__maybe_unused__]]
#   endif
#  elif _GL_HAVE___HAS_C_ATTRIBUTE
#   if __has_c_attribute (__maybe_unused__)
#    define _GL_ATTRIBUTE_MAYBE_UNUSED [[__maybe_unused__]]
#   endif
#  endif
# endif
# ifndef _GL_ATTRIBUTE_MAYBE_UNUSED
#  define _GL_ATTRIBUTE_MAYBE_UNUSED _GL_ATTRIBUTE_UNUSED
# endif
#endif
/* Alternative spelling of this macro, for convenience and for
   compatibility with glibc/include/libc-symbols.h.  */
#define _GL_UNUSED _GL_ATTRIBUTE_MAYBE_UNUSED
/* Earlier spellings of this macro.  */
#define _UNUSED_PARAMETER_ _GL_ATTRIBUTE_MAYBE_UNUSED

/* _GL_ATTRIBUTE_NODISCARD declares that the caller of the function should not
   discard the return value.  The compiler may warn if the caller does not use
   the return value, unless the caller uses something like ignore_value.  */
/* Applies to: function, enumeration, class.  */
#ifndef _GL_ATTRIBUTE_NODISCARD
# ifndef _GL_BRACKET_BEFORE_ATTRIBUTE
#  if defined __clang__ && defined __cplusplus
  /* With clang up to 15.0.6 (at least), in C++ mode, [[__nodiscard__]] produces
     a warning.
     The 1000 below means a yet unknown threshold.  When clang++ version X
     starts supporting [[__nodiscard__]] without warning about it, you can
     replace the 1000 with X.  */
#   if __clang_major__ >= 1000
#    define _GL_ATTRIBUTE_NODISCARD [[__nodiscard__]]
#   endif
#  elif _GL_HAVE___HAS_C_ATTRIBUTE
#   if __has_c_attribute (__nodiscard__)
#    define _GL_ATTRIBUTE_NODISCARD [[__nodiscard__]]
#   endif
#  endif
# endif
# if !defined _GL_ATTRIBUTE_NODISCARD && _GL_HAS_ATTRIBUTE (warn_unused_result)
#  define _GL_ATTRIBUTE_NODISCARD __attribute__ ((__warn_unused_result__))
# endif
# ifndef _GL_ATTRIBUTE_NODISCARD
#  define _GL_ATTRIBUTE_NODISCARD
# endif
#endif

/* _GL_ATTRIBUTE_NOINLINE tells that the compiler should not inline the
   function.  */
/* Applies to: functions.  */
#ifndef _GL_ATTRIBUTE_NOINLINE
# if _GL_HAS_ATTRIBUTE (noinline)
#  define _GL_ATTRIBUTE_NOINLINE __attribute__ ((__noinline__))
# else
#  define _GL_ATTRIBUTE_NOINLINE
# endif
#endif

/* _GL_ATTRIBUTE_NONNULL ((N1, N2,...)) declares that the arguments N1, N2,...
   must not be NULL.
   _GL_ATTRIBUTE_NONNULL () declares that all pointer arguments must not be
   null.  */
/* Applies to: functions.  */
#ifndef _GL_ATTRIBUTE_NONNULL
# if _GL_HAS_ATTRIBUTE (nonnull)
#  define _GL_ATTRIBUTE_NONNULL(args) __attribute__ ((__nonnull__ args))
# else
#  define _GL_ATTRIBUTE_NONNULL(args)
# endif
#endif

/* _GL_ATTRIBUTE_NONSTRING declares that the contents of a character array is
   not meant to be NUL-terminated.  */
/* Applies to: struct/union members and variables that are arrays of element
   type '[[un]signed] char'.  */
#ifndef _GL_ATTRIBUTE_NONSTRING
# if _GL_HAS_ATTRIBUTE (nonstring)
#  define _GL_ATTRIBUTE_NONSTRING __attribute__ ((__nonstring__))
# else
#  define _GL_ATTRIBUTE_NONSTRING
# endif
#endif

/* There is no _GL_ATTRIBUTE_NORETURN; use _Noreturn instead.  */

/* _GL_ATTRIBUTE_NOTHROW declares that the function does not throw exceptions.
 */
/* Applies to: functions.  */
/* After a function's parameter list, this attribute must come first, before
   other attributes.  */
#ifndef _GL_ATTRIBUTE_NOTHROW
# if defined __cplusplus
#  if _GL_GNUC_PREREQ (2, 8) || __clang_major >= 4
#   if __cplusplus >= 201103L
#    define _GL_ATTRIBUTE_NOTHROW noexcept (true)
#   else
#    define _GL_ATTRIBUTE_NOTHROW throw ()
#   endif
#  else
#   define _GL_ATTRIBUTE_NOTHROW
#  endif
# else
#  if _GL_HAS_ATTRIBUTE (nothrow)
#   define _GL_ATTRIBUTE_NOTHROW __attribute__ ((__nothrow__))
#  else
#   define _GL_ATTRIBUTE_NOTHROW
#  endif
# endif
#endif

/* _GL_ATTRIBUTE_PACKED declares:
   For struct members: The member has the smallest possible alignment.
   For struct, union, class: All members have the smallest possible alignment,
   minimizing the memory required.  */
/* Applies to: struct members, struct, union,
   in C++ also: class.  */
#ifndef _GL_ATTRIBUTE_PACKED
# if _GL_HAS_ATTRIBUTE (packed)
#  define _GL_ATTRIBUTE_PACKED __attribute__ ((__packed__))
# else
#  define _GL_ATTRIBUTE_PACKED
# endif
#endif

/* _GL_ATTRIBUTE_PURE declares that It is OK for a compiler to omit duplicate
   calls to the function with the same arguments if observable state is not
   changed between calls.
   This attribute is safe for a function that does not affect
   observable state, and always returns exactly once.
   (This attribute is looser than _GL_ATTRIBUTE_CONST.)  */
/* Applies to: functions.  */
#ifndef _GL_ATTRIBUTE_PURE
# if _GL_HAS_ATTRIBUTE (pure)
#  define _GL_ATTRIBUTE_PURE __attribute__ ((__pure__))
# else
#  define _GL_ATTRIBUTE_PURE
# endif
#endif

/* _GL_ATTRIBUTE_RETURNS_NONNULL declares that the function's return value is
   a non-NULL pointer.  */
/* Applies to: functions.  */
#ifndef _GL_ATTRIBUTE_RETURNS_NONNULL
# if _GL_HAS_ATTRIBUTE (returns_nonnull)
#  define _GL_ATTRIBUTE_RETURNS_NONNULL __attribute__ ((__returns_nonnull__))
# else
#  define _GL_ATTRIBUTE_RETURNS_NONNULL
# endif
#endif

/* _GL_ATTRIBUTE_SENTINEL(pos) declares that the variadic function expects a
   trailing NULL argument.
   _GL_ATTRIBUTE_SENTINEL () - The last argument is NULL (requires C99).
   _GL_ATTRIBUTE_SENTINEL ((N)) - The (N+1)st argument from the end is NULL.  */
/* Applies to: functions.  */
#ifndef _GL_ATTRIBUTE_SENTINEL
# if _GL_HAS_ATTRIBUTE (sentinel)
#  define _GL_ATTRIBUTE_SENTINEL(pos) __attribute__ ((__sentinel__ pos))
# else
#  define _GL_ATTRIBUTE_SENTINEL(pos)
# endif
#endif

/* A helper macro.  Don't use it directly.  */
#ifndef _GL_ATTRIBUTE_UNUSED
# if _GL_HAS_ATTRIBUTE (unused)
#  define _GL_ATTRIBUTE_UNUSED __attribute__ ((__unused__))
# else
#  define _GL_ATTRIBUTE_UNUSED
# endif
#endif


/* _GL_UNUSED_LABEL; declares that it is not a programming mistake if the
   immediately preceding label is not used.  The compiler should not warn
   if the label is not used.  */
/* Applies to: label (both in C and C++).  */
/* Note that g++ < 4.5 does not support the '__attribute__ ((__unused__)) ;'
   syntax.  But clang does.  */
#ifndef _GL_UNUSED_LABEL
# if !(defined __cplusplus && !_GL_GNUC_PREREQ (4, 5)) || defined __clang__
#  define _GL_UNUSED_LABEL _GL_ATTRIBUTE_UNUSED
# else
#  define _GL_UNUSED_LABEL
# endif
#endif


/* In C++, there is the concept of "language linkage", that encompasses
    name mangling and function calling conventions.
    The following macros start and end a block of "C" linkage.  */
#ifdef __cplusplus
# define _GL_BEGIN_C_LINKAGE extern "C" {
# define _GL_END_C_LINKAGE }
#else
# define _GL_BEGIN_C_LINKAGE
# define _GL_END_C_LINKAGE
#endif


/* Define to empty if 'const' does not conform to ANSI C. */
#undef const

/* Define as 'access' if you don't have the eaccess() function. */
#undef eaccess

/* Define as 'int' if <sys/types.h> doesn't define. */
#undef gid_t

/* Define to '__inline__' or '__inline' if that's what the C compiler
   calls it, or to nothing if 'inline' is not supported under any name.  */
#ifndef __cplusplus
#undef inline
#endif

/* Define to long or long long if <stdint.h> and <inttypes.h> don't define. */
#undef intmax_t

/* Work around a bug in Apple GCC 4.0.1 build 5465: In C99 mode, it supports
   the ISO C 99 semantics of 'extern inline' (unlike the GNU C semantics of
   earlier versions), but does not display it by setting __GNUC_STDC_INLINE__.
   __APPLE__ && __MACH__ test for Mac OS X.
   __APPLE_CC__ tests for the Apple compiler and its version.
   __STDC_VERSION__ tests for the C99 mode.  */
#if defined __APPLE__ && defined __MACH__ && __APPLE_CC__ >= 5465 && !defined __cplusplus && __STDC_VERSION__ >= 199901L && !defined __GNUC_STDC_INLINE__
# define __GNUC_STDC_INLINE__ 1
#endif

/* Define to a type if <wchar.h> does not define. */
#undef mbstate_t

/* _GL_CMP (n1, n2) performs a three-valued comparison on n1 vs. n2, where
   n1 and n2 are expressions without side effects, that evaluate to real
   numbers (excluding NaN).
   It returns
     1  if n1 > n2
     0  if n1 == n2
     -1 if n1 < n2
   The naïve code   (n1 > n2 ? 1 : n1 < n2 ? -1 : 0)  produces a conditional
   jump with nearly all GCC versions up to GCC 10.
   This variant     (n1 < n2 ? -1 : n1 > n2)  produces a conditional with many
   GCC versions up to GCC 9.
   The better code  (n1 > n2) - (n1 < n2)  from Hacker's Delight § 2-9
   avoids conditional jumps in all GCC versions >= 3.4.  */
#define _GL_CMP(n1, n2) (((n1) > (n2)) - ((n1) < (n2)))


/* Define to the real name of the mktime_internal function. */
#undef mktime_internal

/* Define to 'int' if <sys/types.h> does not define. */
#undef mode_t

/* Define to the type of st_nlink in struct stat, or a supertype. */
#undef nlink_t

/* Define as a signed integer type capable of holding a process identifier. */
#undef pid_t

/* Define as the type of the result of subtracting two pointers, if the system
   doesn't define it. */
#undef ptrdiff_t

/* Define to rpl_re_comp if the replacement should be used. */
#undef re_comp

/* Define to rpl_re_compile_fastmap if the replacement should be used. */
#undef re_compile_fastmap

/* Define to rpl_re_compile_pattern if the replacement should be used. */
#undef re_compile_pattern

/* Define to rpl_re_exec if the replacement should be used. */
#undef re_exec

/* Define to rpl_re_match if the replacement should be used. */
#undef re_match

/* Define to rpl_re_match_2 if the replacement should be used. */
#undef re_match_2

/* Define to rpl_re_search if the replacement should be used. */
#undef re_search

/* Define to rpl_re_search_2 if the replacement should be used. */
#undef re_search_2

/* Define to rpl_re_set_registers if the replacement should be used. */
#undef re_set_registers

/* Define to rpl_re_set_syntax if the replacement should be used. */
#undef re_set_syntax

/* Define to rpl_re_syntax_options if the replacement should be used. */
#undef re_syntax_options

/* Define to rpl_regcomp if the replacement should be used. */
#undef regcomp

/* Define to rpl_regerror if the replacement should be used. */
#undef regerror

/* Define to rpl_regexec if the replacement should be used. */
#undef regexec

/* Define to rpl_regfree if the replacement should be used. */
#undef regfree

/* Define to the equivalent of the C99 'restrict' keyword, or to
   nothing if this is not supported.  Do not define if restrict is
   supported only directly.  */
#undef restrict
/* Work around a bug in older versions of Sun C++, which did not
   #define __restrict__ or support _Restrict or __restrict__
   even though the corresponding Sun C compiler ended up with
   "#define restrict _Restrict" or "#define restrict __restrict__"
   in the previous line.  This workaround can be removed once
   we assume Oracle Developer Studio 12.5 (2016) or later.  */
#if defined __SUNPRO_CC && !defined __RESTRICT && !defined __restrict__
# define _Restrict
# define __restrict__
#endif

/* Define as an integer type suitable for memory locations that can be
   accessed atomically even in the presence of asynchronous signals. */
#undef sig_atomic_t

/* Define as 'unsigned int' if <stddef.h> doesn't define. */
#undef size_t

/* type to use in place of socklen_t if not defined */
#undef socklen_t

/* Define as a signed type of the same size as size_t. */
#undef ssize_t

/* Define as 'int' if <sys/types.h> doesn't define. */
#undef uid_t


  /* This definition is a duplicate of the one in unitypes.h.
     It is here so that we can cope with an older version of unitypes.h
     that does not contain this definition and that is pre-installed among
     the public header files.  */
  # if defined __restrict \
       || 2 < __GNUC__ + (95 <= __GNUC_MINOR__) \
       || __clang_major__ >= 3
  #  define _UC_RESTRICT __restrict
  # elif 199901L <= __STDC_VERSION__ || defined restrict
  #  define _UC_RESTRICT restrict
  # else
  #  define _UC_RESTRICT
  # endif
  

/* Define to empty if the keyword 'volatile' does not work. Warning: valid
   code using 'volatile' can become incorrect without. Disable with care. */
#undef volatile

#if !defined HAVE_C_ALIGNASOF \
    && !(defined __cplusplus && 201103 <= __cplusplus) \
    && !defined alignof
# if defined HAVE_STDALIGN_H
#  include <stdalign.h>
# endif

/* ISO C23 alignas and alignof for platforms that lack it.

   References:
   ISO C23 (latest free draft
   <http://www.open-std.org/jtc1/sc22/wg14/www/docs/n3047.pdf>)
   sections 6.5.3.4, 6.7.5, 7.15.
   C++11 (latest free draft
   <http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2011/n3242.pdf>)
   section 18.10. */

/* alignof (TYPE), also known as _Alignof (TYPE), yields the alignment
   requirement of a structure member (i.e., slot or field) that is of
   type TYPE, as an integer constant expression.

   This differs from GCC's and clang's __alignof__ operator, which can
   yield a better-performing alignment for an object of that type.  For
   example, on x86 with GCC and on Linux/x86 with clang,
   __alignof__ (double) and __alignof__ (long long) are 8, whereas
   alignof (double) and alignof (long long) are 4 unless the option
   '-malign-double' is used.

   The result cannot be used as a value for an 'enum' constant, if you
   want to be portable to HP-UX 10.20 cc and AIX 3.2.5 xlc.  */

/* GCC releases before GCC 4.9 had a bug in _Alignof.  See GCC bug 52023
   <https://gcc.gnu.org/bugzilla/show_bug.cgi?id=52023>.
   clang versions < 8.0.0 have the same bug.  */
#  if (!defined __STDC_VERSION__ || __STDC_VERSION__ < 201112 \
       || (defined __GNUC__ && __GNUC__ < 4 + (__GNUC_MINOR__ < 9) \
           && !defined __clang__) \
       || (defined __clang__ && __clang_major__ < 8))
#   undef/**/_Alignof
#   ifdef __cplusplus
#    if (201103 <= __cplusplus || defined _MSC_VER)
#     define _Alignof(type) alignof (type)
#    else
      template <class __t> struct __alignof_helper { char __a; __t __b; };
#     if (defined __GNUC__ && 4 <= __GNUC__) || defined __clang__
#      define _Alignof(type) __builtin_offsetof (__alignof_helper<type>, __b)
#     else
#      define _Alignof(type) offsetof (__alignof_helper<type>, __b)
#     endif
#     define _GL_STDALIGN_NEEDS_STDDEF 1
#    endif
#   else
#    if (defined __GNUC__ && 4 <= __GNUC__) || defined __clang__
#     define _Alignof(type) __builtin_offsetof (struct { char __a; type __b; }, __b)
#    else
#     define _Alignof(type) offsetof (struct { char __a; type __b; }, __b)
#     define _GL_STDALIGN_NEEDS_STDDEF 1
#    endif
#   endif
#  endif
#  if ! (defined __cplusplus && (201103 <= __cplusplus || defined _MSC_VER))
#   undef/**/alignof
#   define alignof _Alignof
#  endif

/* alignas (A), also known as _Alignas (A), aligns a variable or type
   to the alignment A, where A is an integer constant expression.  For
   example:

      int alignas (8) foo;
      struct s { int a; int alignas (8) bar; };

   aligns the address of FOO and the offset of BAR to be multiples of 8.

   A should be a power of two that is at least the type's alignment
   and at most the implementation's alignment limit.  This limit is
   2**28 on typical GNUish hosts, and 2**13 on MSVC.  To be portable
   to MSVC through at least version 10.0, A should be an integer
   constant, as MSVC does not support expressions such as 1 << 3.
   To be portable to Sun C 5.11, do not align auto variables to
   anything stricter than their default alignment.

   The following C23 requirements are not supported here:

     - If A is zero, alignas has no effect.
     - alignas can be used multiple times; the strictest one wins.
     - alignas (TYPE) is equivalent to alignas (alignof (TYPE)).

   */
# if !defined __STDC_VERSION__ || __STDC_VERSION__ < 201112
#  if defined __cplusplus && (201103 <= __cplusplus || defined _MSC_VER)
#   define _Alignas(a) alignas (a)
#  elif (!defined __attribute__ \
         && ((defined __APPLE__ && defined __MACH__ \
              ? 4 < __GNUC__ + (1 <= __GNUC_MINOR__) \
              : __GNUC__ && !defined __ibmxl__) \
             || (4 <= __clang_major__) \
             || (__ia64 && (61200 <= __HP_cc || 61200 <= __HP_aCC)) \
             || __ICC || 0x590 <= __SUNPRO_C || 0x0600 <= __xlC__))
#   define _Alignas(a) __attribute__ ((__aligned__ (a)))
#  elif 1300 <= _MSC_VER
#   define _Alignas(a) __declspec (align (a))
#  endif
# endif
# if !defined HAVE_STDALIGN_H
#  if ((defined _Alignas \
        && !(defined __cplusplus \
             && (201103 <= __cplusplus || defined _MSC_VER))) \
       || (defined __STDC_VERSION__ && 201112 <= __STDC_VERSION__))
#   define alignas _Alignas
#  endif
# endif

# if defined _GL_STDALIGN_NEEDS_STDDEF
#  include <stddef.h>
# endif
#endif

#ifndef HAVE_C_BOOL
# if !defined __cplusplus && !defined __bool_true_false_are_defined
#  if HAVE_STDBOOL_H
#   include <stdbool.h>
#  else
#   if defined __SUNPRO_C
#    error "<stdbool.h> is not usable with this configuration. To make it usable, add -D_STDC_C99= to $CC."
#   else
#    error "<stdbool.h> does not exist on this platform. Use gnulib module 'stdbool-c99' instead of gnulib module 'stdbool'."
#   endif
#  endif
# endif
# if !true
#  define true (!false)
# endif
#endif

#if (!defined HAVE_C_STATIC_ASSERT && !defined assert \
     && (!defined __cplusplus \
         || (__cpp_static_assert < 201411 \
             && __GNUG__ < 6 && __clang_major__ < 6)))
 #include <assert.h>
 #undef/**/assert
 #ifdef __sgi
  #undef/**/__ASSERT_H__
 #endif
 /* Solaris 11.4 <assert.h> defines static_assert as a macro with 2 arguments.
    We need it also to be invocable with a single argument.  */
 #if defined __sun && (__STDC_VERSION__ - 0 >= 201112L) && !defined __cplusplus
  #undef/**/static_assert
  #define static_assert _Static_assert
 #endif
#endif


// VMS
// It should be get from test_word_bit.c
// 4 and 0 - I check it on Alpha for example
/* Define as the bit index in the word where to find bit 0 of the exponent of
   'double'. */
#include <stdio.h>
#include <types.h>
#include <stat.h>
#include <stdbool.h>
#include  <assert.h>
#include <pwd.h>
#include <stdint.h>
#include <vms.h>


// Junks from ./fcntl.h
#ifndef O_BINARY
# define O_BINARY 0
# define O_TEXT 0
#endif
#ifndef AT_FDCWD
# define AT_FDCWD (-3041965)
#endif
#ifndef F_DUPFD_CLOEXEC
# define F_DUPFD_CLOEXEC 0x40000000
/* Witness variable: 1 if gnulib defined F_DUPFD_CLOEXEC, 0 otherwise.  */
//# define GNULIB_defined_F_DUPFD_CLOEXEC 1
#else
# define GNULIB_defined_F_DUPFD_CLOEXEC 0
#endif

#ifndef LOCK_SH
/* Operations for the 'flock' call (same as Linux kernel constants).  */
# define LOCK_SH 1       /* Shared lock.  */
# define LOCK_EX 2       /* Exclusive lock.  */
# define LOCK_UN 8       /* Unlock.  */

/* Can be OR'd into one of the above.  */
# define LOCK_NB 4       /* Don't block when locking.  */
#endif

#define DBL_EXPBIT0_BIT 4
# define O_CLOEXEC 0x40000000 /* Try to not collide with system O_* flags.  */
# define GNULIB_defined_O_CLOEXEC 1
/* Define as the word index where to find the exponent of 'double'. */
#define DBL_EXPBIT0_WORD 0

#define __LONG_LONG_MAX__ 9223372036854775807LL
#  define ULLONG_MAX (__LONG_LONG_MAX__ * 2ULL + 1ULL)
# define ULLONG_WIDTH _GL_INTEGER_WIDTH (0, ULLONG_MAX)
#define __align ___align
#define max_align_t long
#define _Noreturn
# define AT_SYMLINK_NOFOLLOW 4096

# ifndef EAI_OVERFLOW
#  define EAI_OVERFLOW    -12   /* Argument buffer overflow.  */
# endif

#ifndef required_argument 
 #define required_argument       1
 #define optional_argument 	 2
 #define no_argument 	 	 0
#endif

#ifndef F_DUPFD_CLOEXEC
# define F_DUPFD_CLOEXEC 0x40000000
/* Witness variable: 1 if gnulib defined F_DUPFD_CLOEXEC, 0 otherwise.  */
# define GNULIB_defined_F_DUPFD_CLOEXEC 1
#else
# define GNULIB_defined_F_DUPFD_CLOEXEC 0
#endif

#define OS_TYPE "VMS"

#define socklen_t    int

#define static_assert(X)

#if (OPENSSL_VERSION_NUMBER >=0x30000000L && !defined SSL_get_peer_certificate)
#define SSL_get_peer_certificate SSL_get1_peer_certificate
#endif
$!
$!
$WRITE SYS$OUTPUT "config.h created"
$!
$!Creating Descrip.mms in each directory needed
$!
$!
$COPY SYS$INPUT [.LIB.MALLOC]DESCRIP.MMS
# (c) Alexey Chupahin 29-APR-2024
# OpenVMS 7.3-2, DEC 2000 mod.300
# OpenVMS 8.3,   Digital PW 600au
# OpenVMS 8.4,   Compaq DS10L
# OpenVMS 8.3,   HP rx1620

.FIRST
        DEFINE malloc []


CC=cc
CFLAGS =  /INCLUDE=([],[-],[--.src],[--.vms]) \
          /DEFINE=(HAVE_CONFIG_H)\
          /OPTIMIZE=(INLINE=SPEED) \
          /WARN=DIS=(QUESTCOMPARE,LONGEXTERN) 

OBJ=\
DYNARRAY_AT_FAILURE.obj,\
DYNARRAY_EMPLACE_ENLARGE.obj,\
DYNARRAY_FINALIZE.obj,\
DYNARRAY_RESIZE.obj,\
DYNARRAY_RESIZE_CLEAR.obj,\
SCRATCH_BUFFER_GROW.obj,\
SCRATCH_BUFFER_GROW_PRESERVE.obj,\
SCRATCH_BUFFER_SET_ARRAY_SIZE.obj

ALL : $(OBJ)
        $!

DYNARRAY-SKELETON.obj : DYNARRAY-SKELETON.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

DYNARRAY_AT_FAILURE.obj : DYNARRAY_AT_FAILURE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

DYNARRAY_EMPLACE_ENLARGE.obj : DYNARRAY_EMPLACE_ENLARGE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

DYNARRAY_FINALIZE.obj : DYNARRAY_FINALIZE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

DYNARRAY_RESIZE.obj : DYNARRAY_RESIZE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

DYNARRAY_RESIZE_CLEAR.obj : DYNARRAY_RESIZE_CLEAR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SCRATCH_BUFFER_GROW.obj : SCRATCH_BUFFER_GROW.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SCRATCH_BUFFER_GROW_PRESERVE.obj : SCRATCH_BUFFER_GROW_PRESERVE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SCRATCH_BUFFER_SET_ARRAY_SIZE.obj : SCRATCH_BUFFER_SET_ARRAY_SIZE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)
 
$COPY SYS$INPUT [.LIB]DESCRIP.MMS
# (c) Alexey Chupahin 29-APR-2024
# OpenVMS 7.3-2, DEC 2000 mod.300
# OpenVMS 8.3,   Digital PW 600au
# OpenVMS 8.4,   Compaq DS10L
# OpenVMS 8.3,   HP rx1620

.FIRST
        DEF malloc [.MALLOC]

CC=cc
CFLAGS =  /INCLUDE=([],[-],[-.src],[-.vms]) \
          /DEFINE=(HAVE_CONFIG_H,__USE_GNU)\
          /OPTIMIZE=(INLINE=SPEED) \
          /WARN=DIS=(QUESTCOMPARE,LONGEXTERN,NOTINCRTL) 

OBJ=\
AF_ALG.OBJ,\
ALLOCA.OBJ,\
ASNPRINTF.OBJ,\
BASE32.OBJ,\
BASENAME-LGPL.OBJ,\
BASENAME.OBJ,\
BINARY-IO-VMS.OBJ,\
BITROTATE.OBJ,\
BTOWC.OBJ,\
C-CTYPE.OBJ,\
C-STRCASECMP.OBJ,\
C-STRCASESTR.OBJ,\
C-STRNCASECMP.OBJ,\
C32ISPRINT.OBJ,\
CANONICALIZE.OBJ,\
CONCAT-FILENAME.OBJ,\
DIRFD.OBJ,\
DIRNAME-LGPL.OBJ,\
DIRNAME.OBJ,\
DUP-SAFER-FLAG.OBJ,\
DUP-SAFER.OBJ,\
DUP.OBJ,\
DUP2.OBJ,\
EXITFAIL.OBJ,\
FATAL-SIGNAL.OBJ,\
FCHDIR.OBJ,\
FD-HOOK.OBJ,\
FD-SAFER-FLAG.OBJ,\
FD-SAFER.OBJ,\
FDOPENDIR.OBJ,\
FFLUSH.OBJ,\
FILE-SET.OBJ,\
FILENAMECAT-LGPL.OBJ,\
FINDPROG-IN.OBJ,\
FLOAT.OBJ,\
FLOCK.OBJ,\
FNMATCH.OBJ,\
FOPEN.OBJ,\
FPURGE.OBJ,\
FREADING.OBJ,\
FREE.OBJ,\
FSTAT.OBJ,\
FSTATAT.OBJ,\
FUTIMENS.OBJ,\
GAI_STRERROR.OBJ,\
GETDELIM.OBJ,\
GETLINE.OBJ,\
GETOPT.OBJ,\
GETOPT1.OBJ,\
GETPASS.OBJ,\
GETRANDOM.OBJ,\
GROUP-MEMBER.OBJ,\
HASH-PJW.OBJ,\
HASH.OBJ,\
IALLOC.OBJ,\
ISBLANK.OBJ,\
ISWBLANK.OBJ,\
ITOLD.OBJ,\
LC-CHARSET-DISPATCH.OBJ,\
LOCALCHARSET.OBJ,\
MBCHAR.OBJ,\
MBITER.OBJ,\
MBRTOC32.OBJ,\
MBRTOWC.OBJ,\
MBSINIT.OBJ,\
MBSRTOC32S-STATE.OBJ,\
MBSRTOC32S.OBJ,\
MBSRTOWCS-STATE.OBJ,\
MBSRTOWCS.OBJ,\
MBSZERO.OBJ,\
MD2-STREAM.OBJ,\
MD2.OBJ,\
MD4-STREAM.OBJ,\
MD4.OBJ,\
MD5.OBJ,\
MEMPCPY.OBJ,\
MEMRCHR.OBJ,\
MKTIME.OBJ,\
QUOTEARG.OBJ,\
REALLOCARRAY.OBJ,\
REGEX.OBJ,\
SHA1-STREAM.OBJ,\
SHA256.OBJ,\
STRNDUP.OBJ,\
STRNLEN1.OBJ,\
TIMEGM.OBJ,\
TMPDIR.OBJ,\
WMEMPCPY.OBJ,\
XALLOC-DIE.OBJ,\
XMALLOC.OBJ,\
XSTRNDUP.OBJ
ALL : LIB.OLB
        $!

LIB.OLB : $(OBJ)
        LIB/CREA LIB.OLB [...]*.OBJ

ACCEPT.obj : ACCEPT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

ACCESS.obj : ACCESS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

AF_ALG.obj : AF_ALG.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

ALLOCA.obj : ALLOCA.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

ASNPRINTF.obj : ASNPRINTF.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

ASPRINTF.obj : ASPRINTF.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

AT-FUNC.obj : AT-FUNC.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

BASE32.obj : BASE32.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

BASENAME-LGPL.obj : BASENAME-LGPL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

BASENAME.obj : BASENAME.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

BINARY-IO-VMS.obj : [-.VMS]BINARY-IO-VMS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

BIND.obj : BIND.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

BITROTATE.obj : BITROTATE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

BTOC32.obj : BTOC32.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

BTOWC.obj : BTOWC.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C-CTYPE.obj : C-CTYPE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C-STRCASECMP.obj : C-STRCASECMP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C-STRCASESTR.obj : C-STRCASESTR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C-STRNCASECMP.obj : C-STRNCASECMP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C32ISALNUM.obj : C32ISALNUM.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C32ISALPHA.obj : C32ISALPHA.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C32ISBLANK.obj : C32ISBLANK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C32ISCNTRL.obj : C32ISCNTRL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C32ISDIGIT.obj : C32ISDIGIT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C32ISGRAPH.obj : C32ISGRAPH.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C32ISLOWER.obj : C32ISLOWER.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C32ISPRINT.obj : C32ISPRINT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C32ISPUNCT.obj : C32ISPUNCT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C32ISSPACE.obj : C32ISSPACE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C32ISUPPER.obj : C32ISUPPER.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C32ISXDIGIT.obj : C32ISXDIGIT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C32TOLOWER.obj : C32TOLOWER.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C32WIDTH.obj : C32WIDTH.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C32_APPLY_TYPE_TEST.obj : C32_APPLY_TYPE_TEST.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

C32_GET_TYPE_TEST.obj : C32_GET_TYPE_TEST.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

CALLOC.obj : CALLOC.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

CANONICALIZE-LGPL.obj : CANONICALIZE-LGPL.C
         perl -p -i -e "s/scratch_buffer.gl.h/scratch_buffer.gl_h/g" SCRATCH_BUFFER.H
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

CANONICALIZE.obj : CANONICALIZE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

CHDIR-LONG.obj : CHDIR-LONG.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

CLOEXEC.obj : CLOEXEC.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

CLOSE.obj : CLOSE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

CLOSEDIR.obj : CLOSEDIR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

CONCAT-FILENAME.obj : CONCAT-FILENAME.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

CONNECT.obj : CONNECT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

DIRFD.obj : DIRFD.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

DIRNAME-LGPL.obj : DIRNAME-LGPL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

DIRNAME.obj : DIRNAME.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

DUP-SAFER-FLAG.obj : DUP-SAFER-FLAG.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

DUP-SAFER.obj : DUP-SAFER.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

DUP.obj : DUP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

DUP2.obj : DUP2.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

ERROR.obj : ERROR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

EXITFAIL.obj : EXITFAIL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FATAL-SIGNAL.obj : FATAL-SIGNAL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FCHDIR.obj : FCHDIR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FCNTL.obj : FCNTL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FD-HOOK.obj : FD-HOOK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FD-SAFER-FLAG.obj : FD-SAFER-FLAG.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FD-SAFER.obj : FD-SAFER.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FDOPENDIR.obj : FDOPENDIR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FFLUSH.obj : FFLUSH.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FILE-SET.obj : FILE-SET.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FILENAMECAT-LGPL.obj : FILENAMECAT-LGPL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FINDPROG-IN.obj : FINDPROG-IN.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FLOAT.obj : FLOAT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FLOCK.obj : FLOCK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FNMATCH.obj : FNMATCH.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FNMATCH_LOOP.obj : FNMATCH_LOOP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FOPEN.obj : FOPEN.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FPURGE.obj : FPURGE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FREADING.obj : FREADING.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FREE.obj : FREE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FSEEK.obj : FSEEK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FSEEKO.obj : FSEEKO.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FSTAT.obj : FSTAT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FSTATAT.obj : FSTATAT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FTELL.obj : FTELL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FTELLO.obj : FTELLO.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FUTIMENS.obj : FUTIMENS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

GAI_STRERROR.obj : GAI_STRERROR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

GETDELIM.obj : GETDELIM.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

GETDTABLESIZE.obj : GETDTABLESIZE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

GETGROUPS.obj : GETGROUPS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

GETLINE.obj : GETLINE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

GETOPT.obj : GETOPT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

GETOPT1.obj : GETOPT1.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

GETPASS.obj : [-.VMS]GETPASS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

GETPEERNAME.obj : GETPEERNAME.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

GETPROGNAME.obj : GETPROGNAME.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

GETRANDOM.obj : [-.VMS]GETRANDOM.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

GETSOCKNAME.obj : GETSOCKNAME.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

GETTIME.obj : GETTIME.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

GETTIMEOFDAY.obj : GETTIMEOFDAY.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

GROUP-MEMBER.obj : GROUP-MEMBER.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

HARD-LOCALE.obj : HARD-LOCALE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

HASH-PJW.obj : HASH-PJW.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

HASH-TRIPLE-SIMPLE.obj : HASH-TRIPLE-SIMPLE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

HASH.obj : HASH.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

IALLOC.obj : IALLOC.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

INET_NTOP.obj : INET_NTOP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

IOCTL.obj : IOCTL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

ISBLANK.obj : ISBLANK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

ISWBLANK.obj : ISWBLANK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

ISWCTYPE.obj : ISWCTYPE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

ISWDIGIT.obj : ISWDIGIT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

ISWPUNCT.obj : ISWPUNCT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

ISWXDIGIT.obj : ISWXDIGIT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

ITOLD.obj : ITOLD.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

LC-CHARSET-DISPATCH.obj : LC-CHARSET-DISPATCH.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

LINK.obj : LINK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

LISTEN.obj : LISTEN.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

LOCALCHARSET.obj : LOCALCHARSET.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

LOCALECONV.obj : LOCALECONV.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

LSEEK.obj : LSEEK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

LSTAT.obj : LSTAT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MALLOC.obj : MALLOC.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MALLOCA.obj : MALLOCA.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MBCHAR.obj : MBCHAR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MBITER.obj : MBITER.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MBRTOC32.obj : MBRTOC32.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MBRTOWC.obj : MBRTOWC.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MBSINIT.obj : MBSINIT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MBSRTOC32S-STATE.obj : MBSRTOC32S-STATE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MBSRTOC32S.obj : MBSRTOC32S.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MBSRTOWCS-STATE.obj : MBSRTOWCS-STATE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MBSRTOWCS.obj : MBSRTOWCS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MBSZERO.obj : [-.VMS]MBSZERO.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MBTOWC-LOCK.obj : MBTOWC-LOCK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MBTOWC.obj : MBTOWC.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MD2-STREAM.obj : MD2-STREAM.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MD2.obj : MD2.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MD4-STREAM.obj : MD4-STREAM.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MD4.obj : MD4.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MD5-STREAM.obj : MD5-STREAM.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MD5.obj : MD5.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MEMCHR.obj : MEMCHR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MEMPCPY.obj : MEMPCPY.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MEMRCHR.obj : MEMRCHR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MKDIR.obj : MKDIR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MKOSTEMP.obj : MKOSTEMP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MKSTEMP.obj : MKSTEMP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MKTIME.obj : MKTIME.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MSVC-INVAL.obj : MSVC-INVAL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MSVC-NOTHROW.obj : MSVC-NOTHROW.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

NANOSLEEP.obj : NANOSLEEP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

NL_LANGINFO-LOCK.obj : NL_LANGINFO-LOCK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

NL_LANGINFO.obj : NL_LANGINFO.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

OPEN.obj : OPEN.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

OPENAT-DIE.obj : OPENAT-DIE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

OPENAT-PROC.obj : OPENAT-PROC.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

OPENAT.obj : OPENAT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

OPENDIR.obj : OPENDIR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

OS2-SPAWN.obj : OS2-SPAWN.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

PIPE-SAFER.obj : PIPE-SAFER.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

PIPE.obj : PIPE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

PIPE2-SAFER.obj : PIPE2-SAFER.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

PIPE2.obj : PIPE2.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

PRINTF-ARGS.obj : PRINTF-ARGS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

PRINTF-PARSE.obj : PRINTF-PARSE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

PSELECT.obj : PSELECT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

PTHREAD_SIGMASK.obj : PTHREAD_SIGMASK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

QUOTEARG.obj : QUOTEARG.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)


RAISE.obj : RAISE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

RAWMEMCHR.obj : RAWMEMCHR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

READDIR.obj : READDIR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

READLINK.obj : READLINK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

REALLOC.obj : REALLOC.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

REALLOCARRAY.obj : REALLOCARRAY.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

RECV.obj : RECV.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

REGCOMP.obj : REGCOMP.C
         $(CC) $(CFLAGS) /FIRST_INCL=REGEX.H $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

REGEX.obj : REGEX.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

REGEXEC.obj : REGEXEC.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

REGEX_INTERNAL.obj : REGEX_INTERNAL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

RENAME.obj : RENAME.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

REWINDDIR.obj : REWINDDIR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

RMDIR.obj : RMDIR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SAME-INODE.obj : SAME-INODE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SAVE-CWD.obj : SAVE-CWD.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SECURE_GETENV.obj : SECURE_GETENV.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SELECT.obj : SELECT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SEND.obj : SEND.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SETLOCALE-LOCK.obj : SETLOCALE-LOCK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SETLOCALE_NULL-UNLOCKED.obj : SETLOCALE_NULL-UNLOCKED.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SETLOCALE_NULL.obj : SETLOCALE_NULL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SETSOCKOPT.obj : SETSOCKOPT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SHA1-STREAM.obj : SHA1-STREAM.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SHA1.obj : SHA1.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SHA256-STREAM.obj : SHA256-STREAM.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SHA256.obj : SHA256.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SHA512-STREAM.obj : SHA512-STREAM.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SHA512.obj : SHA512.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SIG-HANDLER.obj : SIG-HANDLER.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SIGACTION.obj : SIGACTION.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SIGPROCMASK.obj : SIGPROCMASK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SNPRINTF.obj : SNPRINTF.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SOCKET.obj : SOCKET.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SOCKETS.obj : SOCKETS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SPAWN-PIPE.obj : SPAWN-PIPE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SPAWN.obj : SPAWN.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SPAWNATTR_DESTROY.obj : SPAWNATTR_DESTROY.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SPAWNATTR_INIT.obj : SPAWNATTR_INIT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SPAWNATTR_SETFLAGS.obj : SPAWNATTR_SETFLAGS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SPAWNATTR_SETPGROUP.obj : SPAWNATTR_SETPGROUP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SPAWNATTR_SETSIGMASK.obj : SPAWNATTR_SETSIGMASK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SPAWNI.obj : SPAWNI.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SPAWNP.obj : SPAWNP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SPAWN_FACTION_ADDCHDIR.obj : SPAWN_FACTION_ADDCHDIR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SPAWN_FACTION_ADDCLOSE.obj : SPAWN_FACTION_ADDCLOSE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SPAWN_FACTION_ADDDUP2.obj : SPAWN_FACTION_ADDDUP2.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SPAWN_FACTION_ADDOPEN.obj : SPAWN_FACTION_ADDOPEN.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SPAWN_FACTION_DESTROY.obj : SPAWN_FACTION_DESTROY.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SPAWN_FACTION_INIT.obj : SPAWN_FACTION_INIT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STAT-TIME.obj : STAT-TIME.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STAT-W32.obj : STAT-W32.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STAT.obj : STAT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STDIO-READ.obj : STDIO-READ.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STDIO-WRITE.obj : STDIO-WRITE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STPCPY.obj : STPCPY.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STRCASECMP.obj : STRCASECMP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STRCHRNUL.obj : STRCHRNUL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STRDUP.obj : STRDUP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STRERROR-OVERRIDE.obj : STRERROR-OVERRIDE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STRERROR.obj : STRERROR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STRERROR_R.obj : STRERROR_R.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STRIPSLASH.obj : STRIPSLASH.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STRNCASECMP.obj : STRNCASECMP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STRNDUP.obj : STRNDUP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STRNLEN.obj : STRNLEN.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STRNLEN1.obj : STRNLEN1.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STRPBRK.obj : STRPBRK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STRPTIME.obj : STRPTIME.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STRTOK_R.obj : STRTOK_R.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STRTOL.obj : STRTOL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

STRTOLL.obj : STRTOLL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SYMLINK.obj : SYMLINK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SYS_SOCKET.obj : SYS_SOCKET.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

TEMPNAME.obj : TEMPNAME.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

TIMEGM.obj : TIMEGM.C
         $(CC) $(CFLAGS) $(MMS$SOURCE)/LIST /OBJ=$(MMS$TARGET)

TIMESPEC.obj : TIMESPEC.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

TIME_R.obj : TIME_R.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

TMPDIR.obj : TMPDIR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

U64.obj : U64.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

UNISTD.obj : UNISTD.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

UNLINK.obj : UNLINK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

UTIME.obj : UTIME.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

UTIMENS.obj : UTIMENS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

VASNPRINTF.obj : VASNPRINTF.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

VASPRINTF.obj : VASPRINTF.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

VSNPRINTF.obj : VSNPRINTF.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

WAIT-PROCESS.obj : WAIT-PROCESS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

WAITPID.obj : WAITPID.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

WCRTOMB.obj : WCRTOMB.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

WCTYPE-H.obj : WCTYPE-H.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

WCTYPE.obj : WCTYPE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

WCWIDTH.obj : WCWIDTH.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

WINDOWS-MUTEX.obj : WINDOWS-MUTEX.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

WINDOWS-ONCE.obj : WINDOWS-ONCE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

WINDOWS-RECMUTEX.obj : WINDOWS-RECMUTEX.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

WINDOWS-RWLOCK.obj : WINDOWS-RWLOCK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

WINDOWS-SPAWN.obj : WINDOWS-SPAWN.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

WMEMCHR.obj : WMEMCHR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

WMEMPCPY.obj : WMEMPCPY.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

WRITE.obj : WRITE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

XALLOC-DIE.obj : XALLOC-DIE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

XMALLOC.obj : XMALLOC.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

XMEMDUP0.obj : XMEMDUP0.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

XSIZE.obj : XSIZE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

XSTRNDUP.obj : XSTRNDUP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

$!
$COPY SYS$INPUT [.SRC]DESCRIP.MMS
# (c) Alexey Chupahin 29-APR-2024
# OpenVMS 7.3-2, DEC 2000 mod.300
# OpenVMS 8.3,   Digital PW 600au
# OpenVMS 8.4,   Compaq DS10L
# OpenVMS 8.3,   HP rx1620

.FIRST
        DEF LIB [-.LIB]
        DEF SYS [-.VMS]


CC=cc
CFLAGS =  /INCLUDE=([],[-.VMS],LIB,IDN2LIB,ZLIB) \
          /DEFINE=(HAVE_CONFIG_H,HAVE_PWD_H,OPENSSL_RUN_WITHTIMEOUT)\
          /OPTIMIZE

OBJ=\
BUILD_INFO.obj,\
CONNECT.obj,\
CONVERT.obj,\
COOKIES.obj,\
CSS-URL.obj,\
CSS_.obj,\
EXITS.obj,\
FTP-BASIC.obj,\
FTP-LS.obj,\
FTP-OPIE.obj,\
FTP.obj,\
HASH.obj,\
HOST.obj,\
HSTS.obj,\
HTML-PARSE.obj,\
HTML-URL.obj,\
HTTP-NTLM.obj,\
HTTP.obj,\
INIT.obj,\
IRI.obj,\
LOG.obj,\
MAIN.obj,\
METALINK.obj,\
NETRC.obj,\
OPENSSL.obj,\
PROGRESS.obj,\
PTIMER.obj,\
RECUR.obj,\
RES.obj,\
RETR.obj,\
SPIDER.obj,\
URL.obj,\
UTILS.obj,\
WARC.obj,\
VMS.obj,\
XATTR.obj

ALL : WGET.EXE
	$!

WGET.EXE : SRC.OLB
        LINK/EXE:WGET.EXE MAIN,SRC/LIB,[-.LIB]LIB/LIB,IDN2LIB:IDN2/OPT,[-.VMS]SSL.OPT/OPT,ZLIB:ZLIB.OPT/OPT

SRC.OLB : $(OBJ)
        LIB/CREA SRC $(OBJ)

BUILD_INFO.obj : BUILD_INFO.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

CONNECT.obj : CONNECT.C
         $(CC) $(CFLAGS) /WAR=DIS=PTRMISMATCH1 $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

CONVERT.obj : CONVERT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

COOKIES.obj : COOKIES.C
         APP [-.VMS]INC_VMS.H []COOKIES.H
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

CSS-URL.obj : CSS-URL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

CSS.obj : CSS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

CSS_.obj : CSS_.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

EXITS.obj : EXITS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FTP-BASIC.obj : FTP-BASIC.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FTP-LS.obj : FTP-LS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FTP-OPIE.obj : FTP-OPIE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

FTP.obj : FTP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

GNUTLS.obj : GNUTLS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

HASH.obj : HASH.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

HOST.obj : HOST.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

HSTS.obj : HSTS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

HTML-PARSE.obj : HTML-PARSE.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

HTML-URL.obj : HTML-URL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

HTTP-NTLM.obj : HTTP-NTLM.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

HTTP.obj : HTTP.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

INIT.obj : INIT.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

IRI.obj : IRI.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

LOG.obj : LOG.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MAIN.obj : MAIN.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

METALINK.obj : METALINK.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

MSWINDOWS.obj : MSWINDOWS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

NETRC.obj : NETRC.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

OPENSSL.obj : OPENSSL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

PROGRESS.obj : PROGRESS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

PTIMER.obj : PTIMER.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

RECUR.obj : RECUR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

RES.obj : RES.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

RETR.obj : RETR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

SPIDER.obj : SPIDER.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

URL.obj : URL.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

UTILS.obj : UTILS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

WARC.obj : WARC.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

VMS.obj : [-.VMS]VMS.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)

XATTR.obj : XATTR.C
         $(CC) $(CFLAGS) $(MMS$SOURCE) /OBJ=$(MMS$TARGET)
 
$!
$!
$WRITE SYS$OUTPUT "DESCRIP.MMS's have been created"
$WRITE SYS$OUTPUT " "
$WRITE SYS$OUTPUT " "
$WRITE SYS$OUTPUT "Now you can type @BUILD "
$!
$EXIT:
$DEFINE SYS$ERROR _NLA0:
$DEFINE SYS$OUTPUT _NLA0:
$DEL TEST.C;*
$DEL TEST.OBJ;*
$DEL TEST.EXE;*
$DEL TEST.OPT;*
$DEAS SYS$ERROR
$DEAS SYS$OUTPUT

