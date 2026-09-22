/* localStorage is blocked in some sandboxed preview iframes — reading/writing it
     there throws, which would abort the whole script. Wrap it so a blocked store is
     a no-op, never fatal. */
  function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function lsSet(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* ignore */ } }
  /* appearance toggle */
  (function () {
    var KEY = "vitrine-landing-b-appearance";
    var light = document.getElementById("set-light"), dark = document.getElementById("set-dark");
    function apply(mode) {
      var isDark = mode === "dark";
      document.body.classList.toggle("vitrine-dark", isDark);
      light.classList.toggle("active", !isDark);
      dark.classList.toggle("active", isDark);
      light.setAttribute("aria-pressed", String(!isDark));
      dark.setAttribute("aria-pressed", String(isDark));
    }
    apply(lsGet(KEY) || "light");
    light.onclick = function () { lsSet(KEY, "light"); apply("light"); };
    dark.onclick = function () { lsSet(KEY, "dark"); apply("dark"); };
  })();

  /* ---------- style bench ---------- */
  (function () {
    var stage = document.getElementById("stage");
    var card = document.getElementById("benchCard");
    var codeEl = document.getElementById("benchCode");
    var nameEl = document.getElementById("benchName");

    var THEMES = {
      "one-dark":  { bg: "#1c1d24", fg: "#c8cad6", k:"#c792ea", t:"#82aaff", n:"#f78c6c", s:"#c3e88d", f:"#82aaff", c:"#6b6a86" },
      "one-light": { bg: "#fafafa", fg: "#383a42", k:"#a626a4", t:"#4078f2", n:"#986801", s:"#50a14f", f:"#4078f2", c:"#a0a1a7" },
      "dracula":   { bg: "#282a36", fg: "#f8f8f2", k:"#ff79c6", t:"#8be9fd", n:"#bd93f9", s:"#f1fa8c", f:"#50fa7b", c:"#6272a4" }
    };
    var SNIPPETS = {
      swift: { name: "Counter.swift", html:
        '<span class="k">import</span> SwiftUI\n\n<span class="k">struct</span> <span class="t">Counter</span> {\n  <span class="k">private(set) var</span> value = <span class="n">0</span>\n\n  <span class="k">mutating func</span> <span class="f">increment</span>(by step: <span class="t">Int</span> = <span class="n">1</span>) {\n    value += step\n  }\n}' },
      ts: { name: "api.ts", html:
        '<span class="k">export const</span> <span class="f">getUser</span> = <span class="k">async</span> (id: <span class="t">string</span>) =&gt; {\n  <span class="k">const</span> res = <span class="k">await</span> <span class="f">fetch</span>(<span class="s">`/api/u/${id}`</span>)\n  <span class="k">if</span> (!res.ok) <span class="k">throw new</span> <span class="t">Error</span>(<span class="s">"not found"</span>)\n  <span class="k">return</span> res.<span class="f">json</span>()\n}' },
      py: { name: "main.py", html:
        '<span class="k">def</span> <span class="f">greet</span>(name: <span class="t">str</span>) -&gt; <span class="t">str</span>:\n    <span class="c"># a tiny hello</span>\n    <span class="k">return</span> <span class="s">f"Hello, {name}!"</span>\n\n<span class="f">print</span>(<span class="f">greet</span>(<span class="s">"world"</span>))' }
    };
    var current = "swift";

    function paintTheme(name) {
      var th = THEMES[name];
      card.style.background = th.bg;
      codeEl.style.color = th.fg;
      codeEl.style.setProperty("--ck", th.k);
      ["k","t","n","s","f","c"].forEach(function (cls) {
        codeEl.querySelectorAll("." + cls).forEach(function (el) { el.style.color = th[cls]; });
      });
    }
    function paintSnippet(lang) {
      current = lang;
      codeEl.innerHTML = SNIPPETS[lang].html;
      nameEl.textContent = SNIPPETS[lang].name;
      var active = document.querySelector('#themes .chip[aria-pressed="true"]').dataset.theme;
      paintTheme(active);
    }
    function press(group, el) { group.querySelectorAll(".chip,.swatch").forEach(function (b) { b.setAttribute("aria-pressed", b === el ? "true" : "false"); }); }

    document.getElementById("swatches").addEventListener("click", function (e) {
      var b = e.target.closest(".swatch"); if (!b) return;
      stage.style.background = b.dataset.grad; press(this, b);
    });
    document.getElementById("themes").addEventListener("click", function (e) {
      var b = e.target.closest(".chip"); if (!b) return;
      press(this, b); paintTheme(b.dataset.theme);
    });
    document.getElementById("langs").addEventListener("click", function (e) {
      var b = e.target.closest(".chip"); if (!b) return;
      press(this, b); paintSnippet(b.dataset.lang);
    });
    paintTheme("one-dark");
  })();

  /* live release download */
  var REPO = "johnny4young/vitrine";
  fetch("https://api.github.com/repos/"+REPO+"/releases/latest").then(function(r){return r.ok?r.json():Promise.reject();}).then(function(rel){
    var tag = rel.tag_name||""; document.querySelectorAll("[data-version]").forEach(function(el){ if(tag) el.textContent=tag; });
    var dmg=(rel.assets||[]).find(function(a){return /\.dmg$/i.test(a.name);}); var url=dmg?dmg.browser_download_url:rel.html_url;
    document.querySelectorAll("[data-download]").forEach(function(el){el.href=url;});
  }).catch(function(){});
  document.getElementById("copy-brew").addEventListener("click", function () {
    var button = this;
    var feedback = document.getElementById("install-feedback");
    var command = document.getElementById("brew-cmd").textContent;
    if (!navigator.clipboard) {
      feedback.textContent = button.dataset.errorLabel;
      return;
    }
    navigator.clipboard.writeText(command).then(function () {
      feedback.textContent = button.dataset.copiedLabel;
    }).catch(function () {
      feedback.textContent = button.dataset.errorLabel;
    });
  });
