/* localStorage is blocked in some sandboxed preview iframes — reading/writing it
     there throws, which would abort the whole script. Wrap it so a blocked store is
     a no-op, never fatal. */
  function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function lsSet(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* ignore */ } }
  /* ---------- i18n: English / Español ---------- */
  (function () {
    var ES = {
      "nav.bench": "Estilos", "nav.features": "Funciones", "nav.changelog": "Cambios", "nav.pricing": "Precio", "nav.download": "Descargar",
      "hero.kicker": "La app de menu bar para compartir código",
      "hero.h1": "Pon tu código <span class=\"em\">tras el cristal.</span>",
      "hero.tag": "Vitrine convierte código, URLs y HTML en imágenes preciosas y listas para compartir — copia, pulsa <b>⇧⌘S</b>, pega. Al instante, y todo local.",
      "hero.cta1": "Descargar para macOS", "hero.cta2": "Ver en GitHub",
      "hero.meta": "Última <b data-version>versión</b> · macOS 14+ · libre y de código abierto · tu código nunca sale de tu Mac",
      "bench.eyebrow": "El banco de estilos", "bench.title": "Un snippet. Todos los estilos.",
      "bench.lead": "Elige un degradado y un tema — el mismo código, reestilizado en vivo. En la app son presets guardados que se aplican al instante al pulsar el atajo.",
      "bench.bg": "Fondo (preset)", "bench.theme": "Tema", "bench.lang": "Lenguaje",
      "bench.note": "13 temas, 160+ lenguajes, fondos de degradado e imagen, modo enfoque y coloreado de diffs vienen en la app.",
      "story.eyebrow": "En el editor", "story.title": "Ajusta cuando quieras.",
      "story.lead": "El atajo cubre el caso común. Abre el editor para todo lo demás — capturas del build real.",
      "story1.h": "Un estudio para una imagen.",
      "story1.p": "Código a la izquierda, la vista previa flotando en luz ambiental al centro, el inspector de estilo a la derecha. Tema, fuente, relleno, marco de ventana, fondo — cada control a un clic.",
      "story1.t1": "13 temas", "story1.t2": "Fuentes de código", "story1.t3": "Degradado e imagen", "story1.t4": "Modo enfoque",
      "story2.h": "Anótala antes de enviarla.",
      "story2.p": "Una paleta tipo CleanShot integrada: flechas, cajas, texto, resaltador, desenfoque y censura, y contadores numerados — dibujados sobre la vista previa en vivo. Y <strong>Ocultar secretos</strong> escanea la captura en busca de API keys, tokens y contraseñas y oculta esas líneas con un clic — tanto en la imagen como en el texto copiable.",
      "story2.t1": "Flechas y cajas", "story2.t2": "Desenfoque / censura", "story2.t3": "Contadores", "story2.t4": "Escaneo de secretos",
      "story3.h": "Diffs que se leen como GitHub.",
      "story3.p": "Pega un diff unificado y Vitrine resalta las líneas añadidas en verde y las eliminadas en rojo, con números de línea — ideal para PRs y notas de versión.",
      "story3.t1": "Diff unificado", "story3.t2": "Números de línea", "story3.t3": "160+ lenguajes",
      "loop.eyebrow": "El flujo", "loop.title": "Tres pasos, memoria muscular.",
      "loop.s1h": "Copia", "loop.s1p": "Selecciona código en cualquier sitio — tu editor, una terminal, una web — y cópialo como siempre.",
      "loop.s2h": "Pulsa el atajo", "loop.s2p": "Vitrine lee el portapapeles, detecta código, una URL o HTML, y renderiza con tu estilo guardado.",
      "loop.s3h": "Pega la imagen", "loop.s3p": "Un PNG retina queda en tu portapapeles. Pégalo en tu doc, PR, chat o diapositiva.",
      "more.eyebrow": "Y", "more.title": "Los detalles que importan.",
      "more.c1h": "Privada por diseño", "more.c1p": "Totalmente local y en sandbox — sin cuenta, sin red por defecto, sin telemetría. Tu código nunca sale de tu Mac.",
      "more.c2h": "Exporta y comparte", "more.c2p": "PNG/PDF retina al portapapeles, a archivo o al menú Compartir. Presets OpenGraph, Story y banner de GitHub, más una CLI <code>vitrine</code>.",
      "more.c3h": "Capturas web", "more.c3p": "Renderiza HTML pegado, o captura una página en varios viewports a la vez — social, escritorio, Full HD, móvil — compuestos en un tablero responsive para compartir. Todo local en WebKit, con un aviso de privacidad la primera vez.",
      "vp.eyebrow": "Una página, cada pantalla", "vp.title": "Captura todos los viewports a la vez.",
      "vp.lead": "Apunta Vitrine a una URL o a HTML pegado y renderiza la página en varios viewports de una sola pasada — social, escritorio, Full HD, móvil — y los compone en un <em>tablero responsive</em> listo para compartir. La forma más rápida de mostrar un diseño adaptándose a cada pantalla. Todo local, en WebKit.",
      "term.eyebrow": "Terminal", "term.title": "Hasta TUIs de pantalla completa.",
      "term.lead": "Pega o usa <code>vgrab</code> con salida de terminal a color — y ahora también apps de pantalla completa como <code>htop</code>, <code>lazygit</code> y Neovim. Vitrine reconstruye la pantalla final — cada movimiento del cursor y su color, con caracteres anchos (CJK y emoji) incluidos — en tu tema.",
      "cl.eyebrow": "Cambios", "cl.title": "Novedades", "cl.lead": "Se cargan en vivo desde el <code>CHANGELOG.md</code> del proyecto — siempre al día, nada que mantener.",
      "pro.title": "Pásate a PRO cuando lo necesites.",
      "pro.lead": "Libre y de código abierto, para siempre. PRO es una licencia opcional <strong>de pago único</strong> — sin suscripción. La versión gratis no pierde nada: sin marca de agua, sin límite de resolución, sin molestias.",
      "pro.badge": "Lanzamiento · solo 2026",
      "pro.note": "El precio normal es <strong>$25</strong>. Durante 2026 son <strong>$19.99</strong> como precio de lanzamiento — sin código.",
      "pro.l1": "Brand Kit — tu logo, usuario y acento como marca de agua en cada exportación",
      "pro.l2": "Exportación multi-tamaño en una pasada — cada tamaño de plataforma a una carpeta de una vez",
      "pro.l3": "Automatización — la CLI <code>vitrine</code>, Atajos y renderizado por lotes de carpetas",
      "pro.cta1": "Obtener Vitrine PRO", "pro.cta2": "Descargar gratis",
      "pro.foot": "Paga una vez y actívalo en la app con la clave de licencia que recibes por correo.",
      "inst.eyebrow": "Instalar", "inst.title": "A dos comandos.",
      "inst.lead": "Instala con Homebrew, o descarga el DMG firmado y notarizado. En ambos casos, la CLI <code>vitrine</code> queda en tu PATH.",
      "inst.dmg": "Descargar el DMG", "inst.src": "Compilar desde el código",
      "foot.pill": "Sin cuenta · sin red por defecto · sin telemetría",
      "foot.note": "Código abierto bajo licencia MIT. Hecho por <a href=\"https://github.com/johnny4young\" style=\"color:var(--accent)\">johnny4young</a>."
    };
    var nodes = document.querySelectorAll("[data-i18n]");
    var EN = {};
    nodes.forEach(function (n) { EN[n.getAttribute("data-i18n")] = n.innerHTML; });
    var enBtn = document.getElementById("set-en"), esBtn = document.getElementById("set-es");
    function apply(lang) {
      var es = lang === "es";
      document.documentElement.lang = es ? "es" : "en";
      nodes.forEach(function (n) {
        var key = n.getAttribute("data-i18n");
        var val = es ? (ES[key] != null ? ES[key] : EN[key]) : EN[key];
        if (n.innerHTML !== val) n.innerHTML = val;
      });
      enBtn.classList.toggle("active", !es);
      esBtn.classList.toggle("active", es);
      enBtn.setAttribute("aria-pressed", String(!es));
      esBtn.setAttribute("aria-pressed", String(es));
      if (window.__vtag) document.querySelectorAll("[data-version]").forEach(function (el) { el.textContent = window.__vtag; });
    }
    apply(document.documentElement.lang === "es" ? "es" : "en");
    enBtn.onclick = function () { window.location.assign("/"); };
    esBtn.onclick = function () { window.location.assign("/es"); };
  })();

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

  /* live release + changelog */
  var REPO = "johnny4young/vitrine";
  function renderChangelog(section) {
    function inline(s) { return s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/`([^`]+)`/g,"<code>$1</code>").replace(/\*\*([^*]+)\*\*/g,"<strong>$1</strong>"); }
    var out = [], inList = false;
    section.split("\n").forEach(function (raw) {
      var line = raw.replace(/\s+$/, "");
      if (/^##\s+/.test(line)) { if (inList){out.push("</ul>");inList=false;} out.push('<div class="ver">'+inline(line.replace(/^##\s+/,""))+"</div>"); }
      else if (/^###\s+/.test(line)) { if (inList){out.push("</ul>");inList=false;} out.push('<div class="cat">'+inline(line.replace(/^###\s+/,""))+"</div>"); }
      else if (/^\s*-\s+/.test(line)) { if (!inList){out.push("<ul>");inList=true;} out.push("<li>"+inline(line.replace(/^\s*-\s+/,""))+"</li>"); }
      else if (inList && /^\s+\S/.test(line)) { out[out.length-1]=out[out.length-1].replace(/<\/li>$/," "+inline(line.trim())+"</li>"); }
      else if (line.trim()!=="") { if (inList){out.push("</ul>");inList=false;} out.push("<p>"+inline(line)+"</p>"); }
    });
    if (inList) out.push("</ul>");
    return out.join("");
  }
  fetch("https://api.github.com/repos/"+REPO+"/releases/latest").then(function(r){return r.ok?r.json():Promise.reject();}).then(function(rel){
    var tag = rel.tag_name||""; window.__vtag = tag; document.querySelectorAll("[data-version]").forEach(function(el){ if(tag) el.textContent=tag; });
    var dmg=(rel.assets||[]).find(function(a){return /\.dmg$/i.test(a.name);}); var url=dmg?dmg.browser_download_url:rel.html_url;
    document.querySelectorAll("[data-download]").forEach(function(el){el.href=url;});
  }).catch(function(){});
  fetch("https://raw.githubusercontent.com/"+REPO+"/main/CHANGELOG.md").then(function(r){return r.ok?r.text():Promise.reject();}).then(function(md){
    var lines=md.split("\n"); var start=lines.findIndex(function(l){return /^##\s*\[?[0-9v]/.test(l);}); if(start<0) throw 0;
    var end=-1; for(var i=start+1;i<lines.length;i++){ if(/^##\s*\[?[0-9v]/.test(lines[i])){end=i;break;} } if(end<0) end=lines.length;
    document.getElementById("changelog-body").innerHTML = renderChangelog(lines.slice(start,end).join("\n")) + '<a class="more" href="https://github.com/'+REPO+'/blob/main/CHANGELOG.md">Full changelog →</a>';
  }).catch(function(){
    document.getElementById("changelog-body").innerHTML = '<div class="ver">Latest release</div><p class="muted">Release notes load live from the repository when this page is online.</p><a class="more" href="https://github.com/'+REPO+'/blob/main/CHANGELOG.md">Read the changelog on GitHub →</a>';
  });
  document.getElementById("copy-brew").addEventListener("click", function(){
    var btn=this; navigator.clipboard.writeText("brew install --cask johnny4young/tap/vitrine").then(function(){
      btn.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7"></path></svg> Copied';
      setTimeout(function(){ btn.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="8.5" y="8.5" width="11" height="11" rx="2"></rect><path d="M5.5 15.5H5a1.5 1.5 0 0 1-1.5-1.5V5A1.5 1.5 0 0 1 5 3.5h9A1.5 1.5 0 0 1 15.5 5v.5"></path></svg> Copy'; }, 1800);
    });
  });
