/* $Id: axconfig.c,v 1.6 2001/06/05 09:28:45 matt Exp $ */

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

    if(!perl_module_is_loaded(*name)) {
        perl_require_module(*name, NULL);
    }
}
#endif


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
    
    new->translate_output = -1;
    new->gzip_output = -1;
    new->log_declines = -1;
    new->stack_trace = -1;
    new->no_cache = -1;
    new->reset_processors = 0;
    
    new->cache_dir = 0;
    new->config_reader_module = 0;
    new->provider_module = 0;
    new->styleprovider_module = 0;
    new->default_style = 0;
    new->default_media = 0;
    new->cache_module = 0;
    new->output_charset = 0;
    new->debug_level = 0;
    
    /* complex types */
    new->type_map = NULL;
    new->processors = NULL;
    new->dynamic_processors = NULL;
    new->xsp_taglibs = NULL;
    new->current_styles = NULL;
    new->current_medias = NULL;
    new->error_stylesheet = NULL;
    
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
        "new.provider_module: %d\n"
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
        ,
        new,
        new->translate_output,
        new->gzip_output,
        new->log_declines,
        new->stack_trace,
        new->reset_processors,
        new->cache_dir,
        new->config_reader_module,
        new->provider_module,
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
        new->error_stylesheet
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
    
    new->current_styles = newAV();
    av_push(new->current_styles, newSVpv("#default", 0));
    ap_register_cleanup(p, (void*)new->current_styles, ax_cleanup_av, ap_null_cleanup);
    
    new->current_medias = newAV();
    av_push(new->current_medias, newSVpv("screen", 0));
    ap_register_cleanup(p, (void*)new->current_medias, ax_cleanup_av, ap_null_cleanup);
    
    new->error_stylesheet = newAV();
    ap_register_cleanup(p, (void*)new->error_stylesheet, ax_cleanup_av, ap_null_cleanup);
    
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
        "parent_dir.provider_module: %d\n"
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
        ,
        parent_dir,
        parent_dir->translate_output,
        parent_dir->gzip_output,
        parent_dir->log_declines,
        parent_dir->stack_trace,
        parent_dir->reset_processors,
        parent_dir->cache_dir,
        parent_dir->config_reader_module,
        parent_dir->provider_module,
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
        parent_dir->error_stylesheet
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
        "subdir.provider_module: %d\n"
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
        ,
        subdir,
        subdir->translate_output,
        subdir->gzip_output,
        subdir->log_declines,
        subdir->stack_trace,
        subdir->reset_processors,
        subdir->cache_dir,
        subdir->config_reader_module,
        subdir->provider_module,
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
        subdir->error_stylesheet
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
    
    if (subdir->provider_module) {
        new->provider_module = ap_pstrdup(p, subdir->provider_module);
    }
    else if (parent_dir->provider_module) {
        new->provider_module = ap_pstrdup(p, parent_dir->provider_module);
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
    
    if (subdir->debug_level) {
        new->debug_level = ap_pstrdup(p, subdir->debug_level);
    }
    else if (parent_dir->debug_level) {
        new->debug_level = ap_pstrdup(p, parent_dir->debug_level);
    }
    
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
        if (HvKEYS(subdir->xsp_taglibs)) {
            SV * val;
            char * key;
            I32 len;
            hv_iterinit(subdir->xsp_taglibs);
            while (val = hv_iternextsv(subdir->xsp_taglibs, &key, &len)) {
                hv_store(new->xsp_taglibs, key, len, newSViv(1), 0);
            }
        }
        else {
            SV * val;
            char * key;
            I32 len;
            hv_iterinit(parent_dir->xsp_taglibs);
            while (val = hv_iternextsv(parent_dir->xsp_taglibs, &key, &len)) {
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
        
        ap_register_cleanup(p, (void*)new->processors, ax_cleanup_hv, ap_null_cleanup);
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
        "c_medias: %d\n",
        new,
        new->type_map,
        new->processors,
        new->dynamic_processors,
        new->xsp_taglibs,
        new->current_styles,
        new->current_medias);
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

CHAR_P
ax_axkit_onoff (cmd_parms *cmd, axkit_dir_config *ax, int flag)
{
    void * oldconf;
    const char * errmsg;
    SV *sva;
    SV *ignore;
    
    if (flag) {
#ifndef WIN32
        errmsg = (const char *)ap_handle_command(cmd, cmd->server->lookup_defaults, "SetHandler perl-script");
        if (errmsg) {
            return errmsg;
        }
#endif

        sva = newSVpv("AxKit", 0);
        ignore = newSVpv("ignore", 0);

        mod_perl_push_handlers(ignore, "PerlHandler", sva, Nullav);
        
        SvREFCNT_dec(sva);
        SvREFCNT_dec(ignore);
    }
    else {
#ifndef WIN32
        errmsg = (const char *)ap_handle_command(cmd, cmd->server->lookup_defaults, "SetHandler default-handler");
        if (errmsg) {
            return errmsg;
        }
#endif
    }
    
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

static command_rec axkit_mod_cmds[] = {
    { "AxKit", ax_axkit_onoff,
      NULL, OR_ALL, FLAG,
      "On or Off, turns AxKit processing On or Off" },
      
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

    { "AxProvider", ax_set_module_slot,
      (void *)XtOffsetOf(axkit_dir_config, provider_module),
      OR_ALL, TAKE1,
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

    { "AxCacheModule", ax_set_module_slot,
      (void *)XtOffsetOf(axkit_dir_config, cache_module),
      OR_ALL, TAKE1,
      "alternative cache module" },

    { "AxDebugLevel", ap_set_string_slot,
      (void *)XtOffsetOf(axkit_dir_config, debug_level),
      OR_ALL, TAKE1,
      "debug level (0 == none, higher numbers == more debugging)" },

    { "AxTranslateOutput", ap_set_flag_slot,
      (void *)XtOffsetOf(axkit_dir_config, translate_output),
      OR_ALL, FLAG,
      "On or Off [default] to automatically change character set on output" },

    { "AxOutputCharset", ap_set_string_slot,
      (void *)XtOffsetOf(axkit_dir_config, output_charset),
      OR_ALL, TAKE1,
      "character set used by iconv" },

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

    { NULL }
};

module MODULE_VAR_EXPORT XS_AxKit = {
    STANDARD_MODULE_STUFF,
    axkit_module_init,            /* module initializer */
    create_axkit_dir_config,      /* per-directory config creator */
    merge_axkit_dir_config,       /* dir config merger */
    NULL,                         /* server config creator */
    NULL,                         /* server config merger */
    axkit_mod_cmds,               /* command table */
    NULL,                         /* [7] list of handlers */
    NULL,                         /* [2] filename-to-URI translation */
    NULL,                         /* [5] check/validate user_id */
    NULL,                         /* [6] check user_id is valid *here* */
    NULL,                         /* [4] check access by host address */
    NULL,                         /* [7] MIME type checker/setter */
    NULL,                         /* [8] fixups */
    NULL,                         /* [10] logger */
    NULL,                         /* [3] header parser */
    NULL,                         /* process initializer */
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
    if (cfg->provider_module) {
        hv_store(retval, "Provider",
                8, (newSVpv(cfg->provider_module, 0)), 0);
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
    if (cfg->debug_level) {
        hv_store(retval, "DebugLevel",
                10, (newSVpv(cfg->debug_level, 0)), 0);
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
    
    return retval;
}

void remove_module_cleanup(void * ignore)
{
    if (ap_find_linked_module(ap_find_module_name(&XS_AxKit))) {
        ap_remove_module(&XS_AxKit);
    }
    /* make sure BOOT section is re-run on restarts */
    (void)hv_delete(GvHV(incgv), "AxKit.pm", 8, G_DISCARD);
    if (dowarn) {
        /* avoid subroutine redefined warnings */
        perl_clear_symtab(gv_stashpv("AxKit", FALSE));
    }
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

