/* $Id: axconfig.c,v 1.16 2002/09/20 17:00:24 jwalt Exp $ */

#ifndef WIN32
#include <modules/perl/mod_perl.h>
#include <httpd.h>
#include <http_config.h>
#endif
#include "axconfig.h"

#ifdef WIN32
#define ax_preload_module(name)
#else
static void ax_preload_module(char **name)
{
    if(ind(*name, ' ') >= 0) return;
    if(**name == '-' && ++*name) return;
    if(**name == '+') ++*name;
    else if(!PERL_AUTOPRELOAD) return;
    if(!PERL_RUNNING()) return;

    maybe_load_module(*name);
}
#endif

extern SV *error_str;

static SV *module2file(char *name)
{
    SV *sv = newSVpv(name,0);
    char *s;
    for (s = SvPVX(sv); *s; s++) {
        if (*s == ':' && s[1] == ':') {
            *s = '/';
            Move(s+2, s+1, strlen(s+2)+1, char);
            --SvCUR(sv);
        }
    }
    sv_catpvn(sv, ".pm", 3);
    return sv;
}

static I32 module_is_loaded(SV *key)
{
    I32 retval = FALSE;
    if((key && hv_exists_ent(GvHV(incgv), key, FALSE)))
        retval = TRUE;
    return retval;
}

void
maybe_load_module(char * name)
{
    STRLEN len;
    SV * sv_file = module2file(name);
    char * ch_file = SvPV(sv_file, len);
    
    if(!module_is_loaded(sv_file)) {
        perl_require_pv(ch_file);
        if (SvTRUE(ERRSV)) {
            SvREFCNT_dec(sv_file);
            croak("AxKit::load_module failed: %s", SvPV(ERRSV, len));
        }
    }
    SvREFCNT_dec(sv_file);
}

void
ax_cleanup_av(void * av_v)
{
    AV * my_av = (AV*)av_v;
    /* warn("cleanup_av : %d : %d\n", SvREFCNT((SV*)my_av), my_av); */
    SvREFCNT_dec((SV*)my_av);
}

void
ax_cleanup_hv(void * hv_v)
{
    HV * my_hv = (HV*)hv_v;
    /* warn("cleanup_hv : %d : %d\n", SvREFCNT((SV*)my_hv), my_hv); */
    SvREFCNT_dec((SV*)my_hv);
}

axkit_dir_config *
new_axkit_dir_config (pool *p)
{
    axkit_dir_config *new =
        (axkit_dir_config *) ap_palloc(p, sizeof(axkit_dir_config));

    new->debug_tidy = -1;
    new->translate_output = -1;
    new->gzip_output = -1;
    new->log_declines = -1;
    new->stack_trace = -1;
    new->no_cache = -1;
    new->debug_level = -1;
    new->dependency_checks = -1;
    new->ignore_style_pi = -1;
    new->handle_dirs = -1;
    new->reset_processors = 0;
    new->reset_output_transformers = 0;
    new->reset_plugins = 0;

    new->cache_dir = 0;
    new->config_reader_module = 0;
    new->contentprovider_module = 0;
    new->styleprovider_module = 0;
    new->default_style = 0;
    new->default_media = 0;
    new->cache_module = 0;
    new->output_charset = 0;
    new->trace_intermediate = 0;

    /* complex types */
    new->type_map = NULL;
    new->processors = NULL;
    new->dynamic_processors = NULL;
    new->xsp_taglibs = NULL;
    new->current_styles = NULL;
    new->current_medias = NULL;
    new->error_stylesheet = NULL;
    new->output_transformers = NULL;
    new->current_plugins = NULL;

/*
    warn("[AxKit] created new dir_config:\n"
        "location: %d\n"
        "new.translate_output: %d\n"
        "new.gzip_output: %d\n"
        "new.log_declines: %d\n"
        "new.stack_trace: %d\n"
        "new.reset_processors: %d\n"
        "new.cache_dir: %d\n"
        "new.config_reader_module: %d\n"
        "new.contentprovider_module: %d\n"
        "new.styleprovider_module: %d\n"
        "new.default_style: %d\n"
        "new.default_media: %d\n"
        "new.cache_module: %d\n"
        "new.output_charset: %d\n"
        "new.debug_level: %d\n"
        "new.type_map: %d\n"
        "new.processors: %d\n"
        "new.dynamic_processors: %d\n"
        "new.xsp_taglibs: %d\n"
        "new.current_styles: %d\n"
        "new.current_medias: %d\n"
        "new.error_stylesheet: %d\n"
        "new.output_transformers: %d\n"
        ,
        new,
        new->translate_output,
        new->gzip_output,
        new->log_declines,
        new->stack_trace,
        new->reset_processors,
        new->cache_dir,
        new->config_reader_module,
        new->contentprovider_module,
        new->styleprovider_module,
        new->default_style,
        new->default_media,
        new->cache_module,
        new->output_charset,
        new->debug_level,
        new->type_map,
        new->processors,
        new->dynamic_processors,
        new->xsp_taglibs,
        new->current_styles,
        new->current_medias,
        new->error_stylesheet,
        new->output_transformers
        );
*/
    
    return new;
}

void *
create_axkit_dir_config (pool *p, char *dummy)
{
    axkit_dir_config *new = new_axkit_dir_config(p);
    
    new->type_map = newHV();
    hv_store(new->type_map, "application/x-xpathscript", 25,
            newSVpv("Apache::AxKit::Language::XPathScript", 0), 0);
    hv_store(new->type_map, "application/x-xsp", 17,
            newSVpv("Apache::AxKit::Language::XSP", 0), 0);
    ap_register_cleanup(p, (void*)new->type_map, ax_cleanup_hv, ap_null_cleanup);
    
    new->processors = newHV();
    ap_register_cleanup(p, (void*)new->processors, ax_cleanup_hv, ap_null_cleanup);

    new->dynamic_processors = newAV();
    ap_register_cleanup(p, (void*)new->dynamic_processors, ax_cleanup_av, ap_null_cleanup);
    
    new->xsp_taglibs = newHV();
    ap_register_cleanup(p, (void*)new->xsp_taglibs, ax_cleanup_hv, ap_null_cleanup);

    new->output_transformers = newAV();
    ap_register_cleanup(p, (void*)new->output_transformers, ax_cleanup_av, ap_null_cleanup);
    
    new->current_styles = newAV();
    av_push(new->current_styles, newSVpv("#default", 0));
    ap_register_cleanup(p, (void*)new->current_styles, ax_cleanup_av, ap_null_cleanup);

    new->current_medias = newAV();
    av_push(new->current_medias, newSVpv("screen", 0));
    ap_register_cleanup(p, (void*)new->current_medias, ax_cleanup_av, ap_null_cleanup);
    
    new->error_stylesheet = newAV();
    ap_register_cleanup(p, (void*)new->error_stylesheet, ax_cleanup_av, ap_null_cleanup);

    new->current_plugins = newAV();
    ap_register_cleanup(p, (void*)new->current_plugins, ax_cleanup_av, ap_null_cleanup);

    /* warn("create dir config: %d\n", new); */

    return new;
}

void
store_in_hv2 (HV * my_hv, SV * one, SV * two, SV * value)
{
    char * key1;
    char * key2;
    STRLEN len;
    HV * sub1;
    AV * sub2;
    
    key1 = SvPV(one, len);
    if (!hv_exists(my_hv, key1, len)) {
        sub1 = newHV();
        hv_store(my_hv, key1, len, newRV_noinc((SV*)sub1), 0);
    }
    else {
        SV ** sub1p = hv_fetch(my_hv, key1, len, 0);
        if (sub1p == NULL) {
            croak("shouldn't happen");
        }
        sub1 = (HV*)SvRV(*sub1p);
    }

    key2 = SvPV(two, len);
    if (!hv_exists(sub1, key2, len)) {
        sub2 = newAV();
        hv_store(sub1, key2, len, newRV_noinc((SV*)sub2), 0);
    }
    else {
        SV ** sub2p = hv_fetch(sub1, key2, len, 0);
        if (sub2p == NULL) {
            croak("shouldn't happen");
        }
        sub2 = (AV*)SvRV(*sub2p);
    }

    /* warn("adding processor in %s/%s with refs: %d\n", key1, key2, SvREFCNT(value)); */

    av_push(sub2, value);
}

static void *
merge_axkit_dir_config (pool *p, void *parent_dirv, void *subdirv)
{
    axkit_dir_config *parent_dir = (axkit_dir_config *)parent_dirv;
    axkit_dir_config *subdir = (axkit_dir_config *)subdirv;
    axkit_dir_config *new = new_axkit_dir_config(p);

    /* Brian Wheeler found that sometimes parent is NULL */
    if (parent_dir == NULL) {
        parent_dir = create_axkit_dir_config(p, "");
    }

    /* warn("merge : %d with %d\n", parent_dir, subdir); */

/*
    warn("[AxKit] merge: parent dir_config:\n"
        "location: %d\n"
        "parent_dir.translate_output: %d\n"
        "parent_dir.gzip_output: %d\n"
        "parent_dir.log_declines: %d\n"
        "parent_dir.stack_trace: %d\n"
        "parent_dir.reset_processors: %d\n"
        "parent_dir.cache_dir: %d\n"
        "parent_dir.config_reader_module: %d\n"
        "parent_dir.contentprovider_module: %d\n"
        "parent_dir.styleprovider_module: %d\n"
        "parent_dir.default_style: %d\n"
        "parent_dir.default_media: %d\n"
        "parent_dir.cache_module: %d\n"
        "parent_dir.output_charset: %d\n"
        "parent_dir.debug_level: %d\n"
        "parent_dir.type_map: %d\n"
        "parent_dir.processors: %d\n"
        "parent_dir.dynamic_processors: %d\n"
        "parent_dir.xsp_taglibs: %d\n"
        "parent_dir.current_styles: %d\n"
        "parent_dir.current_medias: %d\n"
        "parent_dir.error_stylesheet: %d\n"
        "parent_dir.output_transformers: %d\n"
        ,
        parent_dir,
        parent_dir->translate_output,
        parent_dir->gzip_output,
        parent_dir->log_declines,
        parent_dir->stack_trace,
        parent_dir->reset_processors,
        parent_dir->cache_dir,
        parent_dir->config_reader_module,
        parent_dir->contentprovider_module,
        parent_dir->styleprovider_module,
        parent_dir->default_style,
        parent_dir->default_media,
        parent_dir->cache_module,
        parent_dir->output_charset,
        parent_dir->debug_level,
        parent_dir->type_map,
        parent_dir->processors,
        parent_dir->dynamic_processors,
        parent_dir->xsp_taglibs,
        parent_dir->current_styles,
        parent_dir->current_medias,
        parent_dir->error_stylesheet,
        parent_dir->output_transformers
        );
    
    warn("[AxKit] created new dir_config:\n"
        "location: %d\n"
        "subdir.translate_output: %d\n"
        "subdir.gzip_output: %d\n"
        "subdir.log_declines: %d\n"
        "subdir.stack_trace: %d\n"
        "subdir.reset_processors: %d\n"
        "subdir.cache_dir: %d\n"
        "subdir.config_reader_module: %d\n"
        "subdir.contentprovider_module: %d\n"
        "subdir.styleprovider_module: %d\n"
        "subdir.default_style: %d\n"
        "subdir.default_media: %d\n"
        "subdir.cache_module: %d\n"
        "subdir.output_charset: %d\n"
        "subdir.debug_level: %d\n"
        "subdir.type_map: %d\n"
        "subdir.processors: %d\n"
        "subdir.dynamic_processors: %d\n"
        "subdir.xsp_taglibs: %d\n"
        "subdir.current_styles: %d\n"
        "subdir.current_medias: %d\n"
        "subdir.error_stylesheet: %d\n"
        "subdir.output_transformers: %d\n"
        ,
        subdir,
        subdir->translate_output,
        subdir->gzip_output,
        subdir->log_declines,
        subdir->stack_trace,
        subdir->reset_processors,
        subdir->cache_dir,
        subdir->config_reader_module,
        subdir->contentprovider_module,
        subdir->styleprovider_module,
        subdir->default_style,
        subdir->default_media,
        subdir->cache_module,
        subdir->output_charset,
        subdir->debug_level,
        subdir->type_map,
        subdir->processors,
        subdir->dynamic_processors,
        subdir->xsp_taglibs,
        subdir->current_styles,
        subdir->current_medias,
        subdir->error_stylesheet,
        subdir->output_transformers
        );
*/

    /* flat params */
    if (subdir->cache_dir) {
        new->cache_dir = ap_pstrdup(p, subdir->cache_dir);
    }
    else if (parent_dir->cache_dir) {
        new->cache_dir = ap_pstrdup(p, parent_dir->cache_dir);
    }

    if (subdir->config_reader_module) {
        new->config_reader_module = ap_pstrdup(p, subdir->config_reader_module);
    }
    else if (parent_dir->config_reader_module) {
        new->config_reader_module = ap_pstrdup(p, parent_dir->config_reader_module);
    }

    if (subdir->contentprovider_module) {
        new->contentprovider_module = ap_pstrdup(p, subdir->contentprovider_module);
    }
    else if (parent_dir->contentprovider_module) {
        new->contentprovider_module = ap_pstrdup(p, parent_dir->contentprovider_module);
    }

    if (subdir->styleprovider_module) {
        new->styleprovider_module = ap_pstrdup(p, subdir->styleprovider_module);
    }
    else if (parent_dir->styleprovider_module) {
        new->styleprovider_module = ap_pstrdup(p, parent_dir->styleprovider_module);
    }

    if (subdir->default_style) {
        new->default_style = ap_pstrdup(p, subdir->default_style);
    }
    else if (parent_dir->default_style) {
        new->default_style = ap_pstrdup(p, parent_dir->default_style);
    }

    if (subdir->default_media) {
        new->default_media = ap_pstrdup(p, subdir->default_media);
    }
    else if (parent_dir->default_media) {
        new->default_media = ap_pstrdup(p, parent_dir->default_media);
    }

    if (subdir->cache_module) {
        new->cache_module = ap_pstrdup(p, subdir->cache_module);
    }
    else if (parent_dir->cache_module) {
        new->cache_module = ap_pstrdup(p, parent_dir->cache_module);
    }
    
    if (subdir->output_charset) {
        new->output_charset = ap_pstrdup(p, subdir->output_charset);
    }
    else if (parent_dir->output_charset) {
        new->output_charset = ap_pstrdup(p, parent_dir->output_charset);
    }

    if (subdir->trace_intermediate) {
        new->trace_intermediate = ap_pstrdup(p, subdir->trace_intermediate);
    }
    else if (parent_dir->trace_intermediate) {
        new->trace_intermediate = ap_pstrdup(p, parent_dir->trace_intermediate);
    }

    new->debug_tidy =
        subdir->debug_tidy != -1 ? subdir->debug_tidy :
                                     parent_dir->debug_tidy;

    new->debug_level =
        subdir->debug_level != -1 ? subdir->debug_level :
                                    parent_dir->debug_level;

    new->translate_output =
        subdir->translate_output != -1 ? subdir->translate_output :
                                         parent_dir->translate_output;

    new->gzip_output =
        subdir->gzip_output != -1 ? subdir->gzip_output :
                                         parent_dir->gzip_output;

    new->stack_trace =
        subdir->stack_trace != -1 ? subdir->stack_trace :
                                         parent_dir->stack_trace;

    new->log_declines =
        subdir->log_declines != -1 ? subdir->log_declines :
                                     parent_dir->log_declines;

    new->no_cache =
        subdir->no_cache != -1 ? subdir->no_cache :
                                     parent_dir->no_cache;

    new->dependency_checks =
        subdir->dependency_checks != -1 ? subdir->dependency_checks :
                                     parent_dir->dependency_checks;

    new->ignore_style_pi =
        subdir->ignore_style_pi != -1 ? subdir->ignore_style_pi :
                                    parent_dir->ignore_style_pi;

    new->handle_dirs =
        subdir->handle_dirs != -1 ? subdir->handle_dirs :
                                    parent_dir->handle_dirs;

    /* complex types */

    {
        /* cfg->error_stylesheet */
        AV * from = NULL;
        new->error_stylesheet = newAV();
        
        if (av_len(subdir->error_stylesheet) >= 0) {
            from = subdir->error_stylesheet;
        }
        else if (av_len(parent_dir->error_stylesheet) >= 0) {
            from = parent_dir->error_stylesheet;
        }
        
        if (from) {
            char *mime;
            char *stylesheet;
            SV ** avitem;
            STRLEN len;

            avitem = av_fetch(from, 0, 0);
            mime = ap_pstrdup(p, SvPV(*avitem, len));
            av_push(new->error_stylesheet, newSVpvn(mime, strlen(mime)));
            
            avitem = av_fetch(from, 1, 0);
            stylesheet = ap_pstrdup(p, SvPV(*avitem, len));
            av_push(new->error_stylesheet, newSVpvn(stylesheet, strlen(stylesheet)));
        }

        ap_register_cleanup(p, (void*)new->error_stylesheet, ax_cleanup_av, ap_null_cleanup);
    }
    
    {
        /* cfg->type_map */
        char * key;
        I32 len;
        SV * val;
        
        new->type_map = newHV();
        
        hv_iterinit(parent_dir->type_map);
        while (val = hv_iternextsv(parent_dir->type_map, &key, &len)) {
            char * cval;
            STRLEN clen;
            cval = ap_pstrdup(p, SvPV(val, clen));
            hv_store(new->type_map, key, len, newSVpvn(cval, clen), 0);
        }
        
        hv_iterinit(subdir->type_map);
        while (val = hv_iternextsv(subdir->type_map, &key, &len)) {
            char * cval;
            STRLEN clen;
            cval = ap_pstrdup(p, SvPV(val, clen));
            hv_store(new->type_map, key, len, newSVpvn(cval, clen), 0);
        }

        ap_register_cleanup(p, (void*)new->type_map, ax_cleanup_hv, ap_null_cleanup);
    }

    {
        /* cfg->dynamic_processors */
        new->dynamic_processors = newAV();
        if (av_len(subdir->dynamic_processors) >= 0) {
            I32 key = 0;
            for(key = 0; key <= av_len(subdir->dynamic_processors); key++) {
                SV ** val = av_fetch(subdir->dynamic_processors, key, 0);
                if (val != NULL) {
                    char * cval;
                    STRLEN len;
                    cval = ap_pstrdup(p, SvPV(*val, len));
                    av_push(new->dynamic_processors, newSVpvn(cval, strlen(cval)));
                }
            }
        }
        else {
            I32 key = 0;
            for(key = 0; key <= av_len(parent_dir->dynamic_processors); key++) {
                SV ** val = av_fetch(parent_dir->dynamic_processors, key, 0);
                if (val != NULL) {
                    char * cval;
                    STRLEN len;
                    cval = ap_pstrdup(p, SvPV(*val, len));
                    av_push(new->dynamic_processors, newSVpvn(cval, strlen(cval)));
                }
            }
        }

        ap_register_cleanup(p, (void*)new->dynamic_processors, ax_cleanup_av, ap_null_cleanup);
    }

    {
        /* cfg->xsp_taglibs */
        new->xsp_taglibs = newHV();
        if (HvKEYS(parent_dir->xsp_taglibs)) {
            SV * val;
            char * key;
            I32 len;
            hv_iterinit(parent_dir->xsp_taglibs);
            while (val = hv_iternextsv(parent_dir->xsp_taglibs, &key, &len)) {
                hv_store(new->xsp_taglibs, key, len, newSViv(1), 0);
            }
        }
        if (HvKEYS(subdir->xsp_taglibs)) {
            SV * val;
            char * key;
            I32 len;
            hv_iterinit(subdir->xsp_taglibs);
            while (val = hv_iternextsv(subdir->xsp_taglibs, &key, &len)) {
                hv_store(new->xsp_taglibs, key, len, newSViv(1), 0);
            }
        }

        ap_register_cleanup(p, (void*)new->xsp_taglibs, ax_cleanup_hv, ap_null_cleanup);
    }

    {
        /* cfg->processors */
        SV * val;
        I32 len;
        char * key;

        new->processors = newHV();

        hv_iterinit(subdir->processors);
        while (val = hv_iternextsv(subdir->processors, &key, &len)) {
            SV * subval;
            I32 sublen;
            char * subkey;
            HV * subhash = (HV*)SvRV(val);
            
            hv_iterinit(subhash);
            while (subval = hv_iternextsv(subhash, &subkey, &sublen)) {
                SV * one;
                SV * two;
                AV * ary;
                I32 ary_len;
                I32 i;
                
                one = newSVpvn(ap_pstrdup(p, key), len);
                two = newSVpvn(ap_pstrdup(p, subkey), sublen);
                
                ary = (AV*)SvRV(subval);
                ary_len = av_len(ary);

                if (ary_len >= 0) {
                    for (i = 0; i <= ary_len; i++) {
                        SV ** elem = av_fetch(ary, i, 0);
                        if (elem) {
                            store_in_hv2(new->processors, one, two, newSVsv(*elem));
                        }
                    }
                }
                
                SvREFCNT_dec(one);
                SvREFCNT_dec(two);
            }
        }

        if (!subdir->reset_processors) {
            hv_iterinit(parent_dir->processors);
            while (val = hv_iternextsv(parent_dir->processors, &key, &len)) {
                SV * subval;
                I32 sublen;
                char * subkey;
                HV * subhash = (HV*)SvRV(val);

                hv_iterinit(subhash);
                while (subval = hv_iternextsv(subhash, &subkey, &sublen)) {
                    SV * one;
                    SV * two;
                    AV * ary;
                    I32 ary_len;
                    I32 i;

                    one = newSVpvn(ap_pstrdup(p, key), len);
                    two = newSVpvn(ap_pstrdup(p, subkey), sublen);

                    ary = (AV*)SvRV(subval);
                    ary_len = av_len(ary);

                    if (ary_len >= 0) {
                        for (i = 0; i <= ary_len; i++) {
                            SV ** elem = av_fetch(ary, i, 0);
                            if (elem) {
                                store_in_hv2(new->processors, one, two, newSVsv(*elem));
                            }
                        }
                    }
                    
                    SvREFCNT_dec(one);
                    SvREFCNT_dec(two);
                }
            }
        }

        ap_register_cleanup(p, (void*)new->processors, ax_cleanup_hv, ap_null_cleanup);
    }
    
    {
        /* cfg->output_transformers */
        new->output_transformers = newAV();
        
        if(!subdir->reset_output_transformers) {
            I32 key = 0;
            for(key = 0; key <= av_len(parent_dir->output_transformers); key++) {
                SV ** val = av_fetch(parent_dir->output_transformers, key, 0);
                if (val != NULL) {
                    char * cval;
                    STRLEN len;
                    cval = ap_pstrdup(p, SvPV(*val, len));
                    av_push(new->output_transformers, newSVpvn(cval, strlen(cval)));
                }
            }
        }
        if (av_len(subdir->output_transformers) >= 0) {
            I32 key = 0;
            for(key = 0; key <= av_len(subdir->output_transformers); key++) {
                SV ** val = av_fetch(subdir->output_transformers, key, 0);
                if (val != NULL) {
                    char * cval;
                    STRLEN len;
                    cval = ap_pstrdup(p, SvPV(*val, len));
                    av_push(new->output_transformers, newSVpvn(cval, strlen(cval)));
                }
            }
        }

        ap_register_cleanup(p, (void*)new->output_transformers, ax_cleanup_av, ap_null_cleanup);
    }

    {
        /* cfg->current_plugins */
        new->current_plugins = newAV();
        
        if(!subdir->reset_plugins) {
            I32 key = 0;
            for(key = 0; key <= av_len(parent_dir->current_plugins); key++) {
                SV ** val = av_fetch(parent_dir->current_plugins, key, 0);
                if (val != NULL) {
                    char * cval;
                    STRLEN len;
                    cval = ap_pstrdup(p, SvPV(*val, len));
                    av_push(new->current_plugins, newSVpvn(cval, strlen(cval)));
                }
            }
        }
        if (av_len(subdir->current_plugins) >= 0) {
            I32 key = 0;
            for(key = 0; key <= av_len(subdir->current_plugins); key++) {
                SV ** val = av_fetch(subdir->current_plugins, key, 0);
                if (val != NULL) {
                    char * cval;
                    STRLEN len;
                    cval = ap_pstrdup(p, SvPV(*val, len));
                    av_push(new->current_plugins, newSVpvn(cval, strlen(cval)));
                }
            }
        }

        ap_register_cleanup(p, (void*)new->current_plugins, ax_cleanup_av, ap_null_cleanup);
    }

    new->current_styles = newAV();
    av_push(new->current_styles, newSVpv("#default", 0));
    ap_register_cleanup(p, (void*)new->current_styles, ax_cleanup_av, ap_null_cleanup);

    new->current_medias = newAV();
    av_push(new->current_medias, newSVpv("screen", 0));
    ap_register_cleanup(p, (void*)new->current_medias, ax_cleanup_av, ap_null_cleanup);

/*
    warn("merge results: %d\n"
        "typemap: %d\n"
        "processors: %d\n"
        "dynamic: %d\n"
        "taglibs: %d\n"
        "c_styles: %d\n"
        "c_medias: %d\n"
        "out_trans: %d\n"
        ,
        new,
        new->type_map,
        new->processors,
        new->dynamic_processors,
        new->xsp_taglibs,
        new->current_styles,
        new->current_medias,
        new->output_transformers
        );
*/

    return new;
}

/* return string is an error. Return NULL if OK */

CHAR_P
ax_add_type_processor (cmd_parms *cmd, axkit_dir_config *ax,
                            char *mt, char *sty, char *option)
{
    AV *processor = newAV();

    SV **cur_media = av_fetch(ax->current_medias, 0, 0);
    SV **cur_style = av_fetch(ax->current_styles, 0, 0);

    SV *type = newSVpv((char*)cmd->info, 0);
    SV *mime = newSVpv(mt, 0);
    SV *style = newSVpv(sty, 0);
    SV *opt_sv = newSVpv(option, 0);

    av_push(processor, type);
    av_push(processor, mime);
    av_push(processor, style);
    av_push(processor, opt_sv);
    
    store_in_hv2(ax->processors, *cur_media, *cur_style, newRV_noinc((SV*)processor));
    
    return NULL;
}

CHAR_P
ax_add_processor (cmd_parms *cmd, axkit_dir_config *ax, char *mt, char *sty)
{
    return ax_add_type_processor(cmd, ax, mt, sty, "");
}

CHAR_P
ax_add_dynamic_processor (cmd_parms *cmd, axkit_dir_config *ax,
                            char *module)
{
    SV * mod_sv = newSVpv(module, 0);
    av_push(ax->dynamic_processors, mod_sv);
    
    return NULL;
}

CHAR_P
ax_reset_processors (cmd_parms *cmd, axkit_dir_config *ax)
{
    ax->reset_processors++;
    
    return NULL;
}

CHAR_P
ax_error_stylesheet (cmd_parms *cmd, axkit_dir_config *ax, char *mime, char *stylesheet)
{
    av_push(ax->error_stylesheet, newSVpvn(mime, strlen(mime)));
    av_push(ax->error_stylesheet, newSVpvn(stylesheet, strlen(stylesheet)));

    return NULL;
}

CHAR_P
ax_media_type (cmd_parms *cmd, axkit_dir_config *ax, char *media)
{
    const char *pos = media;
    char * nextword;
    int count = 0;
    char line [MAX_STRING_LEN];
    void * oldconf;
    
    char *endp = strrchr(media, '>');
    if (!endp) {
        return "Syntax error: no terminal \">\" sign";
    }
    *endp = '\0';
    
    while (*pos && (nextword = ap_getword_conf(cmd->pool, &pos))) {
        SV *media_sv = newSVpv(nextword, 0);
        if (count++ > 0) {
            return "Syntax error: <AxMediaType> only takes one parameter";
        }
        av_unshift(ax->current_medias, 1);
        av_store(ax->current_medias, 0, media_sv);
    }
    
    oldconf = ap_get_module_config(cmd->server->lookup_defaults, &XS_AxKit);
    ap_set_module_config(cmd->server->lookup_defaults, &XS_AxKit, (void*)ax);
    
    while (!ap_cfg_getline(line, MAX_STRING_LEN, cmd->config_file)) {
        const char *errmsg;
        if (!strcasecmp(line, "</AxMediaType>")) {
            SV * ignore = av_shift(ax->current_medias);
            SvREFCNT_dec(ignore);
            break;
        }
#ifndef WIN32
        errmsg = (const char *)ap_handle_command(cmd, cmd->server->lookup_defaults, line);
        if (errmsg) {
            return errmsg;
        }
#endif
    }
    
    ap_set_module_config(cmd->server->lookup_defaults, &XS_AxKit, oldconf);

    return NULL;
}

CHAR_P
ax_media_type_end (cmd_parms *cmd, axkit_dir_config *ax)
{
    return "</AxMediaType> with no beginning <AxMediaType> tag";
}

CHAR_P
ax_style_name (cmd_parms *cmd, axkit_dir_config *ax, char *style)
{
    const char *pos = style;
    char * nextword;
    int count = 0;
    char line [MAX_STRING_LEN];
    void * oldconf;
    
    char *endp = strrchr(style, '>');
    if (!endp) {
        return "Syntax error: no terminal \">\" sign";
    }
    *endp = '\0';
    
    while (*pos && (nextword = ap_getword_conf(cmd->pool, &pos))) {
        SV *style_sv = newSVpv(nextword, 0);
        if (count++ > 0) {
            return "Syntax error: <AxStyleName> only takes one parameter";
        }
        av_unshift(ax->current_styles, 1);
        av_store(ax->current_styles, 0, style_sv);
    }

    oldconf = ap_get_module_config(cmd->server->lookup_defaults, &XS_AxKit);
    ap_set_module_config(cmd->server->lookup_defaults, &XS_AxKit, (void*)ax);

    while (!ap_cfg_getline(line, MAX_STRING_LEN, cmd->config_file)) {
        const char *errmsg;
        if (!strcasecmp(line, "</AxStyleName>")) {
            SV * ignore = av_shift(ax->current_styles);
            SvREFCNT_dec(ignore);
            break;
        }
#ifndef WIN32
        errmsg = (const char *)ap_handle_command(cmd, cmd->server->lookup_defaults, line);
        if (errmsg) {
            return errmsg;
        }
#endif
    }
    
    ap_set_module_config(cmd->server->lookup_defaults, &XS_AxKit, oldconf);
    
    return NULL;
}

CHAR_P
ax_style_name_end (cmd_parms *cmd, axkit_dir_config *ax)
{
    return "</AxStyleName> with no beginning <AxStyleName> tag";
}

CHAR_P
ax_add_style_map (cmd_parms *cmd, axkit_dir_config *ax,
                    char *mt, char *module)
{
    SV *module_sv;
    STRLEN len;
    
    ax_preload_module(&module);
    
    len = strlen(mt);
    module_sv = newSVpv(module, 0);
        
    hv_store(ax->type_map, mt, len, module_sv, 0);
    
    return NULL;
}

CHAR_P
ax_reset_style_map (cmd_parms *cmd, axkit_dir_config *ax)
{
    hv_clear(ax->type_map);
    
    return NULL;
}

CHAR_P
ax_add_xsp_taglib (cmd_parms *cmd, axkit_dir_config *ax, char *module)
{
    STRLEN len;

    ax_preload_module(&module);

    len = strlen(module);

    hv_store(ax->xsp_taglibs, module, len, newSViv(1), 0);

    return NULL;
}

CHAR_P
ax_add_output_transformer (cmd_parms *cmd, axkit_dir_config *ax, char *module)
{
    SV * mod_sv = newSVpv(module, 0);
    av_push(ax->output_transformers, mod_sv);

    return NULL;
}

CHAR_P
ax_reset_output_transformers (cmd_parms *cmd, axkit_dir_config *ax)
{
    ax->reset_output_transformers++;
    return NULL;
}

CHAR_P
ax_add_plugin (cmd_parms *cmd, axkit_dir_config *ax, char *module)
{
    ax_preload_module(&module);
    av_push(ax->current_plugins, newSVpv(module, 0));
    return NULL;
}

CHAR_P
ax_set_provider (cmd_parms *cmd, axkit_dir_config *ax, char *provider)
{
    ax_preload_module(&provider);
    ax->contentprovider_module = provider;
    ax->styleprovider_module = provider;
    return NULL;
}

CHAR_P
ax_reset_plugins (cmd_parms *cmd, axkit_dir_config *ax)
{
    ax->reset_plugins++;
    return NULL;
}

static CHAR_P
ax_set_module_slot (cmd_parms *cmd, char *struct_ptr, char *arg)
{
    int offset;
    
    ax_preload_module(&arg);
    
    /* warn("ax_set_module_slot: %d\n", arg); */
    
    offset = (int) (long) cmd->info;
    *(char **) (struct_ptr + offset) = arg;
    return NULL;
}

static CHAR_P
ax_set_debug_level (cmd_parms *cmd, axkit_dir_config *ax, char *arg)
{
    ax->debug_level = atoi(arg);
    return NULL;
}

void axkit_module_init(server_rec *s, pool *p)
{
    STRLEN len = 0;
    SV * serverstring;
    char * serverstringc;
    serverstring = perl_get_sv("AxKit::ServerString", TRUE | GV_ADDMULTI);
    serverstringc = SvPV(serverstring, len);
    /* warn("Adding server string: %s\n", serverstringc); */
    ap_add_version_component(serverstringc);
}

static int axkit_handler(request_rec *r)
{
    int retval;
    SV * handler_sv;
    SV * cfg;
    SV * debuglevel;
    SV * errorlevel;
    
    if (S_ISDIR(r->finfo.st_mode)) {
        axkit_dir_config * cfg = (axkit_dir_config *)ap_get_module_config(r->per_dir_config, &XS_AxKit);
        if (!cfg || cfg->handle_dirs != 1) {
            return DECLINED;
        }
    }

    handler_sv = newSVpv("AxKit::fast_handler", 0);

    cfg = perl_get_sv("AxKit::Cfg", FALSE);
    debuglevel = perl_get_sv("AxKit::DebugLevel", FALSE);
    errorlevel = perl_get_sv("Error::Debug", FALSE);

    ENTER;

    save_item(cfg);
    save_item(debuglevel);
    save_item(errorlevel);

    retval = perl_call_handler(handler_sv, (request_rec *)r, Nullav);

    LEAVE;

    SvREFCNT_dec(handler_sv);

    if (retval == DECLINED) {
        r->handler = "default-handler";
        return ap_invoke_handler(r);
    }

    return retval;
}

static int axkit_ok_handler(request_rec *r)
{
    return OK;
}

static int axkit_declined_handler(request_rec *r)
{
    return DECLINED;
}

/************ server wide configuration *******************/

static axkit_server_config *
new_axkit_server_config (pool *p)
{
    axkit_server_config *new =
        (axkit_server_config *) ap_palloc(p, sizeof(axkit_server_config));

    new->external_encoding = 0;
    new->iconv_handle = 0;

    return new;
}

void *
create_axkit_server_config (pool *p, server_rec *s)
{
    axkit_server_config *new = new_axkit_server_config(p);

    return new;
}

static void *
merge_axkit_server_config (pool *p, void *parent_dirv, void *subdirv)
{
    axkit_server_config *parent_dir = (axkit_server_config *)parent_dirv;
    axkit_server_config *subdir = (axkit_server_config *)subdirv;
    axkit_server_config *new = new_axkit_server_config(p);

    if (subdir->external_encoding) {
        new->external_encoding = ap_pstrdup(p, subdir->external_encoding);
        if (strcmp(new->external_encoding,"UTF-8")) {
            new->iconv_handle = iconv_open(new->external_encoding,"UTF-8");
            ap_register_cleanup(p, (void*)new->iconv_handle, (void (*)(void *))iconv_close, ap_null_cleanup);
        }
    }
    else if (parent_dir && parent_dir->external_encoding) {
        new->external_encoding = ap_pstrdup(p, parent_dir->external_encoding);
        if (strcmp(new->external_encoding,"UTF-8")) {
            new->iconv_handle = iconv_open(new->external_encoding,"UTF-8");
            ap_register_cleanup(p, (void*)new->iconv_handle, (void (*)(void *))iconv_close, ap_null_cleanup);
        }
    }

    return new;
}

static CHAR_P
ax_set_external_encoding (cmd_parms *cmd, void *dummy, char *encoding)
{
    axkit_server_config *ax = (axkit_server_config *)
                ap_get_module_config(cmd->server->module_config, &XS_AxKit);
    /* warn("setting encoding %s",encoding); */
    ax->external_encoding = ap_pstrdup(cmd->pool, encoding);
    if (strcmp(ax->external_encoding,"UTF-8")) {
        ax->iconv_handle = iconv_open(ax->external_encoding,"UTF-8");
        ap_register_cleanup(cmd->pool, (void*)ax->iconv_handle, (void (*)(void *))iconv_close, ap_null_cleanup);
    }
    return NULL;
}

static int axkit_fixup_charsets(request_rec *r)
{
    char *local;
    int inbytes, outbytes;
    char *icursor, *ocursor;

    axkit_server_config * cfg;
    /* warn("fixup: '%s'",r->uri); */

    /* see comments above */
    if (!r || !r->server || !r->server->module_config)
        return DECLINED;

    cfg = (axkit_server_config *)ap_get_module_config(r->server->module_config, &XS_AxKit);

    if (!cfg || !cfg->iconv_handle)
        return DECLINED;

    /* can "UTF-8 -> anything" grow by more than a factor 4?
     * (UTF-8 -> UCS-4 could be factor 4, add some slack to be safe)
     */
    inbytes = strlen(r->uri);
    outbytes = inbytes*4+12;
    local = ap_pcalloc(r->pool, outbytes+1);

    /* reset state */
    iconv(cfg->iconv_handle,NULL,NULL,NULL,NULL);

    icursor = r->uri;
    ocursor = local;
    /* Try conversion */
    if (iconv(cfg->iconv_handle,&icursor,&inbytes,&ocursor,&outbytes) == (size_t)-1) {
        /* conversion failed - assume it was sent in target charset */
        /*warn("not UTF-8, leaving URL '%s' untouched", r->uri);*/
        return DECLINED;
    }

    /*warn("conversion successful: '%s'",local);*/
    r->uri = local;

    return DECLINED;
}

void axkit_child_init(server_rec *s, pool *p)
{
    /* create server_config objects in advance, otherwise apache might try to
    allocate one in a per-request pool, which is a remarkably dumb thing to do. */
    while (s) {
    	if (ap_get_module_config(s->module_config,&XS_AxKit) == NULL)
    		ap_set_module_config(s->module_config,&XS_AxKit,create_axkit_server_config(p,s));
    	s = s->next;
    }
}

static command_rec axkit_mod_cmds[] = {

    { "AxAddProcessor", ax_add_processor,
      (void*)"NORMAL", OR_ALL, TAKE2,
      "a mime type and a stylesheet to use" },

    { "AxAddDocTypeProcessor", ax_add_type_processor,
      (void*)"DocType", OR_ALL, TAKE3,
      "a mime type, a stylesheet, and an XML public identifier" },

    { "AxAddDTDProcessor", ax_add_type_processor,
      (void*)"DTD", OR_ALL, TAKE3,
      "a mime type, a stylesheet, and a dtd filename" },

    { "AxAddDynamicProcessor", ax_add_dynamic_processor,
      NULL, OR_ALL, TAKE1,
      "a package name" },

    { "AxAddRootProcessor", ax_add_type_processor,
      (void*)"Root", OR_ALL, TAKE3, 
      "a mime type, a stylesheet, and a root element" },

    { "AxAddURIProcessor", ax_add_type_processor,
      (void*)"URI", OR_ALL, TAKE3,
      "a mime type, a stylesheet, and a Perl regexp to match the URI" },

    { "AxResetProcessors", ax_reset_processors,
      NULL, OR_ALL, NO_ARGS,
      "reset the list of processors" },

    { "<AxMediaType", ax_media_type,
      NULL, OR_ALL, RAW_ARGS, 
      "Media type block" },

    { "</AxMediaType>", ax_media_type_end,
      NULL, OR_ALL, NO_ARGS,
      "End of media type block" },

    { "<AxStyleName", ax_style_name,
      NULL, OR_ALL, RAW_ARGS,
      "Style name block" },

    { "</AxStyleName>", ax_style_name_end,
      NULL, OR_ALL, NO_ARGS,
      "End of Style name block" },

    { "AxAddStyleMap", ax_add_style_map,
      NULL, OR_ALL, TAKE2,
      "a mime type and a module name to use" },

    { "AxResetStyleMap", ax_reset_style_map,
      NULL, OR_ALL, NO_ARGS,
      "reset the styles" },

    { "AxCacheDir", ap_set_string_slot,
      (void *)XtOffsetOf(axkit_dir_config, cache_dir),
      OR_ALL, TAKE1,
      "directory to store cache files" },

    { "AxConfigReader", ax_set_module_slot,
      (void *)XtOffsetOf(axkit_dir_config, config_reader_module),
      OR_ALL, TAKE1,
      "alternative module to use for reading configuration" },

    { "AxContentProvider", ax_set_module_slot,
      (void *)XtOffsetOf(axkit_dir_config, contentprovider_module),
      OR_ALL, TAKE1,
      "alternative module to use for reading the xml" },

    { "AxProvider", ax_set_provider,
      NULL, OR_ALL, TAKE1,
      "alternative module to use for reading the xml" },

    { "AxStyleProvider", ax_set_module_slot,
      (void *)XtOffsetOf(axkit_dir_config, styleprovider_module),
      OR_ALL, TAKE1,
      "alternative module to use for reading the stylesheet" },

    { "AxStyle", ap_set_string_slot,
      (void *)XtOffsetOf(axkit_dir_config, default_style),
      OR_ALL, TAKE1,
      "a default stylesheet (title) to use" },

    { "AxMedia", ap_set_string_slot,
      (void *)XtOffsetOf(axkit_dir_config, default_media),
      OR_ALL, TAKE1,
      "a default media to use other than screen" },

    { "AxAddOutputTransformer", ax_add_output_transformer,
      NULL, OR_ALL, TAKE1,
      "An output transformer function, qualified with package name." },

    { "AxResetOutputTransformers", ax_reset_output_transformers,
      NULL, OR_ALL, NO_ARGS,
      "Reset list of output transformers." },

    { "AxCacheModule", ax_set_module_slot,
      (void *)XtOffsetOf(axkit_dir_config, cache_module),
      OR_ALL, TAKE1,
      "alternative cache module" },

    { "AxDebugLevel", ax_set_debug_level,
      NULL, OR_ALL, TAKE1,
      "debug level (0 == none, higher numbers == more debugging)" },

    { "AxTranslateOutput", ap_set_flag_slot,
      (void *)XtOffsetOf(axkit_dir_config, translate_output),
      OR_ALL, FLAG,
      "On or Off [default] to automatically change character set on output" },

    { "AxOutputCharset", ap_set_string_slot,
      (void *)XtOffsetOf(axkit_dir_config, output_charset),
      OR_ALL, TAKE1,
      "character set used by iconv" },

    { "AxTraceIntermediate", ap_set_string_slot,
      (void *)XtOffsetOf(axkit_dir_config, trace_intermediate),
      OR_ALL, TAKE1,
      "location of a directory to write intermediate xml documents to (for debugging)" },

    { "AxDebugTidy", ap_set_flag_slot,
      (void *)XtOffsetOf(axkit_dir_config, debug_tidy),
      OR_ALL, FLAG,
      "On or Off [default] to tidy up source of debug output" },

    { "AxGzipOutput", ap_set_flag_slot,
      (void *)XtOffsetOf(axkit_dir_config, gzip_output),
      OR_ALL, FLAG,
      "On or Off [default] to gzip the output" },

    { "AxLogDeclines", ap_set_flag_slot,
      (void *)XtOffsetOf(axkit_dir_config, log_declines),
      OR_ALL, FLAG,
      "On or Off [default] to log why AxKit declined to process the resource" },

    { "AxStackTrace", ap_set_flag_slot,
      (void *)XtOffsetOf(axkit_dir_config, stack_trace),
      OR_ALL, FLAG,
      "On or Off [default] to maintain a stack trace with exceptions" },

    { "AxNoCache", ap_set_flag_slot,
      (void *)XtOffsetOf(axkit_dir_config, no_cache),
      OR_ALL, FLAG,
      "On or Off [default] to not cache results" },

    { "AxErrorStylesheet", ax_error_stylesheet,
      NULL, OR_ALL, TAKE2,
      "mime type and Error Stylesheet to use for displaying errors" },

    { "AxAddXSPTaglib", ax_add_xsp_taglib,
      NULL, OR_ALL, TAKE1,
      "module that provides a taglib functionality" },

    { "AxDependencyChecks", ap_set_flag_slot,
      (void *)XtOffsetOf(axkit_dir_config, dependency_checks),
      OR_ALL, FLAG,
    "On [default] or Off to disable dependency checking" },

    { "AxAddPlugin", ax_add_plugin,
        NULL, OR_ALL, TAKE1,
        "module that implements a plugin" },

    { "AxResetPlugins", ax_reset_plugins,
        NULL, OR_ALL, NO_ARGS,
        "reset the list of plugins" },

    { "AxHandleDirs", ap_set_flag_slot,
      (void *)XtOffsetOf(axkit_dir_config, handle_dirs),
      OR_ALL, FLAG,
      "On or Off [default] to make AxKit process directory requests using XML::Directory" },

    { "AxIgnoreStylePI", ap_set_flag_slot,
      (void *)XtOffsetOf(axkit_dir_config, ignore_style_pi),
      OR_ALL, FLAG,
      "On or Off [default] to disable xml-stylesheet PI processing" },

    { "AxExternalEncoding", ax_set_external_encoding,
      NULL,
      RSRC_CONF, TAKE1,
      "the character set used by the local file system and by URLs [default don't convert]" },

    { NULL }
};

static const handler_rec axkit_handlers[] =
{
    {"axkit", axkit_handler},
    { DIR_MAGIC_TYPE, axkit_handler },
    {NULL}
};

module MODULE_VAR_EXPORT XS_AxKit = {
    STANDARD_MODULE_STUFF,
    axkit_module_init,            /* module initializer */
    create_axkit_dir_config,      /* per-directory config creator */
    merge_axkit_dir_config,       /* dir config merger */
    create_axkit_server_config,   /* server config creator */
    merge_axkit_server_config,    /* server config merger */
    axkit_mod_cmds,               /* command table */
    axkit_handlers,               /* [7] list of handlers */
    axkit_fixup_charsets,         /* [2] filename-to-URI translation */
    NULL,                         /* [5] check/validate user_id */
    NULL,                         /* [6] check user_id is valid *here* */
    NULL,                         /* [4] check access by host address */
    NULL,                         /* [7] MIME type checker/setter */
    NULL,                         /* [8] fixups */
    NULL,                         /* [10] logger */
    NULL,                         /* [3] header parser */
    axkit_child_init,                         /* process initializer */
    NULL,                         /* process exit/cleanup */
    NULL,                         /* [1] post read_request handling */
};

HV *
ax_get_config (axkit_dir_config * cfg)
{
    HV * retval;

    retval = newHV();
    if (cfg->cache_dir) {
        hv_store(retval, "CacheDir",
                8, (newSVpv(cfg->cache_dir, 0)), 0);
    }
    if (cfg->config_reader_module) {
        hv_store(retval, "ConfigReader",
                12, (newSVpv(cfg->config_reader_module, 0)), 0);
    }
    if (cfg->contentprovider_module) {
        hv_store(retval, "ContentProvider",
                15, (newSVpv(cfg->contentprovider_module, 0)), 0);
    }
    if (cfg->styleprovider_module) {
        hv_store(retval, "StyleProvider",
                13, (newSVpv(cfg->styleprovider_module, 0)), 0);
    }
    if (cfg->default_style) {
        hv_store(retval, "Style",
                5, (newSVpv(cfg->default_style, 0)), 0);
    }
    if (cfg->default_media) {
        hv_store(retval, "Media",
                5, (newSVpv(cfg->default_media, 0)), 0);
    }
    if (cfg->cache_module) {
        hv_store(retval, "CacheModule",
                11, (newSVpv(cfg->cache_module, 0)), 0);
    }
    if (cfg->output_charset) {
        hv_store(retval, "OutputCharset",
                13, (newSVpv(cfg->output_charset, 0)), 0);
    }
    if (cfg->trace_intermediate) {
        hv_store(retval, "TraceIntermediate",
                17, (newSVpv(cfg->trace_intermediate, 0)), 0);
    }
    if (cfg->debug_tidy != -1) {
        hv_store(retval, "DebugTidy",
                9, (newSViv(cfg->debug_tidy)), 0);
    }
    if (cfg->debug_level) {
        hv_store(retval, "DebugLevel",
                10, (newSViv(cfg->debug_level)), 0);
    }
    if (cfg->translate_output != -1) {
        hv_store(retval, "TranslateOutput",
                15, (newSViv(cfg->translate_output)), 0);
    }
    if (cfg->gzip_output != -1) {
        hv_store(retval, "GzipOutput",
                10, (newSViv(cfg->gzip_output)), 0);
    }
    if (cfg->log_declines != -1) {
        hv_store(retval, "LogDeclines",
                11, (newSViv(cfg->log_declines)), 0);
    }
    if (cfg->stack_trace != -1) {
        hv_store(retval, "StackTrace",
                10, (newSViv(cfg->stack_trace)), 0);
    }
    if (cfg->no_cache != -1) {
        hv_store(retval, "NoCache",
                7, (newSViv(cfg->no_cache)), 0);
    }
    if (cfg->ignore_style_pi != -1) {
        hv_store(retval, "IgnoreStylePI",
                13, (newSViv(cfg->ignore_style_pi)), 0);
    }
    if (cfg->handle_dirs != -1) {
        hv_store(retval, "HandleDirs",
                10, (newSViv(cfg->handle_dirs)), 0);
    }

    if (cfg->dependency_checks != -1) {
        hv_store(retval, "DependencyChecks",
                16, (newSViv(cfg->dependency_checks)), 0);
    }
    else {
        hv_store(retval, "DependencyChecks",
                16, (newSViv(1)), 0);
    }

    hv_store(retval, "OutputTransformers",
            18, newRV_inc((SV*)cfg->output_transformers), 0);
    hv_store(retval, "ErrorStylesheet",
            15, newRV_inc((SV*)cfg->error_stylesheet), 0);
    hv_store(retval, "StyleMap",
            8, newRV_inc((SV*)cfg->type_map), 0);
    hv_store(retval, "Processors",
            10, newRV_inc((SV*)cfg->processors), 0);
    hv_store(retval, "DynamicProcessors",
            17, newRV_inc((SV*)cfg->dynamic_processors), 0);
    hv_store(retval, "XSPTaglibs",
            10, newRV_inc((SV*)cfg->xsp_taglibs), 0);
    hv_store(retval, "Plugins",
            7, newRV_inc((SV*)cfg->current_plugins), 0);

    return retval;
}

void
ax_get_server_config (axkit_server_config * cfg, HV *retval)
{
    /* see comments above */
    if (cfg->external_encoding) {
        hv_store(retval, "ExternalEncoding",
                16, (newSVpv(cfg->external_encoding, 0)), 0);
    }
}

void remove_module_cleanup(void * ignore)
{
    if (ap_find_linked_module(ap_find_module_name(&XS_AxKit))) {
        ap_remove_module(&XS_AxKit);
    }
    /* make sure BOOT section is re-run on restarts */
    (void)hv_delete(GvHV(incgv), "AxKit.pm", 8, G_DISCARD);
}


/* Diff for styles being relative to .htaccess:
Index: axconfig.c
===================================================================
RCS file: /home/cvs/AxKit/axconfig.c,v
retrieving revision 1.2
diff -r1.2 axconfig.c
2a3
> #define CORE_PRIVATE
3a5
> #include "axconfig.h"
6c8
< #include "axconfig.h"
---
> #include "include/http_core.h"
24a27,30
> char *
> ax_resolve_uri(char * base, char * uri)
> {
> }
626a633
>     SV *style;
634d640
<     SV *style = newSVpv(sty, 0);
636a643,665
>     core_server_config *server_conf = 
>         ap_get_module_config(cmd->server->module_config, &core_module);
>     
>     if (sty[0] != '/' 
>             && strcmp(sty, ".") != 0
>             && strstr(cmd->config_file->name, server_conf->access_name)) 
>     {
>         style = newSVpv(
>                     ap_pstrcat(cmd->pool, "file://",
>                         ap_make_full_path(cmd->pool,
>                             ap_make_dirstr_parent(
>                                         cmd->pool,
>                                         cmd->config_file->name
>                             ), sty
>                         ), NULL
>                     ), 0);
>     }
>     else {
>         style = newSVpv(sty, 0);
>     }
>
>     warn("style: %s\n", SvPV_nolen(style));
>     
674,675c703,725
<     av_push(ax->error_stylesheet, newSVpvn(mime, strlen(mime)));
<     av_push(ax->error_stylesheet, newSVpvn(stylesheet, strlen(stylesheet)));
---
>     core_server_config *server_conf = 
>         ap_get_module_config(cmd->server->module_config, &core_module);
>     
>     av_push(ax->error_stylesheet, newSVpvn(mime, 0));
>     
>     if (stylesheet[0] != '/' 
>                 && strstr(cmd->config_file->name, server_conf->access_name)) 
>     {
>         av_push(ax->error_stylesheet,
>                 newSVpv(
>                     ap_pstrcat(cmd->pool, "file://",
>                         ap_make_full_path(cmd->pool,
>                             ap_make_dirstr_parent(
>                                         cmd->pool,
>                                         cmd->config_file->name
>                             ), stylesheet
>                         ), NULL
>                     ), 0)
>                 );
>     }
>     else {
>         av_push(ax->error_stylesheet, newSVpv(stylesheet, 0));
>     }
*/

