import type { Locale } from './content';

export type LocalizedText = Record<Locale, string>;

export type CLICommandDoc = {
  id: string;
  name: string;
  syntax: string;
  summary: LocalizedText;
  detail: LocalizedText;
};

export type CLIExample = {
  id: string;
  title: LocalizedText;
  summary: LocalizedText;
  code: string;
  note?: LocalizedText;
};

export type CLIOption = {
  flags: string;
  value?: string;
  description: LocalizedText;
};

export type CLIOptionGroup = {
  id: string;
  title: LocalizedText;
  intro: LocalizedText;
  options: CLIOption[];
};

const both = (en: string, es: string): LocalizedText => ({ en, es });

export const cliCommands: CLICommandDoc[] = [
  {
    id: 'terminal-capture',
    name: 'terminal-capture',
    syntax: 'vitrine terminal-capture <capture-file> (--copy | --edit)',
    summary: both('Free path behind vgrab', 'Ruta gratuita de vgrab'),
    detail: both(
      'The constrained local command emitted by vgrab. It accepts terminal width and context, but no general styling, file output, sidecars, or batch automation.',
      'El comando local y limitado que usa vgrab. Acepta ancho y contexto de terminal, pero no estilos generales, salida a archivo, archivos auxiliares ni automatización por lotes.',
    ),
  },
  {
    id: 'render',
    name: 'render',
    syntax: 'vitrine render <input> --out <image> [options]',
    summary: both('Create one image', 'Crear una imagen'),
    detail: both(
      'Render a source file, standard input, a Git diff, or a local image. Write it to disk, copy it, or hand the source to the editor.',
      'Renderiza un archivo, la entrada estándar, un diff de Git o una imagen local. Guárdalo, cópialo o envía la fuente al editor.',
    ),
  },
  {
    id: 'multi-size',
    name: 'multi-size',
    syntax: 'vitrine multi-size <input> --out <folder> [--presets <ids>]',
    summary: both('One source, many destinations', 'Una fuente, varios destinos'),
    detail: both(
      'Load one source once, then export deterministic sizes such as OpenGraph, X, LinkedIn, and Story into one folder.',
      'Carga una fuente una sola vez y exporta tamaños deterministas como OpenGraph, X, LinkedIn y Story en una carpeta.',
    ),
  },
  {
    id: 'batch',
    name: 'batch',
    syntax: 'vitrine batch <input-folder> --out <output-folder> [options]',
    summary: both('Render a folder safely', 'Renderizar una carpeta con seguridad'),
    detail: both(
      'Turn a source tree into image assets with recursive discovery, extension filters, dry runs, manifests, and strict CI exit behavior.',
      'Convierte un árbol de fuentes en imágenes con recorrido recursivo, filtros, simulación, manifiestos y resultados estrictos para CI.',
    ),
  },
  {
    id: 'recipe',
    name: 'recipe',
    syntax: 'vitrine recipe <validate|show> <path> [--json]',
    summary: both('Inspect portable style recipes', 'Inspeccionar recetas portátiles'),
    detail: both(
      'Validate or display one explicitly named recipe without rendering. Vitrine never searches a repository or parent folder for configuration.',
      'Valida o muestra una receta nombrada explícitamente sin renderizar. Vitrine nunca busca configuración en el repositorio ni en carpetas superiores.',
    ),
  },
  {
    id: 'list',
    name: 'list',
    syntax: 'vitrine list <catalog> [--json]',
    summary: both('Discover valid local identifiers', 'Descubrir identificadores válidos'),
    detail: both(
      'List themes, languages, presets, fonts, backgrounds, frames, formats, profiles, and other values shipped by the installed build.',
      'Lista temas, lenguajes, ajustes, fuentes, fondos, marcos, formatos, perfiles y otros valores incluidos en la compilación instalada.',
    ),
  },
  {
    id: 'version',
    name: 'version',
    syntax: 'vitrine --version [--json]',
    summary: both('Verify the installed build', 'Verificar la compilación instalada'),
    detail: both(
      'Print the CLI marketing version and build number before AppKit starts. This is safe and inexpensive in setup scripts.',
      'Muestra la versión y el número de compilación antes de iniciar AppKit. Es una comprobación rápida y segura para automatizaciones.',
    ),
  },
  {
    id: 'shell-init',
    name: 'shell-init',
    syntax: 'vitrine shell-init [zsh|bash|fish]',
    summary: both('Install terminal capture helpers', 'Instalar ayudantes de terminal'),
    detail: both(
      'Print the shell functions behind vgrab and vpane. Nothing runs in the background; the helpers only act when you invoke them.',
      'Muestra las funciones de shell de vgrab y vpane. Nada se ejecuta en segundo plano; solo actúan cuando las invocas.',
    ),
  },
];

export const cliExamples: CLIExample[] = [
  {
    id: 'first-image',
    title: both('Render your first file', 'Renderiza tu primer archivo'),
    summary: both(
      'Language is inferred from the filename and the output format from the extension.',
      'El lenguaje se infiere del nombre del archivo y el formato de la extensión.',
    ),
    code: 'vitrine render Sources/App.swift --out app-card.png',
  },
  {
    id: 'clipboard',
    title: both('Turn a pipe into a clipboard image', 'Convierte una canalización en una imagen'),
    summary: both(
      'Use a filename hint so syntax detection and the visible metadata remain useful.',
      'Usa una pista de nombre para que la detección y los metadatos sigan siendo útiles.',
    ),
    code: 'cat Component.tsx | vitrine render --stdin \\\n  --stdin-name Component.tsx --copy',
  },
  {
    id: 'git-review',
    title: both('Make a focused PR image', 'Crea una imagen enfocada para un PR'),
    summary: both(
      'Read Git directly, keep stable diff prefixes, and limit the image to the paths you are discussing.',
      'Lee Git directamente, conserva prefijos estables y limita la imagen a las rutas que estás explicando.',
    ),
    code: 'vitrine render --git-diff main...HEAD \\\n  --git-path Vitrine/CLI --git-context 6 \\\n  --out cli-review.png',
  },
  {
    id: 'staged-review',
    title: both('Capture only staged changes', 'Captura solo los cambios preparados'),
    summary: both(
      'Useful before committing: the image matches the index, not unrelated work in your working tree.',
      'Útil antes de confirmar cambios: la imagen coincide con el índice y no con trabajo no relacionado.',
    ),
    code: 'vitrine render --git-staged --out staged-review.png',
  },
  {
    id: 'terminal',
    title: both('Share a terminal command with context', 'Comparte un comando con contexto'),
    summary: both(
      'vgrab preserves color and adds the project, Git branch when available, and exact command above the result.',
      'vgrab conserva el color y añade el proyecto, la rama Git cuando existe y el comando exacto sobre el resultado.',
    ),
    code: 'vgrab npm test\nvgrab -e git status\nvgrab --no-context env | sort',
    note: both(
      'Basic vgrab capture is free. Use --no-context whenever arguments, paths, or branch names should stay private.',
      'La captura básica con vgrab es gratis. Usa --no-context cuando los argumentos, rutas o nombres de rama deban mantenerse privados.',
    ),
  },
  {
    id: 'image-frame',
    title: both('Beautify a product screenshot', 'Embellece una captura de producto'),
    summary: both(
      'Local image input can use the same canvas, background, shadow, and browser or device frames as the app.',
      'Una imagen local puede usar el mismo lienzo, fondo, sombra y marcos de navegador o dispositivo que la app.',
    ),
    code: 'vitrine render --image dashboard.png --out showcase.png \\\n  --frame browser --frame-appearance dark \\\n  --window-title app.example.com --background night',
  },
  {
    id: 'recipe-workflow',
    title: both('Reuse one workspace style', 'Reutiliza un estilo del espacio de trabajo'),
    summary: both(
      'Inspect the recipe first, then name it explicitly when rendering. Command-line flags still win.',
      'Inspecciona primero la receta y luego nómbrala al renderizar. Las opciones explícitas siguen teniendo prioridad.',
    ),
    code: 'vitrine recipe validate docs.vitrine-recipe.json\nvitrine recipe show docs.vitrine-recipe.json\nvitrine render README.md --out readme.png \\\n  --recipe docs.vitrine-recipe.json --scale 2',
  },
  {
    id: 'safe-share',
    title: both('Redact before creating sidecars', 'Oculta secretos antes de crear archivos auxiliares'),
    summary: both(
      'Detected secret rows are replaced in the image and every copyable text sidecar.',
      'Las filas detectadas se ocultan en la imagen y se sustituyen en cada archivo de texto auxiliar.',
    ),
    code: 'vitrine render config.swift --out safe.png \\\n  --redact-secrets --sidecars all',
    note: both(
      'A visual --blur-box does not sanitize source text. Use --redact-lines or --redact-secrets for sensitive content.',
      'Un --blur-box visual no limpia el texto fuente. Usa --redact-lines o --redact-secrets cuando haya contenido sensible.',
    ),
  },
  {
    id: 'social-pack',
    title: both('Build a social image pack', 'Crea un paquete para redes'),
    summary: both(
      'One source is rendered at each destination size with stable filenames.',
      'Una fuente se renderiza en cada tamaño con nombres de archivo estables.',
    ),
    code: 'vitrine multi-size launch.swift --out launch-assets \\\n  --presets twitter,linkedin,opengraph \\\n  --recipe launch.vitrine-recipe.json',
  },
  {
    id: 'batch-ci',
    title: both('Make batch generation CI-friendly', 'Prepara lotes confiables para CI'),
    summary: both(
      'Dry-run first, then require at least one input, fail on skipped files, and retain machine-readable evidence.',
      'Simula primero, exige entradas, falla si omite archivos y conserva evidencia legible por máquinas.',
    ),
    code: 'vitrine batch Sources --out docs/cards --recursive \\\n  --include-ext swift,md --dry-run --fail-on-empty\n\nvitrine batch Sources --out docs/cards --recursive \\\n  --include-ext swift,md --fail-on-empty --fail-on-skipped \\\n  --manifest docs/cards/manifest.json \\\n  --skipped-report docs/cards/skipped.json',
  },
  {
    id: 'editor-handoff',
    title: both('Start in Terminal, finish in the editor', 'Empieza en Terminal y termina en el editor'),
    summary: both(
      'Hand the loaded source to Vitrine when a script gets you close but the final image needs manual annotation.',
      'Envía la fuente al editor cuando la automatización te acerca al resultado pero la imagen final necesita anotaciones.',
    ),
    code: 'vitrine render --git-diff main...HEAD --edit',
  },
];

export const cliOptionGroups: CLIOptionGroup[] = [
  {
    id: 'input-options',
    title: both('Input and editor handoff', 'Entrada y envío al editor'),
    intro: both('Choose exactly one source, then optionally narrow or name it.', 'Elige una fuente y, si hace falta, limítala o asígnale un nombre.'),
    options: [
      { flags: '--stdin', description: both('Read source text from standard input.', 'Lee texto desde la entrada estándar.') },
      { flags: '--stdin-name', value: '<name>', description: both('Infer language and default metadata from a filename hint without reading that file.', 'Infiere lenguaje y metadatos desde un nombre sin leer ese archivo.') },
      { flags: '--image', value: '<path>', description: both('Beautify one local image instead of rendering text.', 'Embellece una imagen local en lugar de renderizar texto.') },
      { flags: '--git-diff', value: '<range>', description: both('Load a local revision or range with /usr/bin/git, without a shell or network fetch.', 'Carga una revisión o rango local con /usr/bin/git, sin shell ni descarga de red.') },
      { flags: '--git-staged', description: both('Load only changes staged in the current repository.', 'Carga solo los cambios preparados en el repositorio actual.') },
      { flags: '--git-path', value: '<path>', description: both('Limit a Git source to a literal path; repeat for several paths.', 'Limita una fuente Git a una ruta literal; repítelo para varias rutas.') },
      { flags: '--git-context', value: '<0...100>', description: both('Set unchanged lines around each hunk; the default is 3.', 'Define líneas sin cambios alrededor de cada bloque; el valor predeterminado es 3.') },
      { flags: '-e, --edit', description: both('Open the source in Vitrine instead of writing or copying an image.', 'Abre la fuente en Vitrine en vez de escribir o copiar una imagen.') },
    ],
  },
  {
    id: 'output-options',
    title: both('Output and process control', 'Salida y control del proceso'),
    intro: both('Choose where the result goes and how scripts observe success.', 'Elige el destino y cómo las automatizaciones comprueban el resultado.'),
    options: [
      { flags: '-o, --out', value: '<path>', description: both('Image path, or output folder for multi-size and batch.', 'Ruta de imagen o carpeta para multi-size y batch.') },
      { flags: '--copy', description: both('Copy the rendered image to the macOS clipboard.', 'Copia la imagen al portapapeles de macOS.') },
      { flags: '--format', value: '<png|pdf|heic|avif>', description: both('Select output encoding. A known file extension selects it automatically when omitted.', 'Selecciona la codificación. Una extensión conocida la elige automáticamente.') },
      { flags: '--profile', value: '<srgb|p3>', description: both('Select the PNG color profile; sRGB is the default.', 'Selecciona el perfil de color PNG; sRGB es el predeterminado.') },
      { flags: '--scale', value: '<1|2|3>', description: both('Multiply logical canvas dimensions into final pixels.', 'Multiplica las dimensiones lógicas para obtener los píxeles finales.') },
      { flags: '--preset', value: '<id>', description: both('Use one destination size from vitrine list presets.', 'Usa un tamaño de destino de la lista de ajustes de Vitrine.') },
      { flags: '--canvas-size', value: '<WxH>', description: both('Set an exact 64–2048 point logical canvas.', 'Define un lienzo lógico exacto de 64–2048 puntos.') },
      { flags: '-q, --quiet', description: both('Hide success output while keeping errors visible.', 'Oculta la salida de éxito y conserva los errores.') },
      { flags: '--json', description: both('Emit structured success output for render, multi-size, batch, list, recipe, or version.', 'Emite resultados estructurados para render, multi-size, batch, list, recipe o version.') },
      { flags: '-v, --version', description: both('Print the installed marketing version and build number.', 'Muestra la versión instalada y el número de compilación.') },
      { flags: '--no-overwrite, --no-clobber', description: both('Refuse to replace existing image or sidecar outputs.', 'Evita reemplazar imágenes o archivos auxiliares existentes.') },
      { flags: '-h, --help', description: both('Print local usage for the installed build.', 'Muestra la ayuda local de la compilación instalada.') },
    ],
  },
  {
    id: 'style-options',
    title: both('Code and presentation style', 'Código y estilo visual'),
    intro: both('Start from defaults, a recipe, or a built-in style preset; explicit flags apply last.', 'Empieza con valores predeterminados, una receta o un ajuste integrado; las opciones explícitas se aplican al final.'),
    options: [
      { flags: '--theme', value: '<id>', description: both('Syntax theme from vitrine list themes.', 'Tema de sintaxis de vitrine list themes.') },
      { flags: '--language', value: '<id>', description: both('Force a language instead of inferring it.', 'Fuerza un lenguaje en vez de inferirlo.') },
      { flags: '--style-preset', value: '<id>', description: both('Apply one immutable built-in presentation preset.', 'Aplica un ajuste visual integrado e inmutable.') },
      { flags: '--recipe', value: '<path>', description: both('Load one explicitly named portable workspace recipe.', 'Carga una receta portátil de espacio de trabajo nombrada explícitamente.') },
      { flags: '--font', value: '<family>', description: both('Code font family from vitrine list fonts.', 'Familia tipográfica de vitrine list fonts.') },
      { flags: '--font-ligatures, --no-font-ligatures', description: both('Enable or disable programming ligatures.', 'Activa o desactiva ligaduras de programación.') },
      { flags: '--font-size', value: '<10...20>', description: both('Code font size in points.', 'Tamaño de la fuente en puntos.') },
      { flags: '--padding', value: '<16...64>', description: both('Canvas padding in points.', 'Relleno del lienzo en puntos.') },
      { flags: '--corner-radius', value: '<0...48>', description: both('Code-card corner radius.', 'Radio de las esquinas de la tarjeta.') },
      { flags: '--shadow-radius', value: '<0...40>', description: both('Drop-shadow blur radius.', 'Radio de desenfoque de la sombra.') },
      { flags: '--terminal-width', value: '<1...1000>', description: both('Pin terminal reconstruction width; vgrab -w sets this automatically.', 'Fija el ancho de reconstrucción; vgrab -w lo define automáticamente.') },
      { flags: '--wrap-columns', value: '<40...200>', description: both('Soft-wrap long code lines at a stable column.', 'Ajusta líneas largas en una columna estable.') },
      { flags: '--format-code, --tidy', description: both('Apply Vitrine’s local indentation tidy before rendering.', 'Aplica el ajuste local de indentación antes de renderizar.') },
      { flags: '--line-numbers, --no-line-numbers', description: both('Show or hide the line-number gutter.', 'Muestra u oculta los números de línea.') },
      { flags: '--chrome, --no-chrome', description: both('Show or hide rendered window chrome.', 'Muestra u oculta el marco de ventana.') },
      { flags: '--shadow, --no-shadow', description: both('Show or hide the rendered drop shadow.', 'Muestra u oculta la sombra renderizada.') },
    ],
  },
  {
    id: 'background-options',
    title: both('Canvas and background', 'Lienzo y fondo'),
    intro: both('Use one background source; image modifiers require --background-image.', 'Usa una fuente de fondo; los modificadores de imagen requieren --background-image.'),
    options: [
      { flags: '--transparent', description: both('Render a real alpha background.', 'Renderiza un fondo con transparencia real.') },
      { flags: '--background', value: '<id>', description: both('Built-in gradient from vitrine list backgrounds.', 'Degradado integrado de vitrine list backgrounds.') },
      { flags: '--background-color', value: '<hex>', description: both('Solid RGB or RGBA color.', 'Color sólido RGB o RGBA.') },
      { flags: '--background-gradient', value: '<hex,hex,...>', description: both('Custom gradient with at least two colors.', 'Degradado personalizado con al menos dos colores.') },
      { flags: '--background-angle', value: '<0...360>', description: both('Direction for a custom gradient; default 135.', 'Dirección de un degradado personalizado; valor predeterminado 135.') },
      { flags: '--background-image', value: '<path>', description: both('Use one local image as the canvas background.', 'Usa una imagen local como fondo del lienzo.') },
      { flags: '--background-fit', value: '<fill|fit>', description: both('Crop edge-to-edge or keep the whole background image.', 'Recorta para llenar o conserva la imagen completa.') },
      { flags: '--background-blur', value: '<0...40>', description: both('Blur a background image locally.', 'Desenfoca localmente una imagen de fondo.') },
      { flags: '--background-dimming', value: '<0...1>', description: both('Apply a normalized dark overlay to a background image.', 'Aplica una capa oscura normalizada sobre la imagen.') },
    ],
  },
  {
    id: 'frame-options',
    title: both('Local image framing', 'Marcos para imágenes locales'),
    intro: both('These controls apply when --image is the input.', 'Estos controles se aplican cuando --image es la entrada.'),
    options: [
      { flags: '--frame', value: '<id>', description: both('Use none, macos-window, browser, macbook, or iphone.', 'Usa none, macos-window, browser, macbook o iphone.') },
      { flags: '--frame-appearance', value: '<auto|light|dark>', description: both('Control chrome appearance for a selected frame.', 'Controla la apariencia de un marco seleccionado.') },
    ],
  },
  {
    id: 'metadata-options',
    title: both('Titles and metadata', 'Títulos y metadatos'),
    intro: both('Add enough context for the image to make sense after it leaves your repository.', 'Añade contexto para que la imagen se entienda fuera del repositorio.'),
    options: [
      { flags: '--window-title', value: '<text>', description: both('Title in rendered window or browser chrome.', 'Título en el marco de ventana o navegador.') },
      { flags: '--filename', value: '<text>', description: both('Filename chip in the metadata header.', 'Etiqueta de archivo en la cabecera.') },
      { flags: '--title', value: '<text>', description: both('Primary metadata title.', 'Título principal de metadatos.') },
      { flags: '--caption', value: '<text>', description: both('Supporting caption below the title.', 'Texto de apoyo bajo el título.') },
      { flags: '--language-badge, --no-language-badge', description: both('Show or hide the detected language badge.', 'Muestra u oculta la etiqueta del lenguaje.') },
    ],
  },
  {
    id: 'annotation-options',
    title: both('Annotations, focus, and redaction', 'Anotaciones, enfoque y censura'),
    intro: both('Coordinates are normalized from 0 to 1 so scripted marks scale with the canvas.', 'Las coordenadas de 0 a 1 permiten que las marcas escalen con el lienzo.'),
    options: [
      { flags: '--callout', value: '<text>', description: both('Add one text callout.', 'Añade una llamada de texto.') },
      { flags: '--callout-x, --callout-y', value: '<0...1>', description: both('Set the callout anchor; provide both together.', 'Define el ancla; proporciona ambas coordenadas.') },
      { flags: '--callout-color', value: '<hex>', description: both('Callout text color.', 'Color del texto de la llamada.') },
      { flags: '--callout-size', value: '<2...28>', description: both('Callout visual weight.', 'Peso visual de la llamada.') },
      { flags: '--counter', value: '<1...99>', description: both('Add one numbered badge.', 'Añade una insignia numerada.') },
      { flags: '--counter-x, --counter-y', value: '<0...1>', description: both('Set the counter center; provide both together.', 'Define el centro; proporciona ambas coordenadas.') },
      { flags: '--counter-color', value: '<hex>', description: both('Counter fill color.', 'Color de relleno del contador.') },
      { flags: '--counter-size', value: '<2...28>', description: both('Counter visual weight.', 'Peso visual del contador.') },
      { flags: '--arrow', value: '<x1,y1,x2,y2>', description: both('Draw a repeatable arrow from tail to head.', 'Dibuja una flecha repetible desde la cola a la punta.') },
      { flags: '--arrow-color, --arrow-size', value: '<hex> / <2...28>', description: both('Shared color and weight for every arrow.', 'Color y peso compartidos por todas las flechas.') },
      { flags: '--line', value: '<x1,y1,x2,y2>', description: both('Draw a repeatable straight line.', 'Dibuja una línea recta repetible.') },
      { flags: '--line-color, --line-size', value: '<hex> / <2...28>', description: both('Shared color and weight for every line.', 'Color y peso compartidos por todas las líneas.') },
      { flags: '--rectangle', value: '<x1,y1,x2,y2>', description: both('Outline a repeatable region.', 'Contornea una región repetible.') },
      { flags: '--rectangle-color, --rectangle-size', value: '<hex> / <2...28>', description: both('Shared color and weight for every rectangle.', 'Color y peso compartidos por todos los rectángulos.') },
      { flags: '--highlighter', value: '<x1,y1,x2,y2>', description: both('Highlight a repeatable region.', 'Resalta una región repetible.') },
      { flags: '--highlighter-color', value: '<hex>', description: both('Shared marker color.', 'Color compartido del resaltador.') },
      { flags: '--blur-box', value: '<x1,y1,x2,y2>', description: both('Visually blur a region; this does not sanitize sidecars.', 'Desenfoca visualmente una región; no limpia los archivos auxiliares.') },
      { flags: '--highlight-lines', value: '<spec>', description: both('Highlight 1-based rows such as 3,7-9,12.', 'Resalta filas desde 1, como 3,7-9,12.') },
      { flags: '--redact-lines', value: '<spec>', description: both('Redact rows in the image and replace them in sidecars.', 'Oculta filas en la imagen y las sustituye en los archivos auxiliares.') },
      { flags: '--redact-secrets', description: both('Scan for likely secrets and redact matching rows.', 'Busca secretos probables y oculta las filas correspondientes.') },
      { flags: '--focus-lines, --no-focus-lines', description: both('Dim or restore rows outside the highlight.', 'Atenúa o restaura las filas fuera del resaltado.') },
      { flags: '--diff-bands, --no-diff-bands', description: both('Show or hide GitHub-style added and removed bands.', 'Muestra u oculta bandas de cambios al estilo GitHub.') },
    ],
  },
  {
    id: 'watermark-options',
    title: both('Brand watermark', 'Marca de agua'),
    intro: both('Add text, a local logo, or both through the same render-core overlay as Brand Kit.', 'Añade texto, un logo local o ambos con la misma capa de Brand Kit.'),
    options: [
      { flags: '--watermark', value: '<text>', description: both('Watermark text.', 'Texto de la marca de agua.') },
      { flags: '--watermark-logo', value: '<path>', description: both('Local logo image.', 'Imagen de logo local.') },
      { flags: '--watermark-color', value: '<hex>', description: both('Text tint; requires watermark text.', 'Color del texto; requiere texto.') },
      { flags: '--watermark-position', value: '<corner|free>', description: both('Use a named corner or free placement.', 'Usa una esquina nombrada o posición libre.') },
      { flags: '--watermark-x, --watermark-y', value: '<0...1>', description: both('Normalized center for free placement; provide both.', 'Centro normalizado para posición libre; proporciona ambas.') },
    ],
  },
  {
    id: 'batch-options',
    title: both('Multi-size and batch automation', 'Automatización multi-size y batch'),
    intro: both('Use stable destination sets and make partial work visible to CI.', 'Usa destinos estables y haz visible cualquier resultado parcial en CI.'),
    options: [
      { flags: '--presets', value: '<ids|all>', description: both('Multi-size destination ids, comma-separated; all is the default.', 'Destinos de multi-size separados por comas; all es el valor predeterminado.') },
      { flags: '--recursive', description: both('Walk nested batch folders and preserve relative paths.', 'Recorre subcarpetas y conserva rutas relativas.') },
      { flags: '--dry-run', description: both('Discover and load batch inputs without writing artifacts.', 'Descubre y carga entradas sin escribir artefactos.') },
      { flags: '--include-ext', value: '<list>', description: both('Only consider comma-separated extensions.', 'Considera solo las extensiones indicadas.') },
      { flags: '--exclude-ext', value: '<list>', description: both('Ignore comma-separated extensions before loading.', 'Ignora extensiones antes de cargar archivos.') },
      { flags: '--fail-on-empty', description: both('Exit non-zero when no file would render.', 'Falla cuando ningún archivo se renderizaría.') },
      { flags: '--fail-on-skipped', description: both('Exit non-zero after completing when any input was skipped.', 'Falla al terminar si alguna entrada fue omitida.') },
      { flags: '--skipped-report', value: '<json>', description: both('Write a machine-readable skipped-file report.', 'Escribe un informe de archivos omitidos.') },
      { flags: '--manifest', value: '<json>', description: both('Write successful or planned output paths and dimensions.', 'Escribe rutas y dimensiones de resultados reales o planeados.') },
    ],
  },
  {
    id: 'sidecar-options',
    title: both('Accessible source sidecars', 'Archivos auxiliares accesibles'),
    intro: both('Ship selectable source next to the image without changing the rendered pixels.', 'Entrega texto seleccionable junto a la imagen sin cambiar sus píxeles.'),
    options: [
      { flags: '--text-sidecar', description: both('Write a plain-text .txt file.', 'Escribe un archivo .txt de texto plano.') },
      { flags: '--markdown-sidecar', description: both('Write a Markdown image reference and fenced source.', 'Escribe una referencia Markdown y la fuente en un bloque.') },
      { flags: '--html-sidecar', description: both('Write an HTML image embed and escaped source.', 'Escribe un fragmento HTML con la imagen y la fuente escapada.') },
      { flags: '--sidecars', value: '<text,markdown,html|all>', description: both('Enable several sidecars in one option.', 'Activa varios archivos auxiliares con una opción.') },
    ],
  },
];
