import test from 'node:test';
import assert from 'node:assert/strict';
import {fairwayCalendarEntries,fairwayTimelineItems,fairwayDetail} from './fairway-events.js';
import {layoutTimelineItems} from './scheduler.js';
const source={source_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',starts_at:'2030-09-12T14:30:00Z',course:'Test Links',tee:'Blue',host_name:'Host',participant_count:2,round_status:'planned'};

test('source reference uses local day and actual tee time without copying private fields',()=>{
  const [entry]=fairwayCalendarEntries([{...source,notes:'private',holes:[4,5],deep_link:'javascript:alert(1)'}]);
  const time=new Date(source.starts_at);
  assert.equal(entry.time,`${String(time.getHours()).padStart(2,'0')}:${String(time.getMinutes()).padStart(2,'0')}`);
  assert.equal(entry.date,`${time.getFullYear()}-${String(time.getMonth()+1).padStart(2,'0')}-${String(time.getDate()).padStart(2,'0')}`);
  assert.equal(entry.href,`/golf/#upcoming/${source.source_id}`);
  assert.equal(entry.notes,undefined);assert.equal(entry.holes,undefined);
});
test('changed source time moves the item and empty access results remove it',()=>{
  const [before]=fairwayCalendarEntries([source]);
  const after=fairwayCalendarEntries([{...source,starts_at:'2030-09-14T17:45:00Z'}]);
  assert.equal(fairwayTimelineItems(after,before.date).length,0);
  assert.equal(fairwayCalendarEntries([]).length,0);
});
test('tee-time marker uses timeline lanes without inventing a round end time',()=>{
  const entries=fairwayCalendarEntries([source]);
  const [round]=fairwayTimelineItems(entries,entries[0].date);
  const items=layoutTimelineItems([round,{id:'task',startMinute:round.startMinute,endMinute:round.startMinute+60}]);
  assert.equal(items.length,2);assert.equal(items[0].laneCount,2);
  assert.notEqual(items[0].lane,items[1].lane);
  assert.equal(round.endsAt,undefined);
  assert.match(fairwayDetail(round),/Blue · Host: Host · 2 playing · Planned/);
});
test('invalid dates and invalid source links are ignored',()=>{
  assert.deepEqual(fairwayCalendarEntries([{...source,starts_at:'invalid'},{...source,source_id:'javascript:bad'}]),[]);
});
test('late tee-time marker remains inside selected day',()=>{
  const [entry]=fairwayCalendarEntries([source]);entry.time='23:55';
  const [item]=fairwayTimelineItems([entry],entry.date);
  assert.equal(item.startMinute,1435);assert.equal(item.endMinute,1440);
});
