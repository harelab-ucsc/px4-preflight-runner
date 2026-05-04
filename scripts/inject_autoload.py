#!/usr/bin/env python3
"""
Inject a flight.ulg auto-load snippet into Hawkeye's upstream index.html.

Usage: inject_autoload.py <path-to-index.html>

Inserts a <script> block before </body> that polls window._hawkeye (set by
the upstream harness after hawkeye_init succeeds), fetches flight.ulg, and
calls hawkeye_load_ulog_bytes. Safe to call on any HTML file; no-ops if
</body> is absent.
"""
import sys

SNIPPET = """\
<script>
/* preflight: auto-load flight.ulg once Hawkeye is ready */
(function () {
    function tryLoad() {
        if (!window._hawkeye) { setTimeout(tryLoad, 50); return; }
        var h = window._hawkeye;
        fetch('flight.ulg')
            .then(function (r) {
                if (!r.ok) throw new Error('HTTP ' + r.status);
                return r.arrayBuffer();
            })
            .then(function (ab) {
                var buf = new Uint8Array(ab);
                var ptr = h.heapSet(buf);
                var load = h.instance.cwrap('hawkeye_load_ulog_bytes',
                    'number', ['number', 'number']);
                var rc = load(ptr, buf.length);
                h.instance._free(ptr);
                if (rc !== 0)
                    console.error('[preflight] load_ulog failed:', rc);
            })
            .catch(function (e) {
                console.info('[preflight] no flight.ulg to auto-load:', e.message);
            });
    }
    tryLoad();
})();
</script>"""

path = sys.argv[1]
html = open(path).read()
html = html.replace('</body>', SNIPPET + '\n</body>', 1)
open(path, 'w').write(html)
