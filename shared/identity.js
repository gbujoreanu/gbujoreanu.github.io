export function profileInitials(displayName = '', handle = '') {
  const parts = String(displayName).trim().split(/\s+/).filter(Boolean);
  if (parts.length) return `${parts[0][0]}${parts.length > 1 ? parts.at(-1)[0] : ''}`.toUpperCase();
  return String(handle || 'A').replace(/^@/, '').slice(0, 2).toUpperCase() || 'A';
}

export async function loadEcosystemIdentity(client, user) {
  if (!client || !user?.id) return null;
  const fields = 'id,display_name,handle,avatar_url,avatar_path,bio,discoverable';
  let result = await client.from('profiles').select(fields).eq('id', user.id).maybeSingle();
  if (result.error && /avatar_path|column/i.test(String(result.error.message || ''))) {
    result = await client.from('profiles').select('id,display_name,handle,avatar_url,bio,discoverable').eq('id', user.id).maybeSingle();
  }
  if (result.error) throw result.error;
  const profile = { id:user.id, display_name:'', handle:'', avatar_url:null, avatar_path:null, bio:'', discoverable:false, ...(result.data || {}) };
  let signedAvatarUrl = null;
  if (profile.avatar_path) {
    const signed = await client.storage.from('avatars').createSignedUrl(profile.avatar_path, 3600);
    if (!signed.error) signedAvatarUrl = signed.data?.signedUrl || null;
  }
  return { ...profile, signedAvatarUrl };
}

export function renderIdentityAvatar(element, identity, fallbackUser = null) {
  if (!element) return;
  const initials = profileInitials(identity?.display_name, identity?.handle || fallbackUser?.email?.split('@')[0]);
  element.replaceChildren();
  element.classList.toggle('has-image', Boolean(identity?.signedAvatarUrl));
  if (identity?.signedAvatarUrl) {
    const image = document.createElement('img');
    image.src = identity.signedAvatarUrl;
    image.alt = '';
    image.decoding = 'async';
    image.referrerPolicy = 'no-referrer';
    element.append(image);
  } else element.textContent = initials;
}

export async function mountEcosystemIdentity({ client, user, host = document.querySelector('[data-ecosystem-identity]') }) {
  if (!host || !user) return null;
  try {
    const identity = await loadEcosystemIdentity(client, user);
    renderIdentityAvatar(host.querySelector('[data-identity-avatar]'), identity, user);
    const label = host.querySelector('[data-identity-label]');
    if (label) label.textContent = identity?.display_name || (identity?.handle ? `@${identity.handle}` : 'Account');
    host.setAttribute('aria-label', `Open Account and Profile${identity?.display_name ? ` for ${identity.display_name}` : ''}`);
    return identity;
  } catch (error) {
    console.warn('Ecosystem identity could not be loaded.', error?.code || error?.message || 'unknown error');
    renderIdentityAvatar(host.querySelector('[data-identity-avatar]'), null, user);
    return null;
  }
}

let profileMenuCount = 0;

function accountDestination(section = '') {
  const returnTo = ['/tracker/', '/golf/', '/money/'].includes(location.pathname) ? location.pathname : '/';
  return `/account/?returnTo=${encodeURIComponent(returnTo)}${section ? `#${section}` : ''}`;
}

function profileMenuIcon(path) {
  return `<svg viewBox="0 0 24 24" aria-hidden="true">${path}</svg>`;
}

export async function mountEcosystemProfileMenu({ client, user, appId, onSettings, onSignOut, host = document.querySelector('[data-ecosystem-profile]') }) {
  if (!host || !user || host.dataset.profileMounted === 'true') return null;
  host.dataset.profileMounted = 'true';
  host.dataset.ecosystemProfile = appId || host.dataset.ecosystemProfile || '';
  host.classList.add('ecosystem-profile');

  let identity = null;
  try { identity = await loadEcosystemIdentity(client, user); }
  catch (error) { console.warn('Ecosystem profile menu could not load the profile.', error?.code || error?.message || 'unknown error'); }

  profileMenuCount += 1;
  const panelId = `ecosystem-profile-menu-${profileMenuCount}`;
  const trigger = document.createElement('button');
  trigger.className = 'ecosystem-profile-trigger';
  trigger.type = 'button';
  trigger.dataset.profileTrigger = '';
  trigger.setAttribute('aria-haspopup', 'menu');
  trigger.setAttribute('aria-expanded', 'false');
  trigger.setAttribute('aria-controls', panelId);
  trigger.setAttribute('aria-label', `Open Profile menu${identity?.display_name ? ` for ${identity.display_name}` : ''}`);
  trigger.innerHTML = '<span class="identity-avatar" data-identity-avatar aria-hidden="true"></span><span class="ecosystem-profile-label">Profile</span><svg class="ecosystem-profile-chevron" viewBox="0 0 16 16" aria-hidden="true"><path d="m4 6 4 4 4-4"/></svg>';
  renderIdentityAvatar(trigger.querySelector('[data-identity-avatar]'), identity, user);

  const panel = document.createElement('div');
  panel.className = 'ecosystem-profile-menu';
  panel.id = panelId;
  panel.hidden = true;
  panel.setAttribute('role', 'menu');
  panel.setAttribute('aria-label', 'Profile and account');

  const identityBlock = document.createElement('div');
  identityBlock.className = 'ecosystem-profile-summary';
  identityBlock.innerHTML = '<span class="identity-avatar profile-summary-avatar" data-profile-summary-avatar aria-hidden="true"></span><span><strong></strong><small></small></span>';
  renderIdentityAvatar(identityBlock.querySelector('[data-profile-summary-avatar]'), identity, user);
  identityBlock.querySelector('strong').textContent = identity?.display_name || (identity?.handle ? `@${identity.handle}` : 'Your profile');
  identityBlock.querySelector('small').textContent = identity?.handle ? `@${identity.handle}` : 'Shared ecosystem identity';
  panel.append(identityBlock);

  const profileLink = document.createElement('a');
  profileLink.className = 'ecosystem-profile-action';
  profileLink.href = accountDestination('profileName');
  profileLink.setAttribute('role', 'menuitem');
  profileLink.innerHTML = `${profileMenuIcon('<circle cx="12" cy="8" r="4"/><path d="M4 21c.8-4 3.5-6 8-6s7.2 2 8 6"/>')}<span><strong>Profile</strong><small>Name, handle, avatar, and bio</small></span>`;

  const settingsButton = document.createElement('button');
  settingsButton.className = 'ecosystem-profile-action';
  settingsButton.type = 'button';
  settingsButton.setAttribute('role', 'menuitem');
  settingsButton.dataset.profileSettings = '';
  settingsButton.innerHTML = `${profileMenuIcon('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1-2.8 2.8-.1-.1a1.7 1.7 0 0 0-1.9-.3A1.7 1.7 0 0 0 14 21v.2h-4V21a1.7 1.7 0 0 0-1-1.6 1.7 1.7 0 0 0-1.9.3l-.1.1L4.2 17l.1-.1a1.7 1.7 0 0 0 .3-1.9A1.7 1.7 0 0 0 3 14H2.8v-4H3a1.7 1.7 0 0 0 1.6-1 1.7 1.7 0 0 0-.3-1.9L4.2 7 7 4.2l.1.1A1.7 1.7 0 0 0 9 4.6 1.7 1.7 0 0 0 10 3v-.2h4V3a1.7 1.7 0 0 0 1 1.6 1.7 1.7 0 0 0 1.9-.3l.1-.1L19.8 7l-.1.1a1.7 1.7 0 0 0-.3 1.9A1.7 1.7 0 0 0 21 10h.2v4H21a1.7 1.7 0 0 0-1.6 1Z"/>')}<span><strong>Settings</strong><small>${appId ? `${appId[0].toUpperCase()}${appId.slice(1)}` : 'App'} preferences</small></span>`;

  const securityLink = document.createElement('a');
  securityLink.className = 'ecosystem-profile-action';
  securityLink.href = accountDestination('securityTitle');
  securityLink.setAttribute('role', 'menuitem');
  securityLink.innerHTML = `${profileMenuIcon('<path d="M12 3 5 6v5c0 4.7 2.8 8.2 7 10 4.2-1.8 7-5.3 7-10V6l-7-3Z"/><path d="m9 12 2 2 4-5"/>')}<span><strong>Account &amp; Security</strong><small>Email, password, and session</small></span>`;

  const signOutButton = document.createElement('button');
  signOutButton.className = 'ecosystem-profile-action ecosystem-sign-out';
  signOutButton.type = 'button';
  signOutButton.setAttribute('role', 'menuitem');
  signOutButton.innerHTML = `${profileMenuIcon('<path d="M10 5H5v14h5M14 8l4 4-4 4m4-4H9"/>')}<span><strong>Sign out</strong><small>End this session</small></span>`;
  panel.append(profileLink, settingsButton, securityLink, signOutButton);
  host.replaceChildren(trigger, panel);

  const menuItems = () => [...panel.querySelectorAll('[role="menuitem"]')];
  const close = (restoreFocus = false) => {
    panel.hidden = true;
    trigger.setAttribute('aria-expanded', 'false');
    host.classList.remove('open');
    if (restoreFocus) trigger.focus({ preventScroll:true });
  };
  const open = (focusFirst = false) => {
    document.dispatchEvent(new CustomEvent('ecosystem-utility-open', { detail:{ host } }));
    panel.hidden = false;
    trigger.setAttribute('aria-expanded', 'true');
    host.classList.add('open');
    if (focusFirst) menuItems()[0]?.focus({ preventScroll:true });
  };

  trigger.addEventListener('click', () => panel.hidden ? open() : close());
  trigger.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowDown') { event.preventDefault(); open(true); }
    else if (event.key === 'Escape') { event.preventDefault(); close(true); }
  });
  panel.addEventListener('keydown', (event) => {
    const items = menuItems();
    const index = items.indexOf(document.activeElement);
    if (event.key === 'Escape') { event.preventDefault(); close(true); }
    else if (['ArrowDown','ArrowUp','Home','End'].includes(event.key)) {
      event.preventDefault();
      const next = event.key === 'Home' ? 0 : event.key === 'End' ? items.length-1 : event.key === 'ArrowDown' ? (index+1)%items.length : (index-1+items.length)%items.length;
      items[next]?.focus({ preventScroll:true });
    } else if (event.key === 'Tab') close();
  });
  settingsButton.addEventListener('click', () => { close(); onSettings?.(); });
  signOutButton.addEventListener('click', async () => {
    close(); signOutButton.disabled = true;
    try { await onSignOut?.(); }
    catch (error) { signOutButton.disabled = false; console.error('Sign out failed.', error?.message || error); }
  });
  document.addEventListener('pointerdown', (event) => { if (!host.contains(event.target)) close(); });
  document.addEventListener('ecosystem-utility-open', (event) => { if (event.detail?.host !== host) close(); });
  return identity;
}
