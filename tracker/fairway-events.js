// Source-linked calendar items are held in memory, never in Daymark's private tables.
export function fairwayCalendarEntries(rows) {
  return rows.flatMap(row=>{
    const start=new Date(row.starts_at);
    const holeCount=Number(row.hole_count)===9?9:18;
    const end=new Date(start.getTime()+(holeCount===9?2:4)*60*60*1000);
    if(!Number.isFinite(start.getTime()) || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(row.source_id) || row.round_status==='cancelled')return [];
    const pad=value=>String(value).padStart(2,'0');
    const date=`${start.getFullYear()}-${pad(start.getMonth()+1)}-${pad(start.getDate())}`;
    const time=`${pad(start.getHours())}:${pad(start.getMinutes())}`;
    const endTime=`${pad(end.getHours())}:${pad(end.getMinutes())}`;
    return [{id:`fairway-${row.source_id}`,sourceId:row.source_id,type:'fairway',title:`Fairway · ${row.course}`,
      date,time,endTime,startsAt:row.starts_at,endsAt:end.toISOString(),holeCount,course:row.course,tee:row.tee,host:row.host_name,
      participants:Number(row.participant_count)||0,status:row.round_status,
      href:`/golf/#upcoming/${row.source_id}`,done:row.round_status==='completed'}];
  });
}

export function fairwayTimelineItems(entries,date) {
  return entries.filter(item=>item.date===date).map(item=>{
    const [hour,minute]=item.time.split(':').map(Number);
    const startMinute=hour*60+minute;
    const duration=item.holeCount===9?120:240;
    return {...item,startMinute,endMinute:Math.min(1440,startMinute+duration),
      timeLabel:`${new Date(item.startsAt).toLocaleTimeString('en-US',{hour:'numeric',minute:'2-digit'})} – ${new Date(item.endsAt).toLocaleTimeString('en-US',{hour:'numeric',minute:'2-digit'})}`};
  });
}

export function fairwayDetail(item) {
  const status={planned:'Planned',in_progress:'In progress',completed:'Completed'}[item.status]||'Scheduled';
  return `${item.holeCount} holes · ${item.tee} · Host: ${item.host} · ${item.participants} playing · ${status}`;
}
