/* $Id: axconfig.h,v 1.5 2001/06/05 09:28:45 matt Exp $ */

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
#endif

typedef struct {
    /* simple types */
    char * cache_dir;
    char * config_reader_module;
    char * provider_module;
    char * styleprovider_module;
    char * default_style;
    char * default_media;
    char * cache_module;
    char * output_charset;
    char * debug_level;
    int    translate_output;
    int    gzip_output; 
    int    reset_processors;
    int    log_declines;
    int    stack_trace;
    int    no_cache;
    
    /* complex types */
    HV *   type_map;            /* mime type => module mapping */
    HV *   processors;          /* processor map */
    AV *   dynamic_processors;  /* dynamic processor map */
    HV *   xsp_taglibs;
    AV *   current_styles;
    AV *   current_medias;
    AV *   error_stylesheet;
    
} axkit_dir_config;

module MODULE_VAR_EXPORT XS_AxKit;

void remove_module_cleanup(void * ignore);

HV * ax_get_config (axkit_dir_config * cfg);

