import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import { loadEcosystemIdentity, renderIdentityAvatar } from './identity.js';
import { withSignedAvatars } from './social.js';

test('missing profile is repaired by caller-only RPC and reloaded', async () => {
  const profile = { id:'a', display_name:'User 123', handle:'user123' };
  let reads=0, repairs=0;
  const client={ from:()=>({ select:()=>({ eq:()=>({ maybeSingle:async()=>({data:++reads===1?null:profile}) }) }) }),
    rpc:async(name)=>{ assert.equal(name,'account_ensure_profile'); repairs++; return {}; } };
  const result=await loadEcosystemIdentity(client,{id:'a'});
  assert.equal(result.handle,'user123'); assert.equal(repairs,1);
  await loadEcosystemIdentity(client,{id:'a'}); assert.equal(repairs,1);
});
test('repair errors are not silently replaced with empty identities', async()=>{
  const client={from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>({data:null})})})}),rpc:async()=>({error:new Error('Unavailable')})};
  await assert.rejects(loadEcosystemIdentity(client,{id:'a'}),/Unavailable/);
});
test('signed avatar authorization failures retain initials fallback',async()=>{
  const rows=await withSignedAvatars({storage:{from:()=>({createSignedUrl:async()=>({error:{message:'Denied'}})})}},[{id:'a',avatar_path:'a/a.png'},{id:'b'}]);
  assert.ok(rows.every(row=>row.signedAvatarUrl===null));
});
test('broken avatar falls back; stale image cannot replace new identity; email not used',()=>{
  const previous=globalThis.document;
  globalThis.document={createElement:()=>({addEventListener(_event,handler){this.fail=handler;}})};
  const host={classList:{toggle(){},remove(){}},replaceChildren(){if(this.image)this.image.parentNode=null;this.image=null;},append(image){this.image=image;image.parentNode=this;}};
  try {
    renderIdentityAvatar(host,{display_name:'Neutral User',signedAvatarUrl:'signed'});
    const old=host.image;old.fail();assert.equal(host.textContent,'NU');
    renderIdentityAvatar(host,{display_name:'Other Profile'});old.fail();assert.equal(host.textContent,'OP');
    renderIdentityAvatar(host,null,{email:'private@example.test'});assert.equal(host.textContent,'A');
  } finally {globalThis.document=previous;}
});
async function searchContext(file) {
  const source=(await readFile(new URL(file,import.meta.url),'utf8')).replace(/^import[\s\S]*?;\s*/gm,'');
  const context=vm.createContext({window:{},document:{querySelector:()=>null},clearTimeout:()=>{},setTimeout:()=>1});
  vm.runInContext(source,context);
  return {context,run:code=>vm.runInContext(code,context)};
}
test('Connections invalidates in-flight responses as soon as typing changes',async()=>{
  const {context,run}=await searchContext('../account/connections.js');
  run('render=()=>{};setBusy=()=>{};setMessage=()=>{};');
  let finish;context.listRelationshipPeople=()=>new Promise(resolve=>{finish=resolve;});
  run("active='people';searchQuery='old';");
  const request=run('loadActive()');
  run("scheduleSearch({currentTarget:{value:'new'}})");
  finish([{id:'stale'}]);await request;
  assert.equal(run('rows.length'),0);
  run("scheduleSearch({currentTarget:{value:''}})");assert.equal(run('rows.length'),0);
});
test('Family invalidates stale candidates immediately during debounce',async()=>{
  const {context,run}=await searchContext('../account/family.js');
  run('renderCandidates=()=>{};');
  let finish;context.searchHouseholdCandidates=()=>new Promise(resolve=>{finish=resolve;});
  const request=run("runFamilySearch('old')");
  run("scheduleFamilySearch({currentTarget:{value:'new'}})");
  finish([{id:'stale'}]);await request;
  assert.equal(run('candidates.length'),0);
});
