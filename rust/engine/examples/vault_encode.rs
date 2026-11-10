//! Offline encoder for the secret config vault.
//!
//! Edit the plaintext table below, then run:
//!     cargo run --example vault_encode -p taycoon_engine > src/vault_values.rs
//! The keystream comes from `taycoon_engine::vault::fold`, the single source of
//! truth shared with the VM decoder (guarded by `vault::tests::vm_matches_plain`).
//!
//! Empty strings are intentional stubs: the config endpoint, AppsFlyer dev key
//! and Firebase sender id stay empty until the operator supplies them, which
//! keeps `vault::ready()` false and ships the native experience only.

use taycoon_engine::vault::fold;

// WebView bootstrap script. One IIFE, one sentinel, injected into every frame.
const WEB_INJECTION: &str = r#"(function(){var F='__q7v';if(window[F])return;window[F]=1;function head(){return document.head||document.documentElement;}function typing(){var v=window.visualViewport;return !!v&&v.height<window.innerHeight*0.72;}function lockView(){if(typing())return;var h=head();if(!h)return;var m=document.querySelector('meta[name="viewport"]');if(!m){m=document.createElement('meta');m.name='viewport';h.appendChild(m);}m.setAttribute('content','width=device-width, initial-scale=1, maximum-scale=1, minimum-scale=1, user-scalable=no, viewport-fit=contain');var s=document.getElementById('q7v-s');if(!s){s=document.createElement('style');s.id='q7v-s';h.appendChild(s);}s.textContent=':root{--safe-area-inset-top:0px;--safe-area-inset-right:0px;--safe-area-inset-bottom:0px;--safe-area-inset-left:0px;}html,body{overscroll-behavior:none;}input,textarea,select,[contenteditable="true"]{font-size:max(16px,1em);}*{-webkit-tap-highlight-color:transparent;}';}['gesturestart','gesturechange','gestureend'].forEach(function(n){document.addEventListener(n,function(e){e.preventDefault();},{passive:false});});var last=0;document.addEventListener('touchend',function(e){var n=Date.now();if(n-last<320)e.preventDefault();last=n;},{passive:false});function play(v){if(!(v instanceof HTMLVideoElement))return;v.setAttribute('playsinline','');v.setAttribute('webkit-playsinline','');v.playsInline=true;var p=v.play();if(p&&p.catch)p.catch(function(){});}function scan(node){if(node instanceof HTMLVideoElement)play(node);if(node&&node.querySelectorAll){var l=node.querySelectorAll('video');for(var i=0;i<l.length;i++)play(l[i]);}}scan(document);new MutationObserver(function(recs){for(var i=0;i<recs.length;i++){var a=recs[i].addedNodes;for(var j=0;j<a.length;j++)scan(a[j]);}}).observe(document.documentElement,{childList:true,subtree:true});['pushState','replaceState'].forEach(function(fn){var o=history[fn];history[fn]=function(){var r=o.apply(this,arguments);setTimeout(lockView,140);return r;};});window.addEventListener('popstate',function(){setTimeout(lockView,140);});lockView();setInterval(lockView,2800);})();"#;

fn main() {
    // id-name, plaintext. Order is cosmetic; `name` sets the const identifier.
    let table: &[(&str, &str)] = &[
        ("ENC_ENDPOINT", "https://revotaycoon.com/config.php"),
        ("ENC_AF_KEY", "9bn7jUeX9TH8PSkw3QwKWg"),
        ("ENC_FIREBASE_SENDER", "886111549144"), // GCM_SENDER_ID (GoogleService-Info.plist)
        ("ENC_GCD_BASE", "https://gcdsdk.appsflyer.com/install_data/v5.0/"),
        ("ENC_PRIVACY", ""), // TODO: privacy policy URL
        ("ENC_SUPPORT", ""), // TODO: support URL
        ("ENC_UA_PRODUCT", "Mozilla/5.0"),
        ("ENC_UA_PLATFORM_PREFIX", "(iPhone; CPU iPhone OS"),
        ("ENC_UA_PLATFORM_SUFFIX", "like Mac OS X)"),
        ("ENC_UA_ENGINE", "AppleWebKit/605.1.15 (KHTML, like Gecko)"),
        ("ENC_UA_SAFARI_VERSION", "26.0"),
        ("ENC_UA_MOBILE_TOKEN", "Mobile/15E148"),
        ("ENC_UA_SAFARI_TAIL", "604.1"),
        ("ENC_STORE_ID", "6824470855"),
        ("ENC_STORAGE_PREFIX", "rt.state"),
        ("ENC_LAUNCH_ROUTE_KEY", "rt.state.ln"),
        ("ENC_PROBE_HOST_A", "www.apple.com"),
        ("ENC_PROBE_HOST_B", "one.one.one.one"),
        // Push payload scanning — candidate URL keys + bookkeeping keys to skip.
        ("ENC_PUSH_URL_KEYS", "deep_link,target,url,deeplink,link,dest,destination"),
        ("ENC_PUSH_SKIP_KEYS", "aps,gcm.message_id,google.c.sender.id,google.c.fid,collapse_key,from,sound,title,body,badge,mutable-content"),
        // "Not Now" cooldown on the push opt-in screen (seconds).
        ("ENC_PUSH_SNOOZE", "247734"),
        // Config POST body field names, in a single ordered CSV so only one
        // decoded string ever lives in Swift memory. Order matters:
        // 0=af_id 1=bundle_id 2=os 3=store_id 4=locale 5=push_token
        // 6=firebase_project_id 7=sub_id_10.
        ("ENC_BODY_KEYS", "af_id,bundle_id,os,store_id,locale,push_token,firebase_project_id,sub_id_10"),
        // Platform value for the body — must not appear as a plaintext "iOS"
        // literal in the Swift binary (otherwise it's a trivial grep match).
        ("ENC_OS_VALUE", "iOS"),
        // HTTP content/accept and GCD Authorization prefix.
        ("ENC_HDR_JSON", "application/json"),
        ("ENC_HDR_AUTH", "Bearer "),
        // WebView navigation scheme allowlist (dropping anything else protects
        // against javascript: and surprise app-scheme hops).
        ("ENC_WEB_SCHEMES", "http,https,about,data,blob"),
        // Reachability probe hosts — a THIRD neutral host next to apple.com
        // and one.one.one.one so a sim that stalls on both still answers.
        ("ENC_PROBE_HOST_C", "www.cloudflare.com"),
        // Config POST round-trip timeout in seconds (ASCII decimal). Encoded
        // to keep this magic number off the Swift side as a literal.
        ("ENC_CFG_TIMEOUT", "11"),
        // Per-probe HEAD timeout in milliseconds for `canReachNetwork`.
        ("ENC_PROBE_TIMEOUT_MS", "1400"),
        // Merged WebView bootstrap — viewport lock, zoom swallow, inline video,
        // SPA re-pin. Lives here so the behaviour set is not a plaintext match
        // in the Swift binary. Sentinel + ids are project-local.
        ("ENC_WEB_INJECTION", WEB_INJECTION),
        ("ENC_JS_REFLOW", "window.dispatchEvent(new Event('resize'));window.visualViewport&&window.visualViewport.dispatchEvent(new Event('resize'));"),
        ("ENC_JS_FOCUS", "var a=document.activeElement;if(a&&a.scrollIntoView)a.scrollIntoView({block:'center'});"),
        // WebView timing — ms unless noted. Off the Swift side as literals.
        ("ENC_WEB_REFLOW_DELAYS", "60,210,400,640,910"),
        ("ENC_WEB_POST_FINISH_MS", "690"),
        ("ENC_WEB_COLD_SETTLE_MS", "340"),
        ("ENC_WEB_REDIRECT_RETRY", "4"),
        ("ENC_WEB_NET_RETRY", "3"),
    ];

    println!("// @generated by `cargo run --example vault_encode -p taycoon_engine`.");
    println!("// Do not hand-edit. Regenerate from examples/vault_encode.rs.");
    for (name, value) in table {
        let bytes = fold(value);
        let joined = bytes
            .iter()
            .map(|b| b.to_string())
            .collect::<Vec<_>>()
            .join(", ");
        println!("pub(crate) const {name}: &[u8] = &[{joined}];");
    }
}
