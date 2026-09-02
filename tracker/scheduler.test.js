import test from 'node:test';
import assert from 'node:assert/strict';
import { formatDuration, layoutTimelineItems } from './scheduler.js';

test('overlapping items receive separate lanes', () => {
  const items = layoutTimelineItems([
    { id: 'work', startMinute: 600, endMinute: 1140 },
    { id: 'call', startMinute: 630, endMinute: 690 },
    { id: 'gym', startMinute: 1200, endMinute: 1290 }
  ]);

  const work = items.find((item) => item.id === 'work');
  const call = items.find((item) => item.id === 'call');
  const gym = items.find((item) => item.id === 'gym');
  assert.equal(work.laneCount, 2);
  assert.equal(call.laneCount, 2);
  assert.notEqual(work.lane, call.lane);
  assert.equal(gym.laneCount, 1);
});

test('touching items can reuse the same lane', () => {
  const items = layoutTimelineItems([
    { id: 'one', startMinute: 60, endMinute: 120 },
    { id: 'two', startMinute: 120, endMinute: 180 }
  ]);
  assert.deepEqual(items.map((item) => item.lane), [0, 0]);
});

test('duration labels remain readable', () => {
  assert.equal(formatDuration(45), '45 min');
  assert.equal(formatDuration(60), '1 hour');
  assert.equal(formatDuration(90), '1h 30m');
  assert.equal(formatDuration(540), '9 hours');
});
