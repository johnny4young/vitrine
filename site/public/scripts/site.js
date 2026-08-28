/* localStorage is blocked in some sandboxed preview iframes — reading/writing it
     there throws, which would abort the whole script. Wrap it so a blocked store is
     a no-op, never fatal. */
  function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function lsSet(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* ignore */ } }
  /* ---------- i18n: English / Español ---------- */
  (function () {
    var ES = {
      "nav.bench": "Estilos", "nav.features": "Funciones", "nav.changelog": "Cambios", "nav.pricing": "Precio", "nav.download": "Descargar",
      "hero.kicker": "La app de macOS para compartir código y salida de terminal",
      "hero.h1": "Pon tu código <span class=\"em\">tras el cristal.</span>",
      "hero.tag": "Vitrine convierte el código copiado en imágenes preciosas y listas para compartir — pulsa <b>⇧⌘S</b> y pega. También captura tu terminal: <b>vgrab htop</b> reconstruye el fotograma final de una aplicación a pantalla completa, no una transcripción de códigos de escape. El renderizado permanece en tu Mac.",
      "hero.cta1": "Descargar para macOS", "hero.cta2": "Ver en GitHub",
      "hero.meta": "Última <b data-version>versión</b> · macOS 15+ · licencia MIT y gratis · el renderizado de código permanece en tu Mac",
      "bench.eyebrow": "El banco de estilos", "bench.title": "Un snippet. Todos los estilos.",
      "bench.lead": "Elige un degradado y un tema — el mismo código, reestilizado en vivo. En la app son presets guardados que se aplican al instante al pulsar el atajo.",
      "bench.bg": "Fondo (preset)", "bench.theme": "Tema", "bench.lang": "Lenguaje",
      "bench.note": "13 temas, 33 lenguajes de sintaxis y modos Terminal y Texto plano, fondos de degradado e imagen, modo enfoque y coloreado de diffs vienen en la app.",
      "story.eyebrow": "En el editor", "story.title": "Ajusta cuando quieras.",
      "story.lead": "El atajo cubre el caso común. Abre el editor para todo lo demás — capturas del build real.",
      "story1.h": "Un estudio para una imagen.",
      "story1.p": "Código a la izquierda, la vista previa flotando en luz ambiental al centro y el inspector de estilo a la derecha. Abre un archivo en vivo para actualizarlo durante la sesión al guardar, sin sobrescribir tus cambios locales.",
      "story1.t1": "13 temas", "story1.t2": "Fuentes de código", "story1.t3": "Degradado e imagen", "story1.t4": "Modo enfoque",
      "story2.h": "Anótala antes de enviarla.",
      "story2.p": "Una paleta tipo CleanShot integrada: flechas, cajas, texto, resaltador, desenfoque y censura, y contadores numerados — dibujados sobre la vista previa en vivo. Y <strong>Ocultar secretos</strong> escanea la captura en busca de API keys, tokens y contraseñas y oculta esas líneas con un clic — tanto en la imagen como en el texto copiable.",
      "story2.t1": "Flechas y cajas", "story2.t2": "Desenfoque / censura", "story2.t3": "Contadores", "story2.t4": "Escaneo de secretos",
      "story3.h": "Diffs que se leen como GitHub.",
      "story3.p": "Pega un diff unificado y Vitrine resalta las líneas añadidas en verde y las eliminadas en rojo, con números de línea — ideal para PRs y notas de versión.",
      "story3.t1": "Diff unificado", "story3.t2": "Números de línea", "story3.t3": "33 lenguajes de sintaxis",
      "story4.h": "Convierte capturas en una historia clara.",
      "story4.p": "<strong>Disponible en Vitrine 1.0:</strong> selecciona de dos a cuatro elementos en Recientes, conserva visible su orden y edita los textos y la disposición en un tablero comparativo dedicado. Copia, guarda o comparte el resultado; el tablero conserva píxeles terminados, no rutas de origen, y desaparece al cerrar su ventana.",
      "story4.t1": "Vitrine 1.0", "story4.t2": "2–4 capturas", "story4.t3": "Cuatro disposiciones", "story4.t4": "Solo durante la sesión",
      "story5.h": "Mantén la coherencia visual de un espacio de trabajo.",
      "story5.p": "<strong>Disponible en Vitrine 1.0:</strong> exporta el estilo actual y metadatos de cabecera seguros como una receta JSON sin rutas. Asóciala con una carpeta en este Mac para archivos que sueltas explícitamente, o pasa ese mismo archivo a <code>vitrine --recipe</code>; ninguna opción escanea el repositorio ni descubre configuración privada.",
      "story5.t1": "Vitrine 1.0", "story5.t2": "JSON portátil", "story5.t3": "CLI explícita", "story5.t4": "Sin escanear repositorios",
      "loop.eyebrow": "El flujo", "loop.title": "Tres pasos, memoria muscular.",
      "loop.s1h": "Copia", "loop.s1p": "Selecciona código en cualquier sitio — tu editor, una terminal, una web — y cópialo como siempre.",
      "loop.s2h": "Pulsa el atajo", "loop.s2p": "Vitrine lee el portapapeles, detecta código o una URL y envía cada entrada a su flujo correspondiente.",
      "loop.s3h": "Pega la imagen", "loop.s3p": "Las capturas de código dejan un PNG retina en tu portapapeles. Las capturas URL abren su editor Web para controlar viewports y exportación.",
      "more.eyebrow": "Y", "more.title": "Los detalles que importan.",
      "more.c1h": "Privada por diseño", "more.c1p": "El renderizado permanece en tu Mac: sin servidor de Vitrine, cuenta, analíticas ni telemetría. La red solo se usa para actualizaciones, activación de licencia y contenido que pides cargar explícitamente.",
      "more.c2h": "Exporta y comparte", "more.c2p": "PNG/PDF/HEIC retina al portapapeles, a archivo o al menú Compartir, más AVIF cuando macOS incluye su codificador ImageIO. Abre un archivo en vivo solo durante la sesión, exporta una receta de workspace sin rutas en Ajustes, asóciala localmente con una carpeta o pásala explícitamente a la CLI <code>vitrine</code>.",
      "more.c3h": "Capturas web", "more.c3p": "Renderiza HTML pegado localmente, o captura una página en varios viewports a la vez — social, escritorio, Full HD, móvil — compuestos en un tablero responsive para compartir. La página solicitada se descarga y renderiza en WebKit en tu Mac; no hay servicio remoto de capturas y la primera captura muestra un aviso de privacidad.",
      "vp.eyebrow": "Una página, cada pantalla", "vp.title": "Captura todos los viewports a la vez.",
      "vp.lead": "Apunta Vitrine a una URL o a HTML pegado y renderiza la página en varios viewports de una sola pasada — social, escritorio, Full HD, móvil — y los compone en un <em>tablero responsive</em> listo para compartir. El HTML pegado se renderiza sin red; las URLs están disponibles en el build de descarga directa tras el aviso y cargan la página solicitada en WebKit en tu Mac.",
      "term.eyebrow": "Terminal", "term.title": "Hasta TUIs de pantalla completa.",
      "term.lead": "Pega o usa <code>vgrab</code> con salida de terminal a color — y ahora también apps de pantalla completa como <code>htop</code>, <code>lazygit</code> y Neovim. Vitrine reconstruye la pantalla final — cada movimiento del cursor y su color, con caracteres anchos (CJK y emoji) incluidos — en tu tema.",
      "cl.eyebrow": "Cambios", "cl.title": "Novedades", "cl.lead": "Los puntos destacados de la versión más reciente de Vitrine, disponibles sin esperar una solicitud de red.",
      "cl.version": "Versión", "cl.headline": "Captura más rápida, límites más seguros",
      "cl.h1": "<strong>La captura básica de terminal ahora es gratuita.</strong> Usa <code>vgrab</code> para copiar la salida de un comando o abrirla en Vitrine sin una licencia PRO.",
      "cl.h2": "<strong>La búsqueda funciona como un solo sistema.</strong> Comandos, recientes, temas y fuentes encuentran varias palabras en cualquier orden, con un manejo uniforme de mayúsculas y acentos.",
      "cl.h3": "<strong>Las entradas grandes o bloqueadas fallan de forma segura.</strong> Las importaciones de imágenes, los elementos soltados en el editor y las capturas web respetan límites explícitos de tamaño o tiempo, en lugar de quedarse colgados o agotar memoria.",
      "cl.h4": "<strong>Sequoia y Tahoe siguen siendo plataformas de primera clase.</strong> Las pantallas compactas mantienen los controles accesibles y las opciones de exportación reflejan los formatos que cada Mac realmente puede escribir.",
      "cl.more": "Leer el changelog completo →",
      "pro.title": "Pásate a PRO cuando lo necesites.",
      "pro.lead": "Con licencia MIT y gratis. La captura y edición principales siguen siendo gratis: sin marca de agua, límite de resolución ni molestias. PRO es una licencia opcional <strong>de pago único</strong> — sin suscripción.",
      "pro.evaluation": "No hay una prueba que caduque. Usa el núcleo gratuito todo el tiempo que quieras y pásate a PRO solo cuando Brand Kit, los flujos multi-tamaño/carrusel o la automatización avanzada compensen.",
      "pro.badge": "Lanzamiento · solo 2026",
      "pro.note": "El precio actual en checkout es <strong>$19.99</strong> como pago único. El precio normal previsto es <strong>$25</strong> después del periodo de lanzamiento de 2026.",
      "pro.l1": "Brand Kit — tu logo, usuario y acento como marca de agua en cada exportación",
      "pro.l2": "Exportación multi-tamaño en una pasada — cada tamaño de plataforma a una carpeta de una vez",
      "pro.l3": "Automatización avanzada — renderizado general con <code>vitrine</code>, multi-tamaño, lotes, vpane y Atajos (vgrab básico sigue gratis)",
      "pro.cta1": "Obtener Vitrine PRO", "pro.cta2": "Descargar gratis",
      "pro.foot": "Paga una vez y actívalo en la app con la clave de licencia que recibes por correo. Los avisos de PRO aparecen solo al invocar una acción PRO, nunca al iniciar.",
      "inst.eyebrow": "Instalar", "inst.title": "A dos comandos.",
      "inst.lead": "Homebrew y el DMG firmado y notarizado son los canales canónicos. Homebrew añade la app y la CLI a tu PATH; con el DMG puedes activar la CLI desde Ajustes. La compilación opcional de la App Store es solo gráfica.",
      "inst.dmg": "Descargar el DMG", "inst.src": "Compilar desde el código",
      "foot.pill": "Sin cuenta · renderizado local · sin telemetría",
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
    enBtn.onclick = function () { window.location.assign(enBtn.dataset.target || "/"); };
    esBtn.onclick = function () { window.location.assign(esBtn.dataset.target || "/es"); };
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

  /* live release download */
  var REPO = "johnny4young/vitrine";
  fetch("https://api.github.com/repos/"+REPO+"/releases/latest").then(function(r){return r.ok?r.json():Promise.reject();}).then(function(rel){
    var tag = rel.tag_name||""; window.__vtag = tag; document.querySelectorAll("[data-version]").forEach(function(el){ if(tag) el.textContent=tag; });
    var dmg=(rel.assets||[]).find(function(a){return /\.dmg$/i.test(a.name);}); var url=dmg?dmg.browser_download_url:rel.html_url;
    document.querySelectorAll("[data-download]").forEach(function(el){el.href=url;});
  }).catch(function(){});
  document.getElementById("copy-brew").addEventListener("click", function(){
    var btn=this; navigator.clipboard.writeText("brew install --cask johnny4young/tap/vitrine").then(function(){
      btn.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7"></path></svg> Copied';
      setTimeout(function(){ btn.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="8.5" y="8.5" width="11" height="11" rx="2"></rect><path d="M5.5 15.5H5a1.5 1.5 0 0 1-1.5-1.5V5A1.5 1.5 0 0 1 5 3.5h9A1.5 1.5 0 0 1 15.5 5v.5"></path></svg> Copy'; }, 1800);
    });
  });
