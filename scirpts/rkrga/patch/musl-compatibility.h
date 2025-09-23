#ifndef MUSL_COMPATIBILITY_H
#define MUSL_COMPATIBILITY_H

/* 
 * musl libc compatibility header
 * 解决 musl libc 与 glibc 兼容性问题
 */

#ifdef __MUSL__
/* 为 musl libc 定义缺失的宏 */

#ifndef __BEGIN_DECLS
#ifdef __cplusplus
#define __BEGIN_DECLS extern "C" {
#define __END_DECLS }
#else
#define __BEGIN_DECLS
#define __END_DECLS
#endif
#endif /* __BEGIN_DECLS */

/* musl libc 不提供 sys/cdefs.h，这里提供必要的定义 */
#ifndef _SYS_CDEFS_H_
#define _SYS_CDEFS_H_

#ifndef __GNUC_PREREQ
#define __GNUC_PREREQ(maj, min) \
    ((__GNUC__ << 16) + __GNUC_MINOR__ >= ((maj) << 16) + (min))
#endif

#ifndef __predict_true
#define __predict_true(exp) __builtin_expect((exp), 1)
#endif

#ifndef __predict_false
#define __predict_false(exp) __builtin_expect((exp), 0)
#endif

#ifndef __unused
#define __unused __attribute__((__unused__))
#endif

#ifndef __packed
#define __packed __attribute__((__packed__))
#endif

#ifndef __aligned
#define __aligned(x) __attribute__((__aligned__(x)))
#endif

#ifndef __section
#define __section(x) __attribute__((__section__(x)))
#endif

#ifndef __deprecated
#define __deprecated __attribute__((__deprecated__))
#endif

#ifndef __weak
#define __weak __attribute__((__weak__))
#endif

#ifndef __strong
#define __strong __attribute__((__strong__))
#endif

#ifndef __pure
#define __pure __attribute__((__pure__))
#endif

#ifndef __const
#define __const __attribute__((__const__))
#endif

#ifndef __dead
#define __dead __attribute__((__noreturn__))
#endif

#ifndef __malloc
#define __malloc __attribute__((__malloc__))
#endif

#ifndef __printflike
#define __printflike(fmtarg, firstvararg) \
    __attribute__((__format__ (__printf__, fmtarg, firstvararg)))
#endif

#ifndef __scanflike
#define __scanflike(fmtarg, firstvararg) \
    __attribute__((__format__ (__scanf__, fmtarg, firstvararg)))
#endif

#ifndef __nonnull
#define __nonnull(x) __attribute__((__nonnull__ x))
#endif

#ifndef __returns_twice
#define __returns_twice __attribute__((__returns_twice__))
#endif

#ifndef __always_inline
#define __always_inline __attribute__((__always_inline__))
#endif

#ifndef __noinline
#define __noinline __attribute__((__noinline__))
#endif

#ifndef __wur
#define __wur __attribute__((__warn_unused_result__))
#endif

#endif /* _SYS_CDEFS_H_ */

#endif /* __MUSL__ */

/* 确保包含标准整数类型定义 */
#include <stdint.h>
#include <sys/types.h>

#endif /* MUSL_COMPATIBILITY_H */