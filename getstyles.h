/* $Id: getstyles.h,v 1.1 2002/01/13 20:45:08 matts Exp $ */

#ifndef WIN32
#include <modules/perl/mod_perl.h>
#endif
#ifdef HAVE_LIBXML2
#include <libxml/xmlversion.h>
#include <libxml/xmlmemory.h>
#include <libxml/debugXML.h>
#include <libxml/HTMLtree.h>
#include <libxml/xmlerror.h>

#ifdef VMS
extern int xmlDoValidityCheckingDefaultVal;
#define xmlDoValidityCheckingDefaultValue xmlDoValidityCheckingDefaultVal
extern int xmlSubstituteEntitiesDefaultVal;
#define xmlSubstituteEntitiesDefaultValue xmlSubstituteEntitiesDefaultVal
#else
extern int xmlDoValidityCheckingDefaultValue;
extern int xmlSubstituteEntitiesDefaultValue;
#endif
extern int xmlGetWarningsDefaultValue;
extern int xmlKeepBlanksDefaultValue;
extern int xmlLoadExtDtdDefaultValue;
extern int xmlPedanticParserDefaultValue;

typedef struct {
    Apache apache;
    AV * xml_stylesheet;
    char * start_element;
    AV * start_attribs;
    char * dtd;
    char * publicid;
} axkit_xml_bits;

extern xmlSAXHandler axkitSAXHandlerStruct;

extern xmlSAXHandlerPtr axkitSAXHandler;

extern SV * error_str;

extern xmlEntityPtr blankEntity;

int read_perl (SV * ioref, char * buffer, int len);

#endif /* HAVE_LIBXML2 */

