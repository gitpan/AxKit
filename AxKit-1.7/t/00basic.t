use Test;
BEGIN { plan tests => 2 }
END { ok($loaded) }

use AxKit;
$loaded++;
ok(1);
