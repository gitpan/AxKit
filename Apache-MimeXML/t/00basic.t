use Test;
BEGIN { plan tests => 2 }
END { ok($loaded) }
use Apache::MimeXML;
$loaded = 1;
ok(1);
