/* $Id: AxKit.xs,v 1.38 2001/06/05 09:28:45 matt Exp $ */

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
        return URI;
    }
}
#endif

#define BUFSIZE 1024

MODULE = AxKit		PACKAGE = AxKit

PROTOTYPES: DISABLE

BOOT:
    # warn("AxKit: BOOT\n");
    if (!ap_find_linked_module(ap_find_module_name(&XS_AxKit))) {
        # warn("AxKit: add_module()\n");
        ap_add_module(&XS_AxKit);
    }
    ap_register_cleanup(perl_get_startup_pool(), NULL,
            remove_module_cleanup, null_cleanup);

void
END ()
    CODE:
        # warn("AxKit: END\n");
        if (ap_find_linked_module(ap_find_module_name(&XS_AxKit))) {
            # warn("AxKit: remove_module()\n");
            ap_remove_module(&XS_AxKit);
        }


HV *
get_config (r)
        Apache  r
    PREINIT:
        axkit_dir_config * cfg;
    CODE:
        cfg = (axkit_dir_config *)
                ap_get_module_config(r->per_dir_config, &XS_AxKit);
        
        if (!cfg) {
            XSRETURN_UNDEF;
        }
        
        RETVAL = ax_get_config(cfg);
        sv_2mortal((SV*)RETVAL);
    OUTPUT:
        RETVAL

void
load_module (name)
        char * name
    CODE:
        # warn("load_module: %s\n", name);
        if(!perl_module_is_loaded(name)) {
            # warn("loading...\n");
            perl_require_module(name, NULL);
            # warn("done\n");
        }

char *
build_uri (r, uri, base)
        Apache r
        char * uri
        char * base
    CODE:
        RETVAL = axBuildURI(r->pool, uri, base);
    OUTPUT:
        RETVAL

#ifdef HAVE_LIBXML2

MODULE = AxKit		PACKAGE = Apache::AxKit::Provider

PROTOTYPES: DISABLE

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
        
        xmlInitParser();
        
        xmlDoValidityCheckingDefaultValue = 0;
        xmlSubstituteEntitiesDefaultValue = 0;
        xmlLoadExtDtdDefaultValue = 0;
        
        read_length = read_perl(ioref, buffer, 4);
        if (read_length > 0) {
            ctxt = xmlCreatePushParserCtxt(axkitSAXHandler, 
                        NULL, buffer, read_length, "filename");
            ctxt->userData = (void*)&results;
            
            while(read_length = read_perl(ioref, buffer, BUFSIZE)) {
                xmlParseChunk(ctxt, buffer, read_length, 0);
            }
            ret = xmlParseChunk(ctxt, buffer, 0, 1);
            
            xmlFreeParserCtxt(ctxt);
        }
        
        xmlCleanupParser();
        
        if (ret == -1) {
            croak("xmlParse couldn't read file!");
        }
        
        if (ret != XML_ERR_OK && ret != XML_ERR_UNDECLARED_ENTITY) {
            croak("xmlParse returned error: %d", ret);
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
        
        xmlInitParser();
        
        xmlDoValidityCheckingDefaultValue = 0;
        xmlSubstituteEntitiesDefaultValue = 0;
        xmlLoadExtDtdDefaultValue = 0;
        
        if (!ptr || len < 4) {
            XSRETURN_UNDEF;
        }
        
        ret = xmlSAXUserParseMemory(axkitSAXHandler, (void*)&results, ptr, len);
        
        xmlCleanupParser();
        
        if (ret != XML_ERR_OK && ret != XML_ERR_UNDECLARED_ENTITY) {
            croak("xmlParse returned error: %d", ret);
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

