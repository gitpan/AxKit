use Test;
BEGIN { plan tests => 9 }
use Apache::MimeXML;
ok(1);

my $encoding;

ok(Apache::MimeXML::check_for_xml_file("testnone.xml"), 'utf-8');

ok(Apache::MimeXML::check_for_xml_file("testebcdic.xml"), 'ebcdic-cp-fi');

ok(Apache::MimeXML::check_for_xml_file("testutf16be.xml"), 'utf-16-be');

ok(Apache::MimeXML::check_for_xml_file("testutf16le.xml"), 'utf-16-le');

ok(Apache::MimeXML::check_for_xml_file("testiso.xml"), 'ISO-8859-1');

ok(!Apache::MimeXML::check_for_xml_file("Makefile.PL"));

ok(Apache::MimeXML::check_for_xml_file("testzhbig50.xml"), 'BIG5');

ok(Apache::MimeXML::check_for_xml_file("testzhbig512.xml"), 'Big5');
