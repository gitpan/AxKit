/* $Id: CharsetConv.xs,v 1.4 2001/01/19 14:46:35 matt Exp $ */
/* XSUB for Perl module Apache::AxKit::CharsetConv  */
/* Originally from Text::Iconv distribution, */
/* all credits to Michael Piotrowski - this is a verbatim copy */
/* included in AxKit to reduce the number of required extra modules */

#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <iconv.h>
#ifdef __cplusplus
}
#endif


/*****************************************************************************/

static int raise_error = 0;

SV *do_conv(iconv_t iconv_handle, SV *string)
{
   char    *ibuf;         /* char* to the content of SV *string */
   char    *obuf;         /* temporary output buffer */
   size_t  inbytesleft;   /* no. of bytes left to convert; initially
			     this is the length of the input string,
			     and 0 when the conversion has finished */
   size_t  outbytesleft;  /* no. of bytes in the output buffer */
   size_t  l_obuf;        /* length of the output buffer */
   char *icursor;         /* current position in the input buffer */
   /* The Single UNIX Specification (version 1 and version 2), as well
      as the HP-UX documentation from which the XPG iconv specs are
      derived, are unclear about the type of the second argument to
      iconv() (here called icursor): The manpages say const char **,
      while the header files say char **. */
   char    *ocursor;      /* current position in the output buffer */
   size_t  ret;           /* iconv() return value */
   SV      *perl_str;     /* Perl return string */
   
   perl_str = newSVpv("", 0);

   /* Get length of input string. That's why we take an SV* instead of
      a char*: This way we can convert UCS-2 strings because we know
      their length. */

   inbytesleft = SvCUR(string);
   ibuf        = SvPV(string, inbytesleft);
   
   /* Calculate approximate amount of memory needed for the temporary
      output buffer and reserve the memory. The idea is to choose it
      large enough from the beginning to reduce the number of copy
      operations when converting from a single byte to a multibyte
      encoding. */
   
   if(inbytesleft <= MB_LEN_MAX)
   {
      outbytesleft = MB_LEN_MAX + 1;
   }
   else
   {
      outbytesleft = 2 * inbytesleft;
   }

   l_obuf = outbytesleft;
   obuf   = (char *) New(0, obuf, outbytesleft, char); /* Perl malloc */

   /**************************************************************************/

   icursor = ibuf;
   ocursor = obuf;

   /**************************************************************************/
   
   while(inbytesleft != 0)
   {
#ifdef ICONV_SECOND_PARAM_IS_CONST
      ret = iconv(iconv_handle, (const char**)&icursor, &inbytesleft,
		                &ocursor, &outbytesleft);
#else
      ret = iconv(iconv_handle, &icursor, &inbytesleft,
		                &ocursor, &outbytesleft);
#endif
      
      if(ret == (size_t) -1)
      {
	 switch(errno)
	 {
	    case EILSEQ:
	       /* Stop conversion if input character encountered which
		  does not belong to the input char set */
	       if (raise_error)
		  croak("Character not from source char set: %s",
			strerror(errno));
	       Safefree(obuf);   
	       return(&PL_sv_undef);
	    case EINVAL:
	       /* Stop conversion if we encounter an incomplete
                  character or shift sequence */
	       if (raise_error)
		  croak("Incomplete character or shift sequence: %s",
			strerror(errno));
	       Safefree(obuf);   
	       return(&PL_sv_undef);
	    case E2BIG:
	       /* If the output buffer is not large enough, copy the
                  converted bytes to the return string, reset the
                  output buffer and continue */
	       sv_catpvn(perl_str, obuf, l_obuf - outbytesleft);
	       ocursor = obuf;
	       outbytesleft = l_obuf;
	       break;
	    default:
	       if (raise_error)
		  croak("iconv error: %s", strerror(errno));
	       Safefree(obuf);   
	       return(&PL_sv_undef);
	 }
      }
   }

   /* Copy the converted bytes to the return string, and free the
      output buffer */
   
   sv_catpvn(perl_str, obuf, l_obuf - outbytesleft);
   Safefree(obuf); /* Perl malloc */

   return perl_str;
}

typedef iconv_t Apache__AxKit__CharsetConv;

/*****************************************************************************/
/* Perl interface                                                            */

MODULE = Apache::AxKit::CharsetConv	PACKAGE = Apache::AxKit::CharsetConv      PREFIX = iconv_t_

PROTOTYPES: DISABLE

int
raise_error(...)
   CODE:
      if (items > 0 && SvIOK(ST(0))) /* if called as function */
         raise_error = SvIV(ST(0));
      if (items > 1 && SvIOK(ST(1))) /* if called as class method */
         raise_error = SvIV(ST(1));
      RETVAL = raise_error;
   OUTPUT:
      RETVAL

Apache::AxKit::CharsetConv
new(self, fromcode, tocode)
   char *fromcode
   char *tocode
   CODE:
   if((RETVAL = iconv_open(tocode, fromcode)) == (iconv_t)-1)
   {
      switch(errno)
      {
	 case ENOMEM:
	    croak("Insufficient memory to initialize conversion: %s", 
		  strerror(errno));
	 case EINVAL:
	    croak("Unsupported conversion: %s", strerror(errno));
	 default:
	    croak("Couldn't initialize conversion: %s", strerror(errno));
      }
   }
   OUTPUT:
      RETVAL

SV*
convert(self, string)
   Apache::AxKit::CharsetConv self
   SV *string
   CODE:
      RETVAL = do_conv(self, string);
   OUTPUT:
      RETVAL

void
DESTROY(self)
   Apache::AxKit::CharsetConv self
   CODE:
      /* printf("Now in Apache::AxKit::CharsetConv::DESTROY\n"); */
      (void) iconv_close(self);
