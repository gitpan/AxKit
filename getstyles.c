/* $Id: getstyles.c,v 1.8 2001/05/27 20:05:50 matt Exp $ */

#ifdef HAVE_LIBXML2
#include "getstyles.h"

static void doctypeHandler(void *ctx,
        const xmlChar *name,
        const xmlChar *ExternalID, 
        const xmlChar *SystemID)
{
    axkit_xml_bits * xml_bits = (axkit_xml_bits*)ctx;
    
    /* warn("doctypeHandler: %s\n", name); */
    
    if (xml_bits->start_element != NULL) {
        return;
    }
    
    xml_bits->dtd = ap_pstrdup(xml_bits->apache->pool, ExternalID);
    xml_bits->publicid = ap_pstrdup(xml_bits->apache->pool, SystemID);
}

static void startElementHandler(void *ctx, 
        const xmlChar *name, 
        const xmlChar **atts)
{
    axkit_xml_bits * xml_bits;
    Apache r;
    int i = 0;
    
    xml_bits = (axkit_xml_bits*)ctx;
    
    /* warn("startElement: %s\n", name); */
    
    if (xml_bits->start_element != NULL) {
        return;
    }
    
    r = xml_bits->apache;
    
    xml_bits->start_element = ap_pstrdup(r->pool, name);
    
    xml_bits->start_attribs = newAV();
    
    if (atts != NULL) {
        for (i = 0;(atts[i] != NULL);i++) {
            av_push(xml_bits->start_attribs, newSVpv(ap_pstrdup(r->pool, atts[i]), 0));
	}
    }
}

static void processingInstructionHandler(
        void *ctx,
        const xmlChar *target,
        const xmlChar *data)
{
    axkit_xml_bits * xml_bits = (axkit_xml_bits*)ctx;
    
    if (xml_bits->start_element != NULL) {
        return;
    }
    
    if (strncmp(target, "xml-stylesheet", 14) == 0) {
        av_push(xml_bits->xml_stylesheet, 
                newSVpv(ap_pstrdup(xml_bits->apache->pool, data), 0));
    }
}

static void errorHandler(
        void *ctx,
        const char *msg,
        ...)
{
    va_list args;
    char buffer[50000];
    
    buffer[0] = 0;
    
    va_start(args, msg);
    vsprintf(&buffer[strlen(buffer)], msg, args);
    va_end(args);
    
    warn(buffer);
}

static xmlEntityPtr getEntity(void *user_data, const xmlChar *name) {
    xmlEntityPtr predef = xmlGetPredefinedEntity(name);
    
    if (predef != NULL) {
        /* warn("default entity: %s\n", name); */
        return predef;
    }
    
    /* warn("non-default entity: %s\n", name); */
    return blankEntity;
}

int
read_perl (SV * ioref, char * buffer, int len)
{
    dSP;
    
    int cnt;
    SV * read_results;
    STRLEN read_length;
    char * chars;
    SV * tbuff = NEWSV(0,0);
    SV * tsize = newSViv(len);
    
    ENTER;
    SAVETMPS;
    
    PUSHMARK(SP);
    EXTEND(SP, 3);
    PUSHs(ioref);
    PUSHs(tbuff);
    PUSHs(tsize);
    PUTBACK;
    
    cnt = perl_call_method("read", G_SCALAR);
    
    SPAGAIN;
    
    if (cnt != 1) {
        croak("read method call failed");
    }
    
    read_results = POPs;
    
    if (!SvOK(read_results)) {
        croak("read error");
    }
    
    read_length = SvIV(read_results);
    
    chars = SvPV(tbuff, read_length);
    strncpy(buffer, chars, read_length);
    
    FREETMPS;
    LEAVE;
    
    return read_length;
}

xmlSAXHandler axkitSAXHandlerStruct = {
    doctypeHandler,
    NULL,
    NULL,
    NULL,
    NULL,
    getEntity,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    startElementHandler,
    NULL,
    NULL,
    NULL,
    NULL,
    processingInstructionHandler,
    NULL,
    NULL,
    NULL,
    errorHandler,
    getEntity,
    NULL,
    doctypeHandler
};

xmlSAXHandlerPtr axkitSAXHandler = &axkitSAXHandlerStruct;

xmlEntity blankEntityStruct = {
#ifndef XML_WITHOUT_CORBA
    NULL,	        /* for Corba, must be first ! */
#endif
    XML_ENTITY_DECL,       /* XML_ENTITY_DECL, must be second ! */
    NULL,	/* Attribute name */
    NULL,	/* NULL */
    NULL,	/* NULL */
    NULL,	/* -> DTD */
    NULL,	/* next sibling link  */
    NULL,	/* previous sibling link  */
    NULL,       /* the containing document */

    NULL,	/* content without ref substitution */
    NULL,	/* content or ndata if unparsed */
    0,	/* the content length */
    XML_EXTERNAL_GENERAL_PARSED_ENTITY,	/* The entity type */
    NULL,	/* External identifier for PUBLIC */
    NULL,	/* URI for a SYSTEM or PUBLIC Entity */

    NULL,	/* unused */
    NULL	/* the full URI as computed */
};

xmlEntityPtr blankEntity = &blankEntityStruct;

#endif /* HAVE_LIBXML2 */
