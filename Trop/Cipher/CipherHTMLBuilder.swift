//
//  CipherHTMLBuilder.swift
//  Trop
//
//  Created by 686udjie on 29/06/2026.
//

import Foundation

enum CipherHTMLBuilder {

    /// Patches player.js to expose cipher functions on `window`,
    /// then returns the modified source so it can be saved to a local file.
    static func patchPlayerJs(
        playerJs: String,
        sigConfig: String?,
        nClass: String?,
        playerHash: String?
    ) -> String {
        var exports: [String] = []

        if let config = sigConfig {
            let sigExpr = config
                .replacingOccurrences(of: "INPUT", with: "sig")
            exports.append(
                "window._cipherSigFunc=function(sig){try{return \(sigExpr)}catch(e){return null}}"
            )
        }

        // URL builder that mimics YouTube's `s2` function:
        //   new g.lq(url,true) → set("alr","yes") → fJ(24,1210,sig) → set(sp, sig) → toString()
        let urlBuilder = "window._buildSignedUrl=function(url,sp,sig){try{" +
            "var u=new g.lq(url,true);u.set(\"alr\",\"yes\");" +
            "if(sig){var d;try{d=decodeURIComponent(sig)}catch(e){d=sig};" +
            "u.set(sp,fJ(24,1210,d))}return u.yq()}catch(e){return null}}"
        exports.append(urlBuilder)

        // n-normalization (YouTube's gN$ syncs /n/ path with ?n= param)
        // The actual n-value is NOT transformed in this player version.
        exports.append("""
        window._normalizeUrl=function(url){try{if(typeof gN$==='function')return gN$(url)}catch(e){}return url}
        """)

        // Expose _yt_player and fJ on window for discovery
        exports.append("window._exportedCipher={sigFuncName:'fJ',nFuncClass:'\(nClass ?? "?")'}")

        let marker = "})(_yt_player);"
        let exportCode = exports.isEmpty ? "" : "; " + exports.joined(separator: "; ")

        if playerJs.contains(marker) {
            return playerJs.replacingOccurrences(
                of: marker,
                with: "\(exportCode) \(marker)"
            )
        }

        return playerJs + "\n" + exportCode
    }

    /// Generates a minimal HTML file that loads the (already-patched) player.js
    /// from a local script tag, then provides `deobfuscateSig` / `transformN` / `buildSignedUrl`
    /// bridges for the native side to call via `evaluateJavaScript`.
    static func buildFileBasedHTML(playerHash: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <script src="base_\(playerHash).js"></script>
        <script>
        "use strict";

        // ============================================================
        // SIGNATURE DEOBFUSCATION
        // ============================================================
        function deobfuscateSig(funcName, constantArg, obfuscatedSig) {
            var func = window._cipherSigFunc;
            if (typeof func !== 'function') return null;
            try {
                var r = func(decodeURIComponent(obfuscatedSig));
                return (r !== undefined && r !== null && r !== '') ? String(r) : null;
            } catch(e) {
                return null;
            }
        }

        // ============================================================
        // N-PARAMETER TRANSFORM (no-op for this player version)
        // ============================================================
        function transformN(nValue) {
            return nValue;
        }

        // ============================================================
        // FULL URL BUILDER — uses player's own g.lq to construct URL
        // identical to YouTube's s2 function.
        // Pass baseUrl (decoded), sp param name, and URL-encoded sig.
        // Returns the fully constructed URL string.
        // ============================================================
        function buildSignedUrl(baseUrl, sp, encodedSig) {
            if (typeof window._buildSignedUrl === 'function') {
                return window._buildSignedUrl(baseUrl, sp, encodedSig);
            }
            return null;
        }

        // ============================================================
        // URL NORMALIZATION — syncs /n/ path segment with ?n= param
        // ============================================================
        function normalizeUrl(url) {
            if (typeof window._normalizeUrl === 'function') {
                return window._normalizeUrl(url);
            }
            return url;
        }

        // ============================================================
        // READY SIGNAL
        // ============================================================
        var info = {
            type: 'discovery',
            sigFuncName: typeof _cipherSigFunc === 'function' ? 'exported_fJ' : 'NOT_FOUND',
            nFuncName: typeof gN$ === 'function' ? 'gN$' : 'noop',
            info: 'player_loaded lq=' + (typeof _yt_player !== 'undefined' && typeof _yt_player.lq === 'function')
        };
        window.webkit.messageHandlers.cipher.postMessage(
            JSON.stringify(info)
        );
        window.webkit.messageHandlers.cipher.postMessage(
            JSON.stringify({type:'ready'})
        );
        </script>
        </head><body></body></html>
        """
    }

    // MARK: - Inline HTML (legacy)

    static func buildHTML(
        playerJs: String,
        sigConfig: String?,
        nClass: String?,
        playerHash: String?
    ) -> String {
        let modifiedJs = patchPlayerJs(
            playerJs: playerJs,
            sigConfig: sigConfig,
            nClass: nClass,
            playerHash: playerHash
        )
        return buildDiscoveryHtml(playerJs: modifiedJs)
    }

    private static func buildDiscoveryHtml(playerJs: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><script>
        "use strict";

        function deobfuscateSig(funcName, constantArg, obfuscatedSig) {
            var func = window._cipherSigFunc;
            if (typeof func !== 'function') return null;
            try {
                var r = func(decodeURIComponent(obfuscatedSig));
                return (r !== undefined && r !== null && r !== '') ? String(r) : null;
            } catch(e) {
                return null;
            }
        }

        function transformN(nValue) {
            var func = window._nTransformFunc;
            if (typeof func !== 'function') return nValue;
            try {
                var result = func(nValue);
                if (result === undefined || result === null || result === '') return nValue;
                var resultStr = String(result);
                return (resultStr.length > 0) ? resultStr : nValue;
            } catch(e) {
                return nValue;
            }
        }

        function buildSignedUrl(baseUrl, sp, encodedSig) {
            if (typeof window._buildSignedUrl === 'function') {
                return window._buildSignedUrl(baseUrl, sp, encodedSig);
            }
            return null;
        }

        function normalizeUrl(url) {
            if (typeof window._normalizeUrl === 'function') {
                return window._normalizeUrl(url);
            }
            return url;
        }

        function discoverAndInit() {
            var nFuncName = "";
            var sigFuncName = typeof _cipherSigFunc === 'function' ? 'exported_fJ' : 'NOT_FOUND';
            var info = 'player_inline';

            if (typeof window._nTransformFunc === 'function') {
                try {
                    var testInput = "KdrqFlzJXl9EcCwlmEy";
                    var testResult = window._nTransformFunc(testInput);
                    if (typeof testResult === 'string' && testResult !== testInput && /^[a-zA-Z0-9_-]+$/.test(testResult)) {
                        nFuncName = "exported_n_func";
                        info = "n_transform_active";
                    }
                } catch(e) {}
            }

            window.webkit.messageHandlers.cipher.postMessage(
                JSON.stringify({type:'discovery',sigFuncName:sigFuncName,nFuncName:nFuncName,info:info})
            );
            window.webkit.messageHandlers.cipher.postMessage(
                JSON.stringify({type:'ready'})
            );
        }
        </script>
        <script>
        \(playerJs)
        </script>
        <script>
        discoverAndInit();
        </script>
        </head><body></body></html>
        """
    }
}
