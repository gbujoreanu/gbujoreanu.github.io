import {
  getHouseholdState,searchHouseholdCandidates,createHousehold,inviteHouseholdMember,
  respondHouseholdInvitation,cancelHouseholdInvitation,removeHouseholdMember,
  deleteHousehold,householdError
} from '../shared/households.js?v=1';
import { personLabel } from '../shared/social.js?v=3';
import { renderIdentityAvatar } from '../shared/identity.js?v=3';

const client = window.AppAuth?.client;
const root = document.querySelector('[data-family]');
const content = root?.querySelector('[data-family-content]');
const createDialog = document.querySelector('#createFamilyDialog');
const inviteDialog = document.querySelector('#inviteFamilyDialog');
let user = null;
let state = { household:null,members:[],incoming:[],outgoing:[] };
let candidates = [];

if (client && root) {
  root.addEventListener('click',handleFamilyClick);
  createDialog?.addEventListener('click',handleDialogClick);
  inviteDialog?.addEventListener('click',handleDialogClick);
  document.querySelector('#createFamilyForm')?.addEventListener('submit',submitCreate);
  document.querySelector('#familyInviteSearch')?.addEventListener('submit',searchPeople);
  client.auth.onAuthStateChange((_event,session)=>setUser(session?.user || null));
  client.auth.getSession().then(({data})=>setUser(data.session?.user || null));
}

async function setUser(next) {
  if (user?.id===next?.id) return;
  user=next;
  root.hidden=!user;
  if (user) await loadState();
}

async function loadState(message='') {
  setMessage(message || 'Loading family…');
  root.setAttribute('aria-busy','true');
  try {
    state=await getHouseholdState(client);
    render();
    setMessage(message);
  } catch (error) {
    content.replaceChildren(emptyBlock('Family information is unavailable.','Refresh the page and try again.'));
    setMessage(householdError(error),true);
  } finally { root.setAttribute('aria-busy','false'); }
}

function render() {
  content.replaceChildren();
  if (state.incoming.length) content.append(invitationSection('Invitations for you',state.incoming,'incoming'));
  if (!state.household) {
    const empty=emptyBlock('No family group yet.','Create a private family relationship for future sharing. Membership alone never opens Daymark or Money data.');
    empty.append(actionButton('Create Family','open-create','primary'));
    content.append(empty);
    return;
  }

  const summary=document.createElement('div'); summary.className='family-summary';
  const title=document.createElement('div');
  title.innerHTML='<p class="family-kicker">Your family group</p>';
  const heading=document.createElement('h3'); heading.textContent=state.household.name;
  const detail=document.createElement('p'); detail.textContent=`${state.members.length} ${state.members.length===1?'member':'members'} · You are ${state.household.role==='owner'?'the owner':'a member'}`;
  title.append(heading,detail);
  const actions=document.createElement('div'); actions.className='family-summary-actions';
  if (state.household.role==='owner') {
    actions.append(actionButton('Invite Member','open-invite','primary'),actionButton('Delete Family','delete-household','danger'));
  } else actions.append(actionButton('Leave Family','leave-household','danger'));
  summary.append(title,actions); content.append(summary);

  const members=document.createElement('section'); members.className='family-list-section';
  const membersHeading=document.createElement('div'); membersHeading.className='family-list-heading';
  const membersTitle=document.createElement('h3'); membersTitle.textContent='Members';
  const membersCopy=document.createElement('p'); membersCopy.textContent='Membership establishes a trusted relationship, not automatic access to private apps.';
  membersHeading.append(membersTitle,membersCopy); members.append(membersHeading);
  const list=document.createElement('div'); list.className='family-list';
  state.members.forEach(member=>list.append(personRow(member,'member'))); members.append(list); content.append(members);
  if (state.outgoing.length) content.append(invitationSection('Pending invitations',state.outgoing,'outgoing'));
}

function invitationSection(titleText,rows,direction) {
  const section=document.createElement('section'); section.className='family-list-section';
  const heading=document.createElement('div'); heading.className='family-list-heading';
  const title=document.createElement('h3'); title.textContent=titleText;
  const copy=document.createElement('p'); copy.textContent=direction==='incoming'?'Accepting joins you to that family group.':'Only the invited person can accept.';
  heading.append(title,copy); section.append(heading);
  const list=document.createElement('div'); list.className='family-list';
  rows.forEach(row=>list.append(personRow(row,direction))); section.append(list); return section;
}

function personRow(person,kind) {
  const row=document.createElement('article'); row.className='family-person';
  const avatar=document.createElement('span'); avatar.className='family-avatar'; avatar.setAttribute('aria-hidden','true'); renderIdentityAvatar(avatar,person);
  const info=document.createElement('div'); info.className='family-person-info';
  const title=document.createElement('strong');
  title.textContent=kind==='incoming' ? person.household_name : personLabel(person);
  const secondary=document.createElement('span');
  if (kind==='incoming') secondary.textContent=`Invited by ${personLabel(person)}${person.handle ? ` · @${person.handle}` : ''}`;
  else secondary.textContent=person.handle ? `@${person.handle}` : kind==='member' ? 'Family member' : 'Ecosystem member';
  info.append(title,secondary);
  if (kind==='member') {
    const role=document.createElement('span'); role.className='family-role'; role.textContent=person.role==='owner'?'Owner':'Member'; info.append(role);
  }
  const actions=document.createElement('div'); actions.className='family-person-actions';
  if (kind==='incoming') actions.append(actionButton('Accept','accept-invite','primary',person.id),actionButton('Decline','decline-invite','',person.id));
  if (kind==='outgoing') actions.append(actionButton('Cancel','cancel-invite','',person.id));
  if (kind==='member' && state.household.role==='owner' && person.role!=='owner') actions.append(actionButton('Remove','remove-member','danger',person.id));
  row.append(avatar,info,actions); return row;
}

async function handleFamilyClick(event) {
  const button=event.target.closest('[data-family-action]');
  if (!button) return;
  const action=button.dataset.familyAction;
  if (action==='open-create') return openDialog(createDialog,'#familyName');
  if (action==='open-invite') {
    candidates=[];
    document.querySelector('#familyInviteQuery').value='';
    renderCandidates('Search by display name or @handle.');
    return openDialog(inviteDialog,'#familyInviteQuery');
  }
  if (action==='accept-invite') return runAction(button,()=>respondHouseholdInvitation(client,button.dataset.id,'accepted'),'Invitation accepted.');
  if (action==='decline-invite') return runAction(button,()=>respondHouseholdInvitation(client,button.dataset.id,'declined'),'Invitation declined.');
  if (action==='cancel-invite') return runAction(button,()=>cancelHouseholdInvitation(client,button.dataset.id),'Invitation cancelled.');
  if (action==='remove-member' && confirm('Remove this member from the family group? Their private app data will not be changed.')) {
    return runAction(button,()=>removeHouseholdMember(client,state.household.id,button.dataset.id),'Member removed.');
  }
  if (action==='leave-household' && confirm('Leave this family group? Your private app data will not be changed.')) {
    return runAction(button,()=>removeHouseholdMember(client,state.household.id,user.id),'You left the family group.');
  }
  if (action==='delete-household' && confirm('Permanently delete this family group? Members will be disconnected, but nobody’s Daymark or Money data will be deleted.')) {
    return runAction(button,()=>deleteHousehold(client,state.household.id),'Family group deleted.');
  }
}

async function submitCreate(event) {
  event.preventDefault();
  const button=event.submitter;
  const name=document.querySelector('#familyName').value.trim();
  if (!name) return setDialogMessage(createDialog,'Enter a family name.',true);
  button.disabled=true; setDialogMessage(createDialog,'Creating…');
  try {
    await createHousehold(client,name);
    createDialog.close(); event.currentTarget.reset(); await loadState('Family group created.');
  } catch (error) { setDialogMessage(createDialog,householdError(error),true); }
  finally { button.disabled=false; }
}

async function searchPeople(event) {
  event.preventDefault();
  const query=document.querySelector('#familyInviteQuery').value.trim();
  if (!query) return renderCandidates('Enter a display name or @handle.');
  const submit=event.submitter; submit.disabled=true; renderCandidates('Searching…');
  try {
    const memberIds=new Set(state.members.map(member=>member.id));
    candidates=(await searchHouseholdCandidates(client,query)).filter(person=>!memberIds.has(person.id));
    renderCandidates(candidates.length ? '' : 'No available profiles found.');
  } catch (error) { renderCandidates(householdError(error),true); }
  finally { submit.disabled=false; }
}

function renderCandidates(message='',error=false) {
  const output=document.querySelector('[data-family-candidates]'); output.replaceChildren();
  const status=document.querySelector('[data-family-invite-message]'); status.textContent=message; status.classList.toggle('error',error);
  candidates.forEach(person=>{
    const row=document.createElement('article'); row.className='family-person compact';
    const avatar=document.createElement('span'); avatar.className='family-avatar'; avatar.setAttribute('aria-hidden','true'); renderIdentityAvatar(avatar,person);
    const info=document.createElement('div'); info.className='family-person-info';
    const title=document.createElement('strong'); title.textContent=personLabel(person);
    const handle=document.createElement('span'); handle.textContent=person.handle ? `@${person.handle}` : 'Discoverable profile'; info.append(title,handle);
    const button=actionButton('Invite','invite-candidate','primary',person.id); row.append(avatar,info,button); output.append(row);
  });
}

inviteDialog?.addEventListener('click',async(event)=>{
  const button=event.target.closest('[data-family-action="invite-candidate"]');
  if (!button) return;
  button.disabled=true;
  try {
    await inviteHouseholdMember(client,state.household.id,button.dataset.id);
    inviteDialog.close(); await loadState('Invitation sent.');
  } catch (error) { setDialogMessage(inviteDialog,householdError(error),true); button.disabled=false; }
});

async function runAction(button,operation,success) {
  button.disabled=true; setMessage('Saving…');
  try { await operation(); await loadState(success); }
  catch (error) { setMessage(householdError(error),true); button.disabled=false; }
}

function actionButton(label,action,className='',id='') {
  const button=document.createElement('button'); button.type='button'; button.className=`family-button ${className}`; button.textContent=label;
  button.dataset.familyAction=action; if (id) button.dataset.id=id; return button;
}

function emptyBlock(titleText,copyText) {
  const empty=document.createElement('div'); empty.className='family-empty';
  const title=document.createElement('strong'); title.textContent=titleText;
  const copy=document.createElement('p'); copy.textContent=copyText; empty.append(title,copy); return empty;
}

function openDialog(dialog,focusSelector) {
  setDialogMessage(dialog,''); dialog.showModal(); requestAnimationFrame(()=>dialog.querySelector(focusSelector)?.focus());
}

function handleDialogClick(event) {
  if (event.target.closest('[data-close-family-dialog]')) event.currentTarget.close();
}

function setMessage(text,error=false) {
  const message=root.querySelector('[data-family-message]'); message.textContent=text; message.classList.toggle('error',error);
}

function setDialogMessage(dialog,text,error=false) {
  const message=dialog?.querySelector('[data-family-dialog-message], [data-family-invite-message]');
  if (!message) return; message.textContent=text; message.classList.toggle('error',error);
}
