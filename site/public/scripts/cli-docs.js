(function () {
  function getPreference(key) {
    try { return localStorage.getItem(key); } catch (_) { return null; }
  }

  function setPreference(key, value) {
    try { localStorage.setItem(key, value); } catch (_) { /* Storage is optional. */ }
  }

  var light = document.getElementById('set-light');
  var dark = document.getElementById('set-dark');
  var appearanceKey = 'vitrine-landing-b-appearance';

  function applyAppearance(mode) {
    var isDark = mode === 'dark';
    document.body.classList.toggle('vitrine-dark', isDark);
    light.classList.toggle('active', !isDark);
    dark.classList.toggle('active', isDark);
    light.setAttribute('aria-pressed', String(!isDark));
    dark.setAttribute('aria-pressed', String(isDark));
  }

  applyAppearance(getPreference(appearanceKey) || 'light');
  light.addEventListener('click', function () { setPreference(appearanceKey, 'light'); applyAppearance('light'); });
  dark.addEventListener('click', function () { setPreference(appearanceKey, 'dark'); applyAppearance('dark'); });

  ['set-en', 'set-es'].forEach(function (id) {
    var control = document.getElementById(id);
    control.addEventListener('click', function () { window.location.assign(control.dataset.target); });
  });

  document.querySelectorAll('.cli-copy').forEach(function (button) {
    button.addEventListener('click', function () {
      var code = button.parentElement.querySelector('code').textContent;
      navigator.clipboard.writeText(code).then(function () {
        button.textContent = button.dataset.copiedLabel;
        button.classList.add('copied');
        window.setTimeout(function () {
          button.textContent = button.dataset.copyLabel;
          button.classList.remove('copied');
        }, 1600);
      });
    });
  });

  var search = document.getElementById('cli-search');
  var cards = Array.from(document.querySelectorAll('[data-search-card]'));
  var sections = Array.from(document.querySelectorAll('[data-search-section]'));
  var count = document.getElementById('cli-result-count');
  var empty = document.getElementById('cli-no-results');

  function normalize(value) {
    return value.toLocaleLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  }

  function filter() {
    var query = normalize(search.value.trim());
    var terms = query.split(/\s+/).filter(Boolean);
    var visible = 0;

    cards.forEach(function (card) {
      var haystack = normalize(card.dataset.search || card.textContent);
      var matches = terms.every(function (term) { return haystack.includes(term); });
      card.hidden = !matches;
      if (matches) {
        visible += 1;
        if (query && card.tagName === 'DETAILS') card.open = true;
      }
    });

    sections.forEach(function (section) {
      section.hidden = !section.querySelector('[data-search-card]:not([hidden])');
    });

    count.textContent = String(visible);
    empty.hidden = visible !== 0;
  }

  search.addEventListener('input', filter);
  document.addEventListener('keydown', function (event) {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
      event.preventDefault();
      search.focus();
      search.select();
    }
    if (event.key === 'Escape' && document.activeElement === search) {
      search.value = '';
      filter();
      search.blur();
    }
  });
  filter();
})();
