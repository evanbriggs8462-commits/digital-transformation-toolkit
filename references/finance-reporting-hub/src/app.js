(() => {
  const catalog = JSON.parse(document.getElementById('catalog-data').textContent);
  const view = document.getElementById('reports');
  const search = document.getElementById('search');
  const state = { query: '', topic: 'All', layout: 'tiles' };
  const make = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  };
  document.title = catalog.title;
  document.getElementById('hub-title').textContent = catalog.title;
  document.getElementById('hub-intro').textContent = catalog.intro;
  document.getElementById('preview-note').hidden = catalog.reports.some(r => r.url);
  const topics = ['All', ...new Set(catalog.filters || catalog.reports.map(r => r.category))];
  const filters = document.getElementById('filters');
  topics.forEach(topic => {
    const button = make('button', '', topic === 'All' ? 'All reports' : topic);
    button.type = 'button'; button.dataset.topic = topic;
    button.addEventListener('click', () => { state.topic = topic; render(); });
    filters.append(button);
  });
  function entry(report, heading = 'h2') {
    const li = make('li', 'entry'), article = make('article', 'report');
    article.append(make('p', 'category', report.category), make(heading, '', report.title), make('p', 'summary', report.summary));
    if (report.keyTabs.length) article.append(make('p', 'details', `Key tabs: ${report.keyTabs.slice(0,3).join(' · ')}`));
    else if (report.topics.length) article.append(make('p', 'details', `Topics: ${report.topics.slice(0,3).join(' · ')}`));
    if (report.url) {
      // Recheck at the DOM boundary even though the build validates destinations.
      try {
        const url = new URL(report.url);
        if (url.protocol === 'https:' && !url.username && !url.password) {
          const link = make('a', 'open', 'Open report ↗'); link.href = url.href;
          link.target = '_blank'; link.rel = 'noopener noreferrer';
          link.setAttribute('aria-label', `Open ${report.title} in a new tab`); article.append(link);
        }
      } catch { /* Invalid destinations do not become clickable controls. */ }
    }
    li.append(article); return li;
  }
  function render() {
    const query = state.query.trim().toLowerCase();
    const shown = catalog.reports.filter(r => (state.topic === 'All' || r.category === state.topic || r.topics.includes(state.topic)) && [r.title,r.summary,r.category,...r.topics,...r.keyTabs].join(' ').toLowerCase().includes(query));
    view.dataset.layout = state.layout; view.replaceChildren();
    if (state.layout === 'chapters') {
      for (const category of new Set(shown.map(r => r.category))) {
        const section = make('section','chapter'), list = make('ul','collection');
        section.append(make('h2','',category));
        shown.filter(r => r.category === category).forEach(r => list.append(entry(r,'h3')));
        section.append(list); view.append(section);
      }
    } else {
      const list = make('ul','collection'); shown.forEach(r => list.append(entry(r))); view.append(list);
    }
    document.getElementById('count').textContent = `${shown.length} of ${catalog.reports.length} reports`;
    document.getElementById('empty').hidden = shown.length !== 0;
    filters.querySelectorAll('button').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.topic === state.topic)));
  }
  search.addEventListener('input', () => { state.query = search.value; render(); });
  document.getElementById('layout').addEventListener('change', event => { state.layout = event.target.value; render(); });
  document.getElementById('reset').addEventListener('click', () => { state.query = ''; state.topic = 'All'; search.value = ''; render(); });
  render();
})();
