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
