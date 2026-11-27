"""Set the callback of a freshly initialized, disposable local Supabase only."""

from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
source = path.read_text()
updated, count = re.subn(
    r'^additional_redirect_urls\s*=\s*\[[^\n]*\]\s*$',
    'additional_redirect_urls = ["com.ganaderov.mobile.d4test://auth/callback"]',
    source,
    count=1,
    flags=re.MULTILINE,
)
if count != 1:
    raise SystemExit("Expected the generated local auth redirect setting; no file was changed.")
path.write_text(updated)
