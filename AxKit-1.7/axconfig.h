/* $Id: axconfig.h,v 1.9 2004/07/13 18:05:45 nachbaur Exp $ */

#ifdef WIN32
#define _INC_DIRENT
#define DIR void
#endif
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>
#ifdef WIN32
#ifdef lstat
#define apache_lstat lstat
#undef lstat
#endif
#include "modules/perl/mod_perl.h"
#ifdef apache_lstat
#undef lstat
#define lstat apache_lstat
#undef apache_lstat
#endif
#else
#include <httpd.h>
#include <http_config.h>
 /* SUNPRO C does not know something about __attribute__ */
 #ifdef __SUNPRO_C
  #include <http_core.h>
  #include <http_main.h>
  #include <http_protocol.h>
  #include <http_request.h>
  #include <http_log.h>
 #endif
#endif
#include <iconv.h>

typedef struct {
    /* simple types */
    char * cache_dir;
    char * config_reader_module;
    char * contentprovider_module;
    char * styleprovider_module;
    char * default_style;
    char * default_media;
    char * cache_module;
    char * output_charset;
    char * trace_intermediate;
    char * dir_handler_module;
    int    debug_tidy;
    int    debug_level;
    int    translate_output;
    int    gzip_output;
    int    reset_processors;
    int    log_declines;
    int    stack_trace;
    int    no_cache;
    int    dependency_checks;
    int    reset_output_transformers;
    int    reset_plugins;
    int    handle_dirs;
    int    ignore_style_pi;

    /* complex types */
    HV *   type_map;            /* mime type => module mapping */
    HV *   processors;          /* processor map */
    AV *   dynamic_processors;  /* dynamic processor map */
    HV *   xsp_taglibs;
    AV *   current_styles;
    AV *   current_medias;
    AV *   error_stylesheet;
    AV *   output_transformers;
    AV *   current_plugins;

} axkit_dir_config;

typedef struct {
    /* simple types */
    char * external_encoding;
    iconv_t iconv_handle;
} axkit_server_config;

extern module MODULE_VAR_EXPORT XS_AxKit;

void remove_module_cleanup(void * ignore);

HV * ax_get_config (axkit_dir_config * cfg);

void ax_get_server_config (axkit_server_config * cfg, HV *hash);

void maybe_load_module (char * name);

