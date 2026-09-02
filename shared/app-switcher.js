export const ECOSYSTEM_APPS = Object.freeze([
  Object.freeze({ id: 'daymark', name: 'Daymark', description: 'Tasks, goals, Scheduler, and Calendar', path: '/tracker/', icon: 'D' }),
  Object.freeze({ id: 'fairway', name: 'Fairway', description: 'Golf rounds, courses, scoring, and statistics', path: '/golf/', icon: 'F' }),
  Object.freeze({ id: 'money', name: 'Money', description: 'Budgeting, Earnings, savings, and retirement', path: '/money/', icon: 'M' })
]);

const ACCOUNT = Object.freeze({ id: 'account', name: 'Account', description: 'Profile, password, and shared session', path: '/account/', icon: '@' });
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
  link.innerHTML = `<span class="ecosystem-icon" aria-hidden="true">${app.icon}</span><span class="ecosystem-copy"><strong>${app.name}</strong><small>${app.description}</small></span>${app.id === currentId ? '<span class="ecosystem-current" aria-hidden="true">✓</span><span class="sr-only">Current application</span>' : ''}`;
  return link;
}

function mountSwitcher(host) {
  const currentId = host.dataset.appSwitcher;
  if (!ECOSYSTEM_APPS.some((app) => app.id === currentId)) return;

  instanceCount += 1;
  const panelId = `ecosystem-menu-${instanceCount}`;
  host.classList.add('ecosystem-switcher');

  const trigger = document.createElement('button');
  trigger.className = 'ecosystem-trigger';
  trigger.type = 'button';
  trigger.setAttribute('aria-haspopup', 'menu');
  trigger.setAttribute('aria-expanded', 'false');
  trigger.setAttribute('aria-controls', panelId);
  trigger.setAttribute('aria-label', `Open app switcher. Current application: ${ECOSYSTEM_APPS.find((app) => app.id === currentId).name}`);
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

  const account = createAppLink({ ...ACCOUNT, path: accountPath() }, currentId);
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
  host.addEventListener('focusout', () => {
    queueMicrotask(() => { if (!host.contains(document.activeElement)) close(); });
  });
}

document.querySelectorAll('[data-app-switcher]').forEach(mountSwitcher);
