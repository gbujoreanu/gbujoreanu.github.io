import {
  listRelationshipPeople,setFollow,requestFriend,cancelFriendRequest,respondFriend,
  removeFriend,blockUser,unblockUser,listBlockedUsers,personLabel,socialError
} from '../shared/social.js?v=3';
import { renderIdentityAvatar } from '../shared/identity.js?v=3';

const client = window.AppAuth?.client;
const root = document.querySelector('[data-connections]');
let user = null;
let active = 'friends';
let rows = [];
let searchQuery = '';

if (client && root) {
  root.addEventListener('click', handleClick);
  root.addEventListener('keydown', handleTabKeys);
  root.querySelector('[data-people-search]').addEventListener('submit', runSearch);
  client.auth.onAuthStateChange((_event, session) => setUser(session?.user || null));
  client.auth.getSession().then(({data}) => setUser(data.session?.user || null));
}

async function setUser(next) {
  if (user?.id === next?.id) return;
  user = next;
  root.hidden = !user;
  if (user) await loadActive();
}

async function loadActive() {
  setMessage('Loading connections…');
  setBusy(true);
  try {
    rows = active === 'blocked'
      ? await listBlockedUsers(client)
      : active === 'people' && !searchQuery
        ? []
        : await listRelationshipPeople(client, active === 'people' ? 'search' : active, searchQuery);
    render();
    setMessage('');
  } catch (error) {
    rows = [];
    render();
    setMessage(socialError(error), true);
  } finally { setBusy(false); }
}

async function runSearch(event) {
  event.preventDefault();
  searchQuery = root.querySelector('#peopleSearch').value.trim();
  active = 'people';
  await loadActive();
}

async function handleClick(event) {
  const tab = event.target.closest('[data-connection-tab]');
  if (tab) {
    active = tab.dataset.connectionTab;
    updateTabs();
    await loadActive();
    return;
  }
  const button = event.target.closest('[data-social-action]');
  if (!button) return;
  const action = button.dataset.socialAction;
  button.disabled = true;
  try {
    if (action === 'follow') await setFollow(client, button.dataset.userId, true);
    if (action === 'unfollow') await setFollow(client, button.dataset.userId, false);
    if (action === 'friend') await requestFriend(client, button.dataset.userId);
    if (action === 'cancel-request') await cancelFriendRequest(client, button.dataset.requestId);
    if (action === 'accept') await respondFriend(client, button.dataset.requestId, 'accepted');
    if (action === 'decline') await respondFriend(client, button.dataset.requestId, 'declined');
    if (action === 'remove-friend' && confirm('Remove this friend? This does not change either person’s private app data.')) await removeFriend(client, button.dataset.userId);
    if (action === 'block' && confirm('Block this person? Following, friendship, and pending requests between you will be removed.')) await blockUser(client, button.dataset.userId);
    if (action === 'unblock') await unblockUser(client, button.dataset.userId);
    await loadActive();
  } catch (error) {
    setMessage(socialError(error), true);
    button.disabled = false;
  }
}

function handleTabKeys(event) {
  const current = event.target.closest('[data-connection-tab]');
  if (!current || !['ArrowLeft','ArrowRight','Home','End'].includes(event.key)) return;
  const tabs = [...root.querySelectorAll('[data-connection-tab]')];
  let index = tabs.indexOf(current);
  if (event.key === 'Home') index = 0;
  else if (event.key === 'End') index = tabs.length - 1;
  else index = (index + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length;
  event.preventDefault();
  tabs[index].focus();
  tabs[index].click();
}

function render() {
  updateTabs();
  const output = root.querySelector('[data-connection-results]');
  output.replaceChildren();
  if (active === 'blocked') return renderBlocked(output);
  if (!rows.length) return output.append(emptyState());
  rows.forEach(person => output.append(personRow(person)));
}

function updateTabs() {
  root.querySelectorAll('[data-connection-tab]').forEach((button) => {
    const selected = button.dataset.connectionTab === active;
    button.classList.toggle('active', selected);
    button.setAttribute('aria-selected', String(selected));
    button.tabIndex = selected ? 0 : -1;
  });
  root.querySelector('[data-people-search]').hidden = active !== 'people';
}

function personRow(person) {
  const row = document.createElement('article'); row.className = 'connection-person';
  const avatar = document.createElement('span'); avatar.className = 'connection-avatar'; avatar.setAttribute('aria-hidden','true'); renderIdentityAvatar(avatar, person);
  const info = document.createElement('div'); info.className = 'connection-person-info';
  const title = document.createElement('strong'); title.textContent = personLabel(person);
  const handle = document.createElement('span'); handle.textContent = person.handle ? `@${person.handle}` : 'No public handle';
  const bio = document.createElement('p'); bio.textContent = person.bio || 'No public bio.';
  info.append(title, handle, bio);
  const states = document.createElement('div'); states.className = 'connection-states';
  if (person.is_friend) states.append(stateLabel('Friends'));
  if (person.is_following) states.append(stateLabel('Following'));
  if (person.is_follower) states.append(stateLabel('Follows you'));
  if (person.request_direction === 'incoming') states.append(stateLabel('Wants to be friends'));
  if (person.request_direction === 'outgoing') states.append(stateLabel('Request sent'));
  info.append(states);
  const actions = document.createElement('div'); actions.className = 'connection-actions';
  actions.append(actionButton(person.is_following ? 'Unfollow' : person.is_follower ? 'Follow back' : 'Follow', person.is_following ? 'unfollow' : 'follow', person));
  if (person.request_direction === 'incoming') actions.append(actionButton('Accept','accept',person,'primary'), actionButton('Decline','decline',person));
  else if (person.request_direction === 'outgoing') actions.append(actionButton('Cancel request','cancel-request',person));
  else if (person.is_friend) actions.append(actionButton('Remove friend','remove-friend',person));
  else actions.append(actionButton('Add friend','friend',person,'primary'));
  actions.append(actionButton('Block','block',person,'danger'));
  row.append(avatar,info,actions);
  return row;
}

function renderBlocked(output) {
  if (!rows.length) return output.append(emptyState());
  rows.forEach((block) => {
    const row = document.createElement('article'); row.className = 'connection-person blocked-person';
    const mark = document.createElement('span'); mark.className = 'connection-avatar'; mark.textContent = '—'; mark.setAttribute('aria-hidden','true');
    const info = document.createElement('div'); info.className = 'connection-person-info';
    const title = document.createElement('strong'); title.textContent = 'Blocked account';
    const detail = document.createElement('span'); detail.textContent = 'This person cannot find or connect with you.';
    info.append(title,detail);
    const actions = document.createElement('div'); actions.className = 'connection-actions';
    const button = actionButton('Unblock','unblock',{id:block.blocked_id}); actions.append(button);
    row.append(mark,info,actions); output.append(row);
  });
}

function emptyState() {
  const copy = {
    friends:['No friends yet.','Find people you know and send a friend request.'],
    requests:['No requests.','Incoming and outgoing friend requests will appear here.'],
    following:['Not following anyone yet.','Find a profile to follow.'],
    followers:['No followers yet.','People who follow your discoverable profile will appear here.'],
    people:searchQuery ? ['No people found.','Try another display name or @handle.'] : ['Find people.','Search by display name or @handle. Email is never searchable.'],
    blocked:['No blocked accounts.','Blocked people are excluded from discovery and requests.']
  }[active];
  const empty = document.createElement('div'); empty.className = 'connection-empty';
  const strong = document.createElement('strong'); strong.textContent = copy[0];
  const span = document.createElement('span'); span.textContent = copy[1];
  empty.append(strong,span); return empty;
}

function actionButton(label, action, person, className='') {
  const button = document.createElement('button'); button.type = 'button'; button.className = `connection-button ${className}`; button.textContent = label;
  button.dataset.socialAction = action; button.dataset.userId = person.id;
  if (person.request_id) button.dataset.requestId = person.request_id;
  return button;
}

function stateLabel(text) { const span=document.createElement('span'); span.className='connection-state'; span.textContent=text; return span; }
function setBusy(value) { root.setAttribute('aria-busy', String(value)); }
function setMessage(text, error=false) { const el=root.querySelector('[data-connections-message]'); el.textContent=text; el.classList.toggle('error',error); }
