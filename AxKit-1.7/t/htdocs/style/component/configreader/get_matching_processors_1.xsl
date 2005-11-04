<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">

<xsl:template match="root">
<match>get_matching_processors_1.xsl</match>
</xsl:template>

<xsl:template match="match">
  <bug>Template got applied twice</bug>
</xsl:template>

</xsl:stylesheet>

