const AVATAR_TTL_SECONDS = 1800;
const LIST_MODES = new Set(['search','friends','requests','following','followers']);

export async function withSignedAvatars(client, people = []) {
  return Promise.all(people.map(async (person) => {
    if (!person.avatar_path) return { ...person, signedAvatarUrl:null };
    const { data, error } = await client.storage.from('avatars').createSignedUrl(person.avatar_path, AVATAR_TTL_SECONDS);
    return { ...person, signedAvatarUrl:error ? null : data?.signedUrl || null };
  }));
}

export async function listRelationshipPeople(client, mode, query = '') {
  if (!LIST_MODES.has(mode)) throw new Error('Unsupported connection list.');
  const { data, error } = await client.rpc('ecosystem_relationship_people', {
    search_text:String(query).trim(), list_mode:mode, result_limit:100
  });
  if (error) throw error;
  return withSignedAvatars(client, data || []);
}

export async function setFollow(client, userId, enabled) {
  const { error } = await client.rpc('ecosystem_set_follow', { target_id:userId, should_follow:Boolean(enabled) });
  if (error) throw error;
}

export async function requestFriend(client, userId) {
  const { error } = await client.rpc('ecosystem_send_friend_request', { target_id:userId });
  if (error) throw error;
}

export async function cancelFriendRequest(client, requestId) {
  const { error } = await client.rpc('ecosystem_cancel_friend_request', { request_id:requestId });
  if (error) throw error;
}

export async function respondFriend(client, requestId, response) {
  if (!['accepted','declined'].includes(response)) throw new Error('Unsupported request response.');
  const { error } = await client.rpc('ecosystem_respond_friend_request', { request_id:requestId, response });
  if (error) throw error;
}

export async function removeFriend(client, userId) {
  const { error } = await client.rpc('ecosystem_remove_friend', { target_id:userId });
  if (error) throw error;
}

export async function blockUser(client, userId) {
  const { error } = await client.rpc('ecosystem_block_user', { target_id:userId });
  if (error) throw error;
}

export async function unblockUser(client, userId) {
  const { error } = await client.rpc('ecosystem_unblock_user', { target_id:userId });
  if (error) throw error;
}

export async function listBlockedUsers(client) {
  const { data, error } = await client.from('ecosystem_blocks').select('blocked_id,created_at').order('created_at', { ascending:false });
  if (error) throw error;
  return data || [];
}

export function personLabel(person) {
  return person.display_name?.trim() || (person.handle ? `@${person.handle}` : 'Ecosystem member');
}

export function socialError(error) {
  const raw = String(error?.message || 'That action could not be completed.');
  if (/duplicate|one_pending|unique/i.test(raw)) return 'That request already exists.';
  if (/request unavailable/i.test(raw)) return 'That request is no longer available.';
  if (/not allowed|blocked|unavailable|discoverable/i.test(raw)) return 'That connection is not available.';
  return 'That action could not be completed. Please try again.';
}
