/* $Id: AxKit.xs,v 1.7 2004/01/31 19:28:32 mach Exp $ */

#ifdef __cplusplus
extern "C" {
#endif
#ifdef WIN32
#define _INC_DIRENT
#define DIR void
#endif
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>
#include "axconfig.h"
#include "getstyles.h"
#ifdef __cplusplus
}
#endif

SV * error_str = NULL;

#ifdef HAVE_LIBXML2
char * axBuildURI(pool *p, const char *URI, const char *base)
{
    return ap_pstrdup(p, (char *)xmlBuildURI(URI, base));
}
#else
char * axBuildURI(pool *p, const char *URI, const char *base)
{
    if (URI[0] != '/') {
        return ap_pstrdup(p, ap_make_full_path(p, ap_make_dirstr_parent(p, base), URI));
    }
    else {
        return (char*)URI;
    }
}
#endif

pool *
get_startup_pool(void)
{
    SV *sv = perl_get_sv("Apache::__POOL", FALSE);
    if(sv) {
        IV tmp = SvIV((SV*)SvRV(sv));
        return (pool *)tmp;
    }
    return NULL;
}

int
call_method_int(SV * obj, char * method)
{
    dSP;
    int cnt;
    int results = -1;
    
    ENTER;
    SAVETMPS;
    
    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(obj);
    PUTBACK;
    
    cnt = perl_call_method(method, G_SCALAR);

    SPAGAIN;
    
    if (cnt != 1) {
        croak("read method call failed");
    }
    
    results = POPi;
    
    FREETMPS;
    LEAVE;
    
    return results;
}

SV *
call_method_sv(SV * obj, char * method)
{
    dSP;
    int cnt;
    STRLEN n_a;
    SV * results;
    ENTER;
    SAVETMPS;
    
    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(obj);
    PUTBACK;
    
    cnt = perl_call_method(method, G_SCALAR);
    
    SPAGAIN;
    
    if (cnt != 1) {
        croak("read method call failed");
    }
    
    results = NEWSV(0,0);
    sv_catsv(results, POPs);
    
    FREETMPS;
    LEAVE;
    
    /* SvREFCNT_inc(results); */
    
    return results;
}

#define BUFSIZE 1024

MODULE = AxKit		PACKAGE = AxKit

PROTOTYPES: DISABLE

BOOT:
    # warn("AxKit: BOOT\n");
    if (!ap_find_linked_module(ap_find_module_name(&XS_AxKit))) {
        # warn("AxKit: add_module()\n");
        ap_add_module(&XS_AxKit);
    }
    ap_register_cleanup(get_startup_pool(), NULL,
            remove_module_cleanup, null_cleanup);

void
END ()
    CODE:
        # warn("AxKit: END\n");
        if (ap_find_linked_module(ap_find_module_name(&XS_AxKit))) {
            # warn("AxKit: remove_module()\n");
            ap_remove_module(&XS_AxKit);
        }

void
load_module (name)
        char * name
    CODE:
        maybe_load_module(name);

void
reconsecrate (obj, class)
        SV * obj
        char * class
    CODE:
        maybe_load_module(class);
        sv_bless(obj, gv_stashpv(class, FALSE));

char *
build_uri (r, uri, base)
        Apache r
        char * uri
        char * base
    CODE:
        if (r == NULL) {
            croak("build_uri: Unexpected r == NULL");
        }
        RETVAL = axBuildURI(r->pool, uri, base);
    OUTPUT:
        RETVAL

void
Debug (level, ...)
        int level
    PREINIT:
        STRLEN n_a;
        request_rec * r;
        SV * str;
        int debuglevel;
        axkit_dir_config * cfg;
    PPCODE:
        r = perl_request_rec(NULL);
        if (r == NULL) {
            return;
        }
        cfg = (axkit_dir_config *)
                ap_get_module_config(r->per_dir_config, &XS_AxKit);
        if (!cfg) {
            /* AxKit is not handler in this directory */
            return;
        }
        if (level > cfg->debug_level) {
            return;
        }
        str = NEWSV(0, 256);
        sv_setpvn(str, "", 0);
        if (items > 1) {
            int i;
            char * last;
            for (i = 1; i < (items - 1); i++) {
                sv_catpv(str, SvPV(ST(i), n_a));
            }
            last = SvPV(ST(items - 1), n_a);
            if (last[strlen(last)] == '\n') {
                sv_catpvn(str, last, strlen(last) - 1);
            }
            else {
                sv_catpv(str, last);
            }
        }
        ap_log_rerror(APLOG_MARK, APLOG_NOERRNO|APLOG_WARNING, r, "[AxKit] %s", SvPV(str, n_a));
        SvREFCNT_dec(str);


MODULE = AxKit		PACKAGE = Apache::AxKit::ConfigReader

PROTOTYPES: DISABLE

SV *
_get_config (r=NULL)
        Apache  r
    CODE:
    {
        axkit_dir_config * cfg;
        axkit_server_config * scfg;
        HV * config;

        if (r == NULL) {
            croak("_get_config: Unexpected request_rec = NULL");
        }

        if (r->per_dir_config == NULL) {
            croak("_get_config: Unexpected per_dir_config = NULL");
        }

        cfg = (axkit_dir_config *)
                ap_get_module_config(r->per_dir_config, &XS_AxKit);

        if (!cfg) {
            config = newHV();
        }
        else {
            config = ax_get_config(cfg);
            if (!config) {
                config = newHV();
            }
        }

        if (r->server == NULL || r->server->module_config == NULL) {
            croak("_get_config: Unexpected r->server->module_config = NULL");
        }

        scfg = (axkit_server_config *)
                ap_get_module_config(r->server->module_config, &XS_AxKit);

        if (scfg) ax_get_server_config(scfg,config);

        RETVAL = newRV_noinc((SV*)config);
    }
    OUTPUT:
        RETVAL


#ifdef HAVE_LIBXML2

MODULE = AxKit		PACKAGE = Apache::AxKit::Provider

PROTOTYPES: DISABLE

SV *
_new(class, r, ...)
        char * class
        SV * r
    PREINIT:
        HV * hash;
        SV * alternate;
        STRLEN n_a;
        int item_id;
        SV * cfg;
        SV * key;
        int cnt;
        SV * obj;
        AV * item_store;
    CODE:
        hash = newHV();
        hv_store(hash, "apache", 6, r, 0);
        
        obj = newRV_noinc((SV*)hash);
        sv_bless(obj, gv_stashpv(class, 0));
        
        item_store = newAV();
        for (item_id = 2; item_id < items; item_id++) {
            av_push(item_store, ST(item_id));
        }
        
        if (alternate = call_method_sv(perl_get_sv("AxKit::Cfg", FALSE), "ContentProviderClass")) {
            SV * tmp;
            sv_bless(obj, gv_stashsv(alternate, 0));
            SvREFCNT_dec(alternate);
        }
        {
            dSP;
            ENTER;
            SAVETMPS;
            
            PUSHMARK(SP);
            EXTEND(SP, (items + 1));
            PUSHs(obj);
            for (item_id = 0; item_id <= av_len(item_store); item_id++) {
                PUSHs(*av_fetch(item_store, item_id, 0));
            }
            PUTBACK;
            
            cnt = perl_call_method("init", G_VOID);
            
            SPAGAIN;
            
            if (cnt != 0) {
                croak("init method call failed");
            }
            
            POPs;
            
            FREETMPS;
            LEAVE;
        }
        key = call_method_sv(obj, "key");
        {
            dSP;
            ENTER;
            SAVETMPS;
            
            PUSHMARK(SP);
            EXTEND(SP, 1);
            PUSHs(key);
            PUTBACK;
            
            cnt = perl_call_pv("AxKit::add_depends", G_VOID);
            
            SPAGAIN;
            
            if (cnt != 1) {
                croak("add_depends method call failed");
            }
            
            POPs;
            
            FREETMPS;
            LEAVE;
        }
        SvREFCNT_dec(key);
        SvREFCNT_dec(item_store);
        RETVAL = obj;
    OUTPUT:
        RETVAL

SV *
xs_get_styles_fh(r, ioref)
        Apache  r
        SV * ioref
    PREINIT:
        axkit_xml_bits results;
        xmlParserCtxtPtr ctxt;
        char buffer[BUFSIZE];
        int read_length;
        
        SV * tbuff;
        SV * tsize;
        int done = 0;
        int ret;
        AV * return_array;
    CODE:
        results.apache = r;
        results.xml_stylesheet = newAV();
        results.start_element = 0;
        results.start_attribs = 0;
        results.dtd = 0;
        results.publicid = 0;
        
        ret = -1;
        
        error_str = newSVpv("", 0);
        xmlInitParser();
        
        xmlDoValidityCheckingDefaultValue = 0;
        xmlSubstituteEntitiesDefaultValue = 0;
        xmlLoadExtDtdDefaultValue = 0;
        
		read_length = 0;
		ctxt = xmlCreatePushParserCtxt(axkitSAXHandler, 
					&results, buffer, read_length, "filename");
		
		while(read_length = read_perl(ioref, buffer, BUFSIZE)) {
			xmlParseChunk(ctxt, buffer, read_length, 0);
		}
		ret = xmlParseChunk(ctxt, buffer, 0, 1);
		
		xmlFreeParserCtxt(ctxt);
        
        sv_2mortal(error_str);
        
        xmlCleanupParser();
        
        if (ret == -1) {
            croak("xmlParse couldn't read file!");
        }
        
        if (ret != XML_ERR_OK && ret != XML_ERR_UNDECLARED_ENTITY) {
            STRLEN len;
            croak("xmlParse returned error: %d, %s", ret, SvPV(error_str, len));
        }
       
        return_array = newAV();
        av_push(return_array, newRV_noinc((SV*)results.xml_stylesheet));
        av_push(return_array, newSVpv(results.start_element, 0));
        av_push(return_array, newRV_noinc((SV*)results.start_attribs));
        
        
        if (results.dtd != NULL) {
            av_push(return_array, newSVpv(results.dtd, 0));
        }
        else {
            av_push(return_array, NEWSV(1,0));
        }
        
        if (results.publicid != NULL) {
            av_push(return_array, newSVpv(results.publicid, 0));
        }
        else {
            av_push(return_array, NEWSV(1,0));
        }
        
        RETVAL = newRV_noinc((SV*)return_array);
        
    OUTPUT:
        RETVAL

SV *
xs_get_styles_str(r, xmlstring)
        Apache  r
        SV * xmlstring
    PREINIT:
        axkit_xml_bits results;
        xmlParserCtxtPtr ctxt;
        int ret;
        STRLEN len;
        char * ptr;
        AV * return_array;
    CODE:
        results.apache = r;
        results.xml_stylesheet = newAV();
        results.start_element = 0;
        results.dtd = 0;
        results.publicid = 0;
        
        ptr = SvPV(xmlstring, len);
        
        error_str = newSVpv("", 0);
        
        xmlInitParser();
        
        xmlDoValidityCheckingDefaultValue = 0;
        xmlSubstituteEntitiesDefaultValue = 0;
        xmlLoadExtDtdDefaultValue = 0;
        
        if (!ptr || len < 4) {
            XSRETURN_UNDEF;
        }

        ret = xmlSAXUserParseMemory(axkitSAXHandler, (void*)&results, ptr, len);
        
        sv_2mortal(error_str);
        
        xmlCleanupParser();
        
        if (ret != XML_ERR_OK && ret != XML_ERR_UNDECLARED_ENTITY) {
            croak("xmlParse returned error: %d, %s", ret, SvPV(error_str, len));
        }
        
        return_array = newAV();
        av_push(return_array, newRV_noinc((SV*)results.xml_stylesheet));
        av_push(return_array, newSVpv(results.start_element, 0));
        av_push(return_array, newRV_noinc((SV*)results.start_attribs));
        
        if (results.dtd != NULL) {
            av_push(return_array, newSVpv(results.dtd, 0));
        }
        else {
            av_push(return_array, NEWSV(1,0));
        }
        
        if (results.publicid != NULL) {
            av_push(return_array, newSVpv(results.publicid, 0));
        }
        else {
            av_push(return_array, NEWSV(1,0));
        }
        
        RETVAL = newRV_noinc((SV*)return_array);
        
    OUTPUT:
        RETVAL

#endif /* HAVE_LIBXML2 */

