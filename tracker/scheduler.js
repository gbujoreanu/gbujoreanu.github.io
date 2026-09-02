export const MINUTES_PER_DAY = 24 * 60;

export function layoutTimelineItems(items) {
  const sorted = [...items]
    .map((item) => ({ ...item, startMinute: clampMinute(item.startMinute), endMinute: clampMinute(item.endMinute) }))
    .filter((item) => item.endMinute > item.startMinute)
    .sort((a, b) => a.startMinute - b.startMinute || a.endMinute - b.endMinute);

  const result = [];
  let index = 0;

  while (index < sorted.length) {
    const cluster = [sorted[index]];
    let clusterEnd = sorted[index].endMinute;
    index += 1;

    while (index < sorted.length && sorted[index].startMinute < clusterEnd) {
      cluster.push(sorted[index]);
      clusterEnd = Math.max(clusterEnd, sorted[index].endMinute);
      index += 1;
    }

    const laneEnds = [];
    const placed = cluster.map((item) => {
      let lane = laneEnds.findIndex((end) => end <= item.startMinute);
      if (lane < 0) lane = laneEnds.length;
      laneEnds[lane] = item.endMinute;
      return { ...item, lane };
    });

    const laneCount = Math.max(1, laneEnds.length);
    result.push(...placed.map((item) => ({ ...item, laneCount })));
  }

  return result;
}

export function formatDuration(minutes) {
  const safeMinutes = Math.max(0, Math.round(Number(minutes) || 0));
  const hours = Math.floor(safeMinutes / 60);
  const remainder = safeMinutes % 60;
  if (!hours) return `${remainder} min`;
  if (!remainder) return `${hours} ${hours === 1 ? 'hour' : 'hours'}`;
  return `${hours}h ${remainder}m`;
}

function clampMinute(value) {
  return Math.min(MINUTES_PER_DAY, Math.max(0, Number(value) || 0));
}
