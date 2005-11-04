<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">

<xsl:template match="root">
	<root><xsl:value-of select="document('axkit:./subrequest.xml')/root"/></root>
</xsl:template>

</xsl:stylesheet>

