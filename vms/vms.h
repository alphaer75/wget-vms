/*
 *    Various VMS-specific items.
 *
 *    Includes:
 *
 *  Emergency replacement for <utime.h> for VMS CRTL before V7.3.
 *
 *  Emergency replacement for <pwd.h> for VMS CRTL before V7.0.
 *
 *  Prototypes for VMS-specific functions:
 *     acc_cb()
 *     utime() (CRTL < V7.3)
 *     ods_conform()
 *     set_ods5_dest()
 *     vms_arch()
 *     vms_basename()
 *     vms_vers()
 *     vms_version_supplement()
 *
 *  Global storage:
 *     ods5_dest
 */

#ifndef __VMS_H_INCLUDED
#define __VMS_H_INCLUDED

#include <wchar.h>

/* Emergency replacement for <utime.h> for VMS before V7.3. */
#include <stdio.h>
#include <types.h>


#if __CRTL_VER < 70300000

#include <types.h>

/* The "utimbuf" structure is used by "utime()". */
struct utimbuf {
        time_t actime;          /* access time */
        time_t modtime;         /* modification time */
};

/* Function prototypes for utime(), */

int utime( const char *path, const struct utimbuf *times);

#else /* __CRTL_VER < 70300000 */

#include <utime.h>

#endif /* __CRTL_VER < 70300000 */


#include <time.h>

/* Global storage. */

/*    VMS destination file system type.  < 0: unset/unknown
                                         = 0: ODS2
                                         > 0: ODS5
*/

extern int ods5_dest;


/* Function prototypes. */

extern int acc_cb();

char *ods_conform( char *path);

int set_ods5_dest( char *path);

char *vms_arch( void);

char *vms_basename( char *file_spec);

char *vms_vers( void);

int vms_version_supplement( void);

/* Emergency replacement for <pwd.h> (for VMS CRTL before V7.0). */

/* Declare "passwd" structure, if needed. */

#ifndef HAVE_PWD_H

struct passwd {
        char    *pw_name;
        char    *pw_passwd;
        int     pw_uid;
        int     pw_gid;
        short   pw_salt;
        int     pw_encrypt;
        char    *pw_age;
        char    *pw_comment;
        char    *pw_gecos;
        char    *pw_dir;
        char    *pw_shell;
};

struct passwd *getpwuid();

#endif /* HAVE_PWD_H */

#ifndef RE_TRANSLATE_TYPE
# define RE_TRANSLATE_TYPE unsigned char *
#endif
#ifndef __RE_TRANSLATE_TYPE
# define __RE_TRANSLATE_TYPE unsigned char *
#endif

int
flock (int fd, int operation);
void *
reallocarray (void *ptr, size_t nmemb, size_t size);
void *
rawmemchr (const void *s, int c_in);
void *
mempcpy (void *dest, const void *src, size_t n);
char *
stpcpy (char *dest, const char *src);
int
dup_safer_flag (int fd, int flag);
int
fchdir (int fd);
ssize_t getrandom (void *buffer, size_t length, unsigned int flags);
void *
memrchr (void const *s, int c_in, size_t n);
char *
getpass (const char *prompt);
ssize_t
getdelim (char **lineptr, size_t *n, int delimiter, FILE *fp);
ssize_t
getline (char **lineptr, size_t *n, FILE *stream);
time_t
timegm (struct tm *tmp);
void
mbszero (mbstate_t *ps);
char *
strchrnul (const char *s, int c_in);
char *
base_name (char const *name);
int
fpurge (FILE *fp);
const char * 
secure_getenv(char *var);
char *
strndup (char const *s, size_t n);
/*int
u8_mbtouc_unsafe (ucs4_t *puc, const uint8_t *s, size_t n);
int
u8_uctomb (uint8_t *s, ucs4_t uc, ptrdiff_t n);
*/
#endif /* __VMS_H_INCLUDED */
