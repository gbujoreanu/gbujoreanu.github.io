import { listRelationshipPeople,withSignedAvatars } from './social.js?v=3';

export async function getHouseholdState(client) {
  const { data,error } = await client.rpc('ecosystem_household_state');
  if (error) throw error;
  const state = data || {};
  const [members,incoming,outgoing] = await Promise.all([
    withSignedAvatars(client,state.members || []),
    withSignedAvatars(client,state.incoming || []),
    withSignedAvatars(client,state.outgoing || [])
  ]);
  return { household:state.household || null,members,incoming,outgoing };
}

export async function searchHouseholdCandidates(client,query) {
  return listRelationshipPeople(client,'search',query);
}

export async function createHousehold(client,name) {
  const { data,error } = await client.rpc('ecosystem_create_household',{ household_name:String(name).trim() });
  if (error) throw error;
  return data;
}

export async function inviteHouseholdMember(client,householdId,userId) {
  const { data,error } = await client.rpc('ecosystem_invite_household',{ household:householdId,target_id:userId });
  if (error) throw error;
  return data;
}

export async function respondHouseholdInvitation(client,invitationId,response) {
  if (!['accepted','declined'].includes(response)) throw new Error('Unsupported invitation response.');
  const { error } = await client.rpc('ecosystem_respond_household_invite',{ invitation_id:invitationId,response });
  if (error) throw error;
}

export async function cancelHouseholdInvitation(client,invitationId) {
  const { error } = await client.rpc('ecosystem_cancel_household_invite',{ invitation_id:invitationId });
  if (error) throw error;
}

export async function removeHouseholdMember(client,householdId,userId) {
  const { error } = await client.rpc('ecosystem_remove_household_member',{ target_household:householdId,target_user:userId });
  if (error) throw error;
}

export async function deleteHousehold(client,householdId) {
  const { error } = await client.rpc('ecosystem_delete_household',{ target_household:householdId });
  if (error) throw error;
}

export function householdError(error) {
  const raw = String(error?.message || 'That family action could not be completed.');
  if (/already belongs/i.test(raw)) return 'That person already belongs to a family group.';
  if (/already pending|duplicate|unique/i.test(raw)) return 'An invitation is already pending.';
  if (/cannot invite yourself/i.test(raw)) return 'You cannot invite yourself.';
  if (/blocked/i.test(raw)) return 'That invitation is unavailable because one of you has blocked the other.';
  if (/invitation unavailable/i.test(raw)) return 'That invitation is no longer available.';
  if (/profile unavailable/i.test(raw)) return 'That profile is not available for invitations.';
  if (/owner must delete/i.test(raw)) return 'The owner must delete the family group instead of leaving it.';
  if (/household unavailable|member unavailable|not allowed/i.test(raw)) return 'That family action is not available.';
  if (/name must be/i.test(raw)) return 'Enter a family name between 1 and 80 characters.';
  return 'That family action could not be completed. Please try again.';
}
