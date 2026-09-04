function mountAppNavigation(nav) {
  const trigger = document.querySelector(`[aria-controls="${nav.id}"]`);
  if (!trigger) return;
  const items = () => [...nav.querySelectorAll('button:not([disabled]),a[href]')];
  const close = (restoreFocus = false) => {
    nav.classList.remove('open');
    trigger.setAttribute('aria-expanded', 'false');
    if (restoreFocus) trigger.focus({ preventScroll:true });
  };
  const open = (focusFirst = false) => {
    document.dispatchEvent(new CustomEvent('ecosystem-utility-open', { detail:{ host:nav } }));
    nav.classList.add('open');
    trigger.setAttribute('aria-expanded', 'true');
    if (focusFirst) items()[0]?.focus({ preventScroll:true });
  };

  trigger.addEventListener('click', () => nav.classList.contains('open') ? close() : open());
  trigger.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowDown') { event.preventDefault(); open(true); }
    else if (event.key === 'Escape') { event.preventDefault(); close(true); }
  });
  nav.addEventListener('click', (event) => { if (event.target.closest('button,a[href]')) close(); });
  nav.addEventListener('keydown', (event) => {
    const menuItems = items();
    const index = menuItems.indexOf(document.activeElement);
    if (event.key === 'Escape') { event.preventDefault(); close(true); }
    else if (['ArrowDown','ArrowUp','Home','End'].includes(event.key)) {
      event.preventDefault();
      const next = event.key === 'Home' ? 0 : event.key === 'End' ? menuItems.length - 1 : event.key === 'ArrowDown' ? (index + 1) % menuItems.length : (index - 1 + menuItems.length) % menuItems.length;
      menuItems[next]?.focus({ preventScroll:true });
    } else if (event.key === 'Tab') close();
  });
  document.addEventListener('pointerdown', (event) => {
    if (!nav.contains(event.target) && event.target !== trigger && !trigger.contains(event.target)) close();
  });
  document.addEventListener('ecosystem-utility-open', (event) => { if (event.detail?.host !== nav) close(); });
  matchMedia('(min-width:821px)').addEventListener('change', (event) => { if (event.matches) close(); });
}

document.querySelectorAll('[data-app-nav]').forEach(mountAppNavigation);
