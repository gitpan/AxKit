#include "modules/perl/mod_perl.h"

static mod_perl_perl_dir_config *newPerlConfig(pool *p)
{
    mod_perl_perl_dir_config *cld =
	(mod_perl_perl_dir_config *)
	    palloc(p, sizeof (mod_perl_perl_dir_config));
    cld->obj = Nullsv;
    cld->pclass = "AxKit";
    register_cleanup(p, cld, perl_perl_cmd_cleanup, null_cleanup);
    return cld;
}

static void *create_dir_config_sv (pool *p, char *dirname)
{
    return newPerlConfig(p);
}

static void *create_srv_config_sv (pool *p, server_rec *s)
{
    return newPerlConfig(p);
}

static void stash_mod_pointer (char *class, void *ptr)
{
    SV *sv = newSV(0);
    sv_setref_pv(sv, NULL, (void*)ptr);
    hv_store(perl_get_hv("Apache::XS_ModuleConfig",TRUE), 
	     class, strlen(class), sv, FALSE);
}

static mod_perl_cmd_info cmd_info_AxAddProcessor = { 
"AxKit::AxAddProcessor", "", 
};
static mod_perl_cmd_info cmd_info_AxAddDocTypeProcessor = { 
"AxKit::AxAddDocTypeProcessor", "", 
};
static mod_perl_cmd_info cmd_info_AxAddDTDProcessor = { 
"AxKit::AxAddDTDProcessor", "", 
};
static mod_perl_cmd_info cmd_info_AxAddDynamicProcessor = { 
"AxKit::AxAddDynamicProcessor", "", 
};
static mod_perl_cmd_info cmd_info_AxAddRootProcessor = { 
"AxKit::AxAddRootProcessor", "", 
};
static mod_perl_cmd_info cmd_info_AxResetProcessors = { 
"AxKit::AxResetProcessors", "", 
};
static mod_perl_cmd_info cmd_info_AxMediaType = { 
"AxKit::AxMediaType", "", 
};
static mod_perl_cmd_info cmd_info_AxMediaType_END = { 
"AxKit::AxMediaType_END", "", 
};
static mod_perl_cmd_info cmd_info_AxStyleName = { 
"AxKit::AxStyleName", "", 
};
static mod_perl_cmd_info cmd_info_AxStyleName_END = { 
"AxKit::AxStyleName_END", "", 
};
static mod_perl_cmd_info cmd_info_AxAddStyleMap = { 
"AxKit::AxAddStyleMap", "", 
};
static mod_perl_cmd_info cmd_info_AxResetStyleMap = { 
"AxKit::AxResetStyleMap", "", 
};
static mod_perl_cmd_info cmd_info_AxCacheDir = { 
"AxKit::AxCacheDir", "", 
};
static mod_perl_cmd_info cmd_info_AxConfigReader = { 
"AxKit::AxConfigReader", "", 
};
static mod_perl_cmd_info cmd_info_AxProvider = { 
"AxKit::AxProvider", "", 
};
static mod_perl_cmd_info cmd_info_AxStyle = { 
"AxKit::AxStyle", "", 
};
static mod_perl_cmd_info cmd_info_AxMedia = { 
"AxKit::AxMedia", "", 
};
static mod_perl_cmd_info cmd_info_AxCacheModule = { 
"AxKit::AxCacheModule", "", 
};
static mod_perl_cmd_info cmd_info_AxDebugLevel = { 
"AxKit::AxDebugLevel", "", 
};
static mod_perl_cmd_info cmd_info_AxTranslateOutput = { 
"AxKit::AxTranslateOutput", "", 
};
static mod_perl_cmd_info cmd_info_AxOutputCharset = { 
"AxKit::AxOutputCharset", "", 
};
static mod_perl_cmd_info cmd_info_AxGzipOutput = { 
"AxKit::AxGzipOutput", "", 
};
static mod_perl_cmd_info cmd_info_AxErrorStylesheet = { 
"AxKit::AxErrorStylesheet", "", 
};
static mod_perl_cmd_info cmd_info_AxAddXSPTaglib = { 
"AxKit::AxAddXSPTaglib", "", 
};


static command_rec mod_cmds[] = {
    
    { "AxAddProcessor", perl_cmd_perl_TAKE2,
      (void*)&cmd_info_AxAddProcessor,
      OR_ALL, TAKE2, "a mime type and a stylesheet to use" },

    { "AxAddDocTypeProcessor", perl_cmd_perl_TAKE3,
      (void*)&cmd_info_AxAddDocTypeProcessor,
      OR_ALL, TAKE3, "a mime type, a stylesheet, and an XML public identifier" },

    { "AxAddDTDProcessor", perl_cmd_perl_TAKE3,
      (void*)&cmd_info_AxAddDTDProcessor,
      OR_ALL, TAKE3, "a mime type, a stylesheet, and a dtd filename" },

    { "AxAddDynamicProcessor", perl_cmd_perl_TAKE1,
      (void*)&cmd_info_AxAddDynamicProcessor,
      OR_ALL, TAKE1, "a package name" },

    { "AxAddRootProcessor", perl_cmd_perl_TAKE3,
      (void*)&cmd_info_AxAddRootProcessor,
      OR_ALL, TAKE3, "a mime type, a stylesheet, and a root element" },

    { "AxResetProcessors", perl_cmd_perl_NO_ARGS,
      (void*)&cmd_info_AxResetProcessors,
      OR_ALL, NO_ARGS, "reset the list of processors" },

    { "<AxMediaType", perl_cmd_perl_RAW_ARGS,
      (void*)&cmd_info_AxMediaType,
      OR_ALL, RAW_ARGS, "Media type block" },

    { "</AxMediaType>", perl_cmd_perl_NO_ARGS,
      (void*)&cmd_info_AxMediaType_END,
      OR_ALL, NO_ARGS, "End of media type block" },

    { "<AxStyleName", perl_cmd_perl_RAW_ARGS,
      (void*)&cmd_info_AxStyleName,
      OR_ALL, RAW_ARGS, "Style name block" },

    { "</AxStyleName>", perl_cmd_perl_NO_ARGS,
      (void*)&cmd_info_AxStyleName_END,
      OR_ALL, NO_ARGS, "End of Style name block" },

    { "AxAddStyleMap", perl_cmd_perl_TAKE2,
      (void*)&cmd_info_AxAddStyleMap,
      OR_ALL, TAKE2, "a mime type and a module name to use" },

    { "AxResetStyleMap", perl_cmd_perl_NO_ARGS,
      (void*)&cmd_info_AxResetStyleMap,
      OR_ALL, NO_ARGS, "reset the styles" },

    { "AxCacheDir", perl_cmd_perl_TAKE1,
      (void*)&cmd_info_AxCacheDir,
      OR_ALL, TAKE1, "directory to store cache files" },

    { "AxConfigReader", perl_cmd_perl_TAKE1,
      (void*)&cmd_info_AxConfigReader,
      OR_ALL, TAKE1, "alternative module to use for reading configuration" },

    { "AxProvider", perl_cmd_perl_TAKE1,
      (void*)&cmd_info_AxProvider,
      OR_ALL, TAKE1, "alternative module to use for reading the xml" },

    { "AxStyle", perl_cmd_perl_TAKE1,
      (void*)&cmd_info_AxStyle,
      OR_ALL, TAKE1, "a default stylesheet (title) to use" },

    { "AxMedia", perl_cmd_perl_TAKE1,
      (void*)&cmd_info_AxMedia,
      OR_ALL, TAKE1, "a default media to use other than screen" },

    { "AxCacheModule", perl_cmd_perl_TAKE1,
      (void*)&cmd_info_AxCacheModule,
      OR_ALL, TAKE1, "alternative cache module" },

    { "AxDebugLevel", perl_cmd_perl_TAKE1,
      (void*)&cmd_info_AxDebugLevel,
      OR_ALL, TAKE1, "debug level (0 == none, higher numbers == more debugging)" },

    { "AxTranslateOutput", perl_cmd_perl_FLAG,
      (void*)&cmd_info_AxTranslateOutput,
      OR_ALL, FLAG, "On or Off [default] to automatically change character set on output" },

    { "AxOutputCharset", perl_cmd_perl_TAKE1,
      (void*)&cmd_info_AxOutputCharset,
      OR_ALL, TAKE1, "character set used by iconv" },

    { "AxGzipOutput", perl_cmd_perl_FLAG,
      (void*)&cmd_info_AxGzipOutput,
      OR_ALL, FLAG, "On or Off [default] to gzip the output" },

    { "AxErrorStylesheet", perl_cmd_perl_TAKE2,
      (void*)&cmd_info_AxErrorStylesheet,
      OR_ALL, TAKE2, "Error Stylesheet and a content-type for the StyleMap to use" },

    { "AxAddXSPTaglib", perl_cmd_perl_TAKE1,
      (void*)&cmd_info_AxAddXSPTaglib,
      OR_ALL, TAKE1, "module that provides a taglib functionality" },

    { NULL }
};

module MODULE_VAR_EXPORT XS_AxKit = {
    STANDARD_MODULE_STUFF,
    NULL,               /* module initializer */
    create_dir_config_sv,  /* per-directory config creator */
    perl_perl_merge_dir_config,   /* dir config merger */
    create_srv_config_sv,       /* server config creator */
    NULL,        /* server config merger */
    mod_cmds,               /* command table */
    NULL,           /* [7] list of handlers */
    NULL,  /* [2] filename-to-URI translation */
    NULL,      /* [5] check/validate user_id */
    NULL,       /* [6] check user_id is valid *here* */
    NULL,     /* [4] check access by host address */
    NULL,       /* [7] MIME type checker/setter */
    NULL,        /* [8] fixups */
    NULL,             /* [10] logger */
    NULL,      /* [3] header parser */
    NULL,         /* process initializer */
    NULL,         /* process exit/cleanup */
    NULL,   /* [1] post read_request handling */
};

#define this_module "AxKit.pm"

static void remove_module_cleanup(void *data)
{
    if (find_linked_module("AxKit")) {
       /* need to remove the module so module index is reset */
       remove_module(&XS_AxKit);
    }
    if (data) {
        /* make sure BOOT section is re-run on restarts */
        (void)hv_delete(GvHV(incgv), this_module,
                        strlen(this_module), G_DISCARD);
         if (dowarn) {
             /* avoid subroutine redefined warnings */
             perl_clear_symtab(gv_stashpv("AxKit", FALSE));
         }
    }
}

MODULE = AxKit		PACKAGE = AxKit

PROTOTYPES: DISABLE

BOOT:
    XS_AxKit.name = "AxKit";
    add_module(&XS_AxKit);
    stash_mod_pointer("AxKit", &XS_AxKit);
    register_cleanup(perl_get_startup_pool(), (void *)1,
                     null_cleanup, remove_module_cleanup);

void
END()

    CODE:
    remove_module_cleanup(NULL);
