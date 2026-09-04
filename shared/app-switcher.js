export const ECOSYSTEM_APPS = Object.freeze([
  Object.freeze({ id: 'daymark', name: 'Daymark', description: 'Tasks, goals, Scheduler, and Calendar', path: '/tracker/', mark: '<svg viewBox="0 0 32 32"><path d="M5 23h22M8 19h16M11 15h10"/><circle cx="16" cy="10" r="3.5"/></svg>' }),
  Object.freeze({ id: 'fairway', name: 'Fairway', description: 'Golf rounds, courses, scoring, and statistics', path: '/golf/', mark: '<svg viewBox="0 0 32 32"><path d="M8 27c5-7 9-10 13-10 3.5 0 5 1 7-2v12H8Z" class="mark-fill"/><path d="M12 24V6m0 1h10l-3 3 3 3H12"/><circle cx="12" cy="25" r="1.7"/></svg>' }),
  Object.freeze({ id: 'money', name: 'Money', description: 'Budgeting, Earnings, savings, and retirement', path: '/money/', mark: '<svg viewBox="0 0 32 32"><path d="M5 25h22M8 22V13m6 9V8m6 14V15m6 7V10"/><path d="m7 10 7-5 6 6 6-7" class="mark-accent"/></svg>' })
]);

const ACCOUNT = Object.freeze({ id: 'account', name: 'Account', description: 'Profile, password, and shared session', path: '/account/', mark: '<svg viewBox="0 0 32 32"><circle cx="16" cy="11" r="5"/><path d="M6 27c1.2-6 4.5-9 10-9s8.8 3 10 9"/></svg>' });
let instanceCount = 0;

function accountPath() {
  const currentPath = `${location.pathname}${location.hash || ''}`;
  return `${ACCOUNT.path}?returnTo=${encodeURIComponent(currentPath)}`;
}

function createAppLink(app, currentId) {
  const link = document.createElement('a');
  link.className = 'ecosystem-link';
  link.href = app.path;
  link.setAttribute('role', 'menuitem');
  link.dataset.ecosystemApp = app.id;
  if (app.id === currentId) {
    link.classList.add('current');
    link.setAttribute('aria-current', 'page');
  }
  link.innerHTML = `<span class="ecosystem-icon ecosystem-icon-${app.id}" aria-hidden="true">${app.mark}</span><span class="ecosystem-copy"><strong>${app.name}</strong><small>${app.description}</small></span>${app.id === currentId ? '<span class="ecosystem-current" aria-hidden="true">✓</span><span class="sr-only">Current application</span>' : ''}`;
  return link;
}

function mountSwitcher(host) {
  const currentId = host.dataset.appSwitcher;
  const currentApp = [...ECOSYSTEM_APPS, ACCOUNT].find((app) => app.id === currentId);
  if (!currentApp) return;

  instanceCount += 1;
  const panelId = `ecosystem-menu-${instanceCount}`;
  host.classList.add('ecosystem-switcher');

  const trigger = document.createElement('button');
  trigger.className = 'ecosystem-trigger';
  trigger.type = 'button';
  trigger.setAttribute('aria-haspopup', 'menu');
  trigger.setAttribute('aria-expanded', 'false');
  trigger.setAttribute('aria-controls', panelId);
  trigger.setAttribute('aria-label', `Open app switcher. Current application: ${currentApp.name}`);
  trigger.innerHTML = '<span class="ecosystem-grid" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></span><span class="ecosystem-trigger-label">Apps</span>';

  const panel = document.createElement('div');
  panel.className = 'ecosystem-menu';
  panel.id = panelId;
  panel.setAttribute('role', 'menu');
  panel.setAttribute('aria-label', 'Applications');
  panel.hidden = true;

  const heading = document.createElement('div');
  heading.className = 'ecosystem-heading';
  heading.innerHTML = '<span>Applications</span><small>One account, separate apps</small>';
  panel.append(heading);
  ECOSYSTEM_APPS.forEach((app) => panel.append(createAppLink(app, currentId)));

  const divider = document.createElement('div');
  divider.className = 'ecosystem-divider';
  divider.setAttribute('role', 'separator');
  panel.append(divider);

  const account = createAppLink({ ...ACCOUNT, path: currentId === 'account' ? ACCOUNT.path : accountPath() }, currentId);
  account.classList.add('account-link');
  panel.append(account);
  host.append(trigger, panel);

  const menuItems = () => [...panel.querySelectorAll('[role="menuitem"]')];
  const close = (restoreFocus = false) => {
    panel.hidden = true;
    trigger.setAttribute('aria-expanded', 'false');
    host.classList.remove('open');
    if (restoreFocus) trigger.focus();
  };
  const open = (focusFirst = false) => {
    panel.hidden = false;
    trigger.setAttribute('aria-expanded', 'true');
    host.classList.add('open');
    if (focusFirst) menuItems()[0]?.focus();
  };

  trigger.addEventListener('click', () => panel.hidden ? open() : close());
  trigger.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      open(true);
    }
    if (event.key === 'Escape') close(true);
  });
  panel.addEventListener('keydown', (event) => {
    const items = menuItems();
    const index = items.indexOf(document.activeElement);
    if (event.key === 'Escape') {
      event.preventDefault();
      close(true);
    } else if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) {
      event.preventDefault();
      const next = event.key === 'Home' ? 0 : event.key === 'End' ? items.length - 1 : event.key === 'ArrowDown' ? (index + 1) % items.length : (index - 1 + items.length) % items.length;
      items[next].focus();
    } else if (event.key === 'Tab') {
      close();
    }
  });
  document.addEventListener('pointerdown', (event) => {
    if (!host.contains(event.target)) close();
  });
}

document.querySelectorAll('[data-app-switcher]').forEach(mountSwitcher);
