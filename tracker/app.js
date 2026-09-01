const STORAGE_KEY = "daymark-v1";
const DAY = 86400000;
const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const cloudClient = window.AppAuth?.client || null;
const deviceState = loadDeviceState();

let state = { tasks: [], goals: [], events: [] };
let currentUser = null;
let cloudIsEmpty = false;
let handledUserId = null;
let activeView = "overview";
let taskFilter = "open";
let selectedDate = todayKey();
let calendarCursor = startOfMonth(new Date());

const els = {
  navTaskCount: $("#navTaskCount"), navGoalCount: $("#navGoalCount"), todayLabel: $("#todayLabel"),
  completionScore: $("#completionScore"), completionMeter: $("#completionMeter"), completionDetail: $("#completionDetail"),
  openTaskStat: $("#openTaskStat"), overdueStat: $("#overdueStat"), todayTaskStat: $("#todayTaskStat"),
  activeGoalStat: $("#activeGoalStat"), goalProgressStat: $("#goalProgressStat"), weekStat: $("#weekStat"),
  focusList: $("#focusList"), miniWeek: $("#miniWeek"), goalPreview: $("#goalPreview"),
  taskList: $("#taskList"), taskSearch: $("#taskSearch"), taskFilters: $("#taskFilters"), goalList: $("#goalList"),
  calendarTitle: $("#calendarTitle"), calendarGrid: $("#calendarGrid"), agendaDate: $("#agendaDate"), agendaList: $("#agendaList"),
  itemModal: $("#itemModal"), itemForm: $("#itemForm"), itemType: $("#itemType"), itemId: $("#itemId"),
  formEyebrow: $("#formEyebrow"), formTitle: $("#formTitle"), itemTitle: $("#itemTitle"), itemNotes: $("#itemNotes"),
  taskFields: $("#taskFields"), taskDate: $("#taskDate"), taskTime: $("#taskTime"), taskPriority: $("#taskPriority"), taskOnCalendar: $("#taskOnCalendar"),
  goalFields: $("#goalFields"), goalDate: $("#goalDate"), goalProgress: $("#goalProgress"), goalProgressOutput: $("#goalProgressOutput"),
  eventFields: $("#eventFields"), eventDate: $("#eventDate"), eventTime: $("#eventTime"), saveItem: $("#saveItem"),
  helpModal: $("#helpModal"), importData: $("#importData"), storageStatus: $("#storageStatus"),
  accountLink: $("#accountLink"), signOut: $("#signOut"), migrateData: $("#migrateData")
};

initialize();

async function initialize() {
  bindEvents();
  if (!cloudClient) return location.replace('../account/?returnTo=/tracker/');
  cloudClient.auth.onAuthStateChange((_event, session) => setTimeout(() => applySession(session), 0));
  const { data, error } = await cloudClient.auth.getSession();
  if (error) return setStorageStatus("Cloud unavailable", true);
  await applySession(data.session);
}

function bindEvents() {
  $$('[data-view-target]').forEach((button) => button.addEventListener('click', () => showView(button.dataset.viewTarget)));
  $$('[data-open-form]').forEach((button) => button.addEventListener('click', () => openForm(button.dataset.openForm)));
  $$('[data-close-modal]').forEach((button) => button.addEventListener('click', () => els.itemModal.close()));
  els.itemForm.addEventListener('submit', saveItem);
  els.goalProgress.addEventListener('input', () => { els.goalProgressOutput.value = `${els.goalProgress.value}%`; });
  els.taskFilters.addEventListener('click', (event) => {
    const button = event.target.closest('[data-task-filter]');
    if (!button) return;
    taskFilter = button.dataset.taskFilter;
    $$('[data-task-filter]').forEach((item) => item.classList.toggle('active', item === button));
    renderTasks();
  });
  els.taskSearch.addEventListener('input', renderTasks);
  els.taskList.addEventListener('click', handleItemAction);
  els.focusList.addEventListener('click', handleItemAction);
  els.goalList.addEventListener('click', handleItemAction);
  els.agendaList.addEventListener('click', handleItemAction);
  $('#prevMonth').addEventListener('click', () => changeMonth(-1));
  $('#nextMonth').addEventListener('click', () => changeMonth(1));
  $('#todayButton').addEventListener('click', () => { selectedDate = todayKey(); calendarCursor = startOfMonth(new Date()); renderCalendar(); });
  els.calendarGrid.addEventListener('click', (event) => {
    const day = event.target.closest('[data-date]');
    if (!day) return;
    selectedDate = day.dataset.date;
    const selected = parseDate(selectedDate);
    if (selected.getMonth() !== calendarCursor.getMonth()) calendarCursor = startOfMonth(selected);
    renderCalendar();
  });
  $('#backupHelp').addEventListener('click', () => els.helpModal.showModal());
  $('#exportData').addEventListener('click', exportData);
  els.importData.addEventListener('change', importData);
  $('#resetData').addEventListener('click', resetData);
  els.signOut.addEventListener('click', () => cloudClient?.auth.signOut());
  els.migrateData.addEventListener('click', migrateDeviceData);
}

function showView(view) {
  activeView = view;
  $$('[data-view]').forEach((panel) => panel.classList.toggle('active', panel.dataset.view === view));
  $$('.nav-item').forEach((button) => button.classList.toggle('active', button.dataset.viewTarget === view));
  if (view === 'calendar') renderCalendar();
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

function loadDeviceState() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
    if (saved && Array.isArray(saved.tasks) && Array.isArray(saved.goals) && Array.isArray(saved.events)) return saved;
  } catch (error) { console.warn('Could not read Daymark data.', error); }
  return null;
}

function seedState() {
  const today = new Date();
  return {
    tasks: [
      { id: uid(), title: 'Review this week’s priorities', notes: 'Choose the three outcomes that matter most.', dueDate: dateOffset(today, 0), dueTime: '09:00', priority: 'high', status: 'open', onCalendar: true, createdAt: Date.now() },
      { id: uid(), title: 'Plan the next project milestone', notes: 'Break the next deliverable into clear steps.', dueDate: dateOffset(today, 2), dueTime: '14:30', priority: 'medium', status: 'open', onCalendar: true, createdAt: Date.now() },
      { id: uid(), title: 'Archive completed notes', notes: '', dueDate: dateOffset(today, -1), dueTime: '', priority: 'low', status: 'done', onCalendar: true, createdAt: Date.now() }
    ],
    goals: [
      { id: uid(), title: 'Ship a project I am proud of', notes: 'Polish the core experience and share the finished work.', targetDate: dateOffset(today, 21), progress: 45, createdAt: Date.now() },
      { id: uid(), title: 'Build a consistent weekly system', notes: 'Review tasks and goals every Sunday.', targetDate: dateOffset(today, 35), progress: 70, createdAt: Date.now() }
    ],
    events: [{ id: uid(), title: 'Weekly review', notes: 'Reset priorities for the week ahead.', date: dateOffset(today, 1), time: '17:00', createdAt: Date.now() }]
  };
}

async function applySession(session) {
  if (session?.user && !session.user.email_confirmed_at) { await cloudClient.auth.signOut(); return location.replace('../account/?returnTo=/tracker/'); }
  const nextUser = session?.user || null;
  if (nextUser?.id === handledUserId) return;
  handledUserId = nextUser?.id || null;
  currentUser = nextUser;
  if (!currentUser) {
    return location.replace('../account/?returnTo=/tracker/');
  }
  els.accountLink.classList.add('hidden');
  els.signOut.classList.remove('hidden');
  setStorageStatus('Loading cloud data…');
  try {
    state = await loadCloudState();
    cloudIsEmpty = !state.tasks.length && !state.goals.length && !state.events.length;
    els.migrateData.classList.toggle('hidden', !(cloudIsEmpty && deviceState));
    setStorageStatus(`Cloud · ${currentUser.email || 'signed in'}`);
    document.body.classList.remove('auth-pending');
    renderAll();
  } catch (error) {
    console.error(error);
    setStorageStatus('Cloud load failed', true);
  }
}

async function loadCloudState() {
  const [tasksResult, goalsResult, eventsResult] = await Promise.all([
    cloudClient.from('daymark_tasks').select('*').order('created_at'),
    cloudClient.from('daymark_goals').select('*').order('created_at'),
    cloudClient.from('daymark_events').select('*').order('created_at')
  ]);
  const error = tasksResult.error || goalsResult.error || eventsResult.error;
  if (error) throw error;
  return { tasks: tasksResult.data.map(fromCloudTask), goals: goalsResult.data.map(fromCloudGoal), events: eventsResult.data.map(fromCloudEvent) };
}

function fromCloudTask(row) { return { id:row.id,title:row.title,notes:row.notes,dueDate:row.due_date||'',dueTime:String(row.due_time||'').slice(0,5),priority:row.priority,status:row.status,onCalendar:row.on_calendar,createdAt:Date.parse(row.created_at) }; }
function fromCloudGoal(row) { return { id:row.id,title:row.title,notes:row.notes,targetDate:row.target_date||'',progress:Number(row.progress),createdAt:Date.parse(row.created_at) }; }
function fromCloudEvent(row) { return { id:row.id,title:row.title,notes:row.notes,date:row.event_date,time:String(row.event_time||'').slice(0,5),createdAt:Date.parse(row.created_at) }; }
function toCloudTask(item) { return { id:item.id,user_id:currentUser.id,title:item.title,notes:item.notes||'',due_date:item.dueDate||null,due_time:item.dueTime||null,priority:item.priority,status:item.status,on_calendar:Boolean(item.onCalendar),created_at:new Date(item.createdAt||Date.now()).toISOString() }; }
function toCloudGoal(item) { return { id:item.id,user_id:currentUser.id,title:item.title,notes:item.notes||'',target_date:item.targetDate||null,progress:Number(item.progress)||0,created_at:new Date(item.createdAt||Date.now()).toISOString() }; }
function toCloudEvent(item) { return { id:item.id,user_id:currentUser.id,title:item.title,notes:item.notes||'',event_date:item.date,event_time:item.time||null,created_at:new Date(item.createdAt||Date.now()).toISOString() }; }
function cloudTable(type) { return type === 'task' ? 'daymark_tasks' : type === 'goal' ? 'daymark_goals' : 'daymark_events'; }
function cloudRow(type,item) { return type === 'task' ? toCloudTask(item) : type === 'goal' ? toCloudGoal(item) : toCloudEvent(item); }
async function persistItem(type,item) {
  if (!currentUser) return;
  setStorageStatus('Saving…');
  const { error } = await cloudClient.from(cloudTable(type)).upsert(cloudRow(type,item), { onConflict:'user_id,id' });
  if (error) throw error;
  setStorageStatus(`Cloud · ${currentUser.email || 'signed in'}`);
}
async function removeCloudItem(type,id) {
  const { error } = await cloudClient.from(cloudTable(type)).delete().eq('user_id',currentUser.id).eq('id',id);
  if (error) throw error;
}
function setStorageStatus(text,isError=false) { els.storageStatus.textContent=text; els.storageStatus.classList.toggle('sync-error',isError); }

async function migrateDeviceData() {
  if (!currentUser || !deviceState || !cloudIsEmpty) return;
  if (!confirm('Move this device’s Daymark data into your account? Your local backup will remain on this browser.')) return;
  els.migrateData.disabled = true; setStorageStatus('Moving device data…');
  try {
    const batches = [['daymark_tasks',deviceState.tasks.map(toCloudTask)],['daymark_goals',deviceState.goals.map(toCloudGoal)],['daymark_events',deviceState.events.map(toCloudEvent)]];
    for (const [table,rows] of batches) { if (!rows.length) continue; const {error}=await cloudClient.from(table).upsert(rows,{onConflict:'user_id,id'}); if(error) throw error; }
    state=await loadCloudState(); cloudIsEmpty=false; els.migrateData.classList.add('hidden'); setStorageStatus(`Cloud · ${currentUser.email||'signed in'}`); renderAll();
    alert('Your device data is now saved to your account. The original local copy was kept as a backup.');
  } catch(error) { console.error(error); setStorageStatus('Migration needs attention',true); alert('The move did not finish. Your original device data is safe. You can try again.'); }
  finally { els.migrateData.disabled=false; }
}
function renderAll() { renderOverview(); renderTasks(); renderGoals(); renderCalendar(); updateNavCounts(); }

function updateNavCounts() {
  els.navTaskCount.textContent = state.tasks.filter((task) => task.status !== 'done').length;
  els.navGoalCount.textContent = state.goals.filter((goal) => Number(goal.progress) < 100).length;
}

function calendarEntries() {
  return [
    ...state.tasks.filter((task) => task.dueDate && task.onCalendar).map((task) => ({ id: task.id, sourceId: task.id, type: 'task', title: task.title, date: task.dueDate, time: task.dueTime, done: task.status === 'done' })),
    ...state.goals.filter((goal) => goal.targetDate).map((goal) => ({ id: goal.id, sourceId: goal.id, type: 'goal', title: goal.title, date: goal.targetDate, time: '', done: Number(goal.progress) >= 100 })),
    ...state.events.map((event) => ({ ...event, type: 'event', sourceId: event.id }))
  ].sort(sortByDateTime);
}

function renderOverview() {
  const today = todayKey();
  const open = state.tasks.filter((task) => task.status !== 'done');
  const done = state.tasks.filter((task) => task.status === 'done');
  const overdue = open.filter((task) => task.dueDate && task.dueDate < today);
  const completion = state.tasks.length ? Math.round(done.length / state.tasks.length * 100) : 0;
  const activeGoals = state.goals.filter((goal) => Number(goal.progress) < 100);
  const avgProgress = state.goals.length ? Math.round(state.goals.reduce((sum, goal) => sum + Number(goal.progress), 0) / state.goals.length) : 0;
  const entries = calendarEntries();
  const weekEnd = dateOffset(new Date(), 6);
  els.todayLabel.textContent = new Intl.DateTimeFormat('en-US', { weekday: 'long', month: 'long', day: 'numeric' }).format(new Date());
  els.completionScore.textContent = `${completion}%`; els.completionMeter.style.width = `${completion}%`;
  els.completionDetail.textContent = state.tasks.length ? `${done.length} of ${state.tasks.length} tasks completed` : 'No tasks yet';
  els.openTaskStat.textContent = open.length; els.overdueStat.textContent = overdue.length ? `${overdue.length} overdue` : 'Nothing overdue';
  els.todayTaskStat.textContent = entries.filter((entry) => entry.date === today && !entry.done).length;
  els.activeGoalStat.textContent = activeGoals.length; els.goalProgressStat.textContent = `${avgProgress}% average progress`;
  els.weekStat.textContent = entries.filter((entry) => entry.date >= today && entry.date <= weekEnd && !entry.done).length;
  const focus = [...open].sort((a, b) => priorityRank(a.priority) - priorityRank(b.priority) || sortByDateTime(a, b)).slice(0, 5);
  els.focusList.innerHTML = focus.length ? focus.map((task) => focusMarkup(task)).join('') : emptyMarkup('Nothing urgent. Add a task when you are ready.');
  renderMiniWeek(entries);
  const featuredGoals = [...state.goals].sort((a, b) => Number(b.progress) - Number(a.progress)).slice(0, 3);
  els.goalPreview.innerHTML = featuredGoals.length ? featuredGoals.map((goal) => `<div class="goal-preview-item"><header><h3>${escapeHtml(goal.title)}</h3><span>${goal.progress}%</span></header><div class="progress-track"><i style="width:${clamp(goal.progress,0,100)}%"></i></div></div>`).join('') : emptyMarkup('No goals yet.');
}

function renderMiniWeek(entries) {
  const start = new Date(); start.setHours(12, 0, 0, 0);
  els.miniWeek.innerHTML = Array.from({ length: 7 }, (_, index) => {
    const date = new Date(start.getTime() + index * DAY); const key = formatKey(date);
    const count = entries.filter((entry) => entry.date === key && !entry.done).length;
    return `<div class="day-stack ${index === 0 ? 'today' : ''}"><span>${date.toLocaleDateString('en-US',{weekday:'short'})}</span><strong>${date.getDate()}</strong><i class="${count ? 'has-items' : ''}" title="${count} items"></i></div>`;
  }).join('');
}

function focusMarkup(task) {
  const overdue = task.dueDate && task.dueDate < todayKey();
  return `<div class="focus-item"><button class="check-button" type="button" data-action="toggle-task" data-id="${task.id}" aria-label="Complete ${escapeHtml(task.title)}"></button><div><h3>${escapeHtml(task.title)}</h3><p>${escapeHtml(task.notes || 'No additional notes')}</p></div><div><span class="priority ${task.priority}"></span>${task.dueDate ? `<span class="date-chip ${overdue ? 'overdue' : ''}">${relativeDate(task.dueDate)}</span>` : ''}</div></div>`;
}

function renderTasks() {
  const query = els.taskSearch.value.trim().toLowerCase(); const today = todayKey();
  const filtered = [...state.tasks].filter((task) => {
    const matchesSearch = !query || `${task.title} ${task.notes}`.toLowerCase().includes(query);
    const matchesFilter = taskFilter === 'all' || (taskFilter === 'open' && task.status !== 'done') || (taskFilter === 'done' && task.status === 'done') || (taskFilter === 'today' && task.dueDate === today);
    return matchesSearch && matchesFilter;
  }).sort((a,b) => (a.status === 'done') - (b.status === 'done') || priorityRank(a.priority) - priorityRank(b.priority) || sortByDateTime(a,b));
  els.taskList.innerHTML = filtered.length ? filtered.map(taskMarkup).join('') : emptyMarkup('No tasks match this view.');
}

function taskMarkup(task) {
  const due = task.dueDate ? `${relativeDate(task.dueDate)}${task.dueTime ? ` · ${formatTime(task.dueTime)}` : ''}` : 'No due date';
  return `<article class="task-card ${task.status === 'done' ? 'done' : ''}"><button class="check-button" type="button" data-action="toggle-task" data-id="${task.id}" aria-label="${task.status === 'done' ? 'Reopen' : 'Complete'} ${escapeHtml(task.title)}">${task.status === 'done' ? '✓' : ''}</button><div><h3>${escapeHtml(task.title)}</h3><p>${escapeHtml(task.notes || 'No notes')}</p></div><div class="task-meta"><span class="pill ${task.priority}">${task.priority}</span><span class="date-chip ${task.dueDate < todayKey() && task.status !== 'done' ? 'overdue' : ''}">${due}</span>${task.onCalendar && task.dueDate ? '<span class="pill">Calendar</span>' : ''}</div><div class="card-actions"><button class="small-action" type="button" data-action="edit-task" data-id="${task.id}">Edit</button><button class="small-action danger" type="button" data-action="delete-task" data-id="${task.id}">Delete</button></div></article>`;
}

function renderGoals() {
  const goals = [...state.goals].sort((a,b) => (Number(a.progress) >= 100) - (Number(b.progress) >= 100) || String(a.targetDate).localeCompare(String(b.targetDate)));
  els.goalList.innerHTML = goals.length ? goals.map((goal) => `<article class="goal-card"><header><span class="pill">${Number(goal.progress) >= 100 ? 'Complete' : 'Active'}</span><div class="goal-actions"><button class="small-action" type="button" data-action="edit-goal" data-id="${goal.id}">Edit</button><button class="small-action danger" type="button" data-action="delete-goal" data-id="${goal.id}">Delete</button></div></header><h3>${escapeHtml(goal.title)}</h3><p class="goal-card-copy">${escapeHtml(goal.notes || 'No additional notes')}</p><footer><span class="goal-date">Target · ${formatDate(goal.targetDate)}</span><div class="goal-progress-line"><span>Progress</span><span>${goal.progress}%</span></div><div class="progress-track"><i style="width:${clamp(goal.progress,0,100)}%"></i></div></footer></article>`).join('') : emptyMarkup('No goals yet. Add one to define your next outcome.');
}

function renderCalendar() {
  const year = calendarCursor.getFullYear(), month = calendarCursor.getMonth();
  els.calendarTitle.textContent = calendarCursor.toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
  const gridStart = new Date(year, month, 1); gridStart.setDate(1 - gridStart.getDay()); gridStart.setHours(12,0,0,0);
  const entries = calendarEntries();
  els.calendarGrid.innerHTML = Array.from({length:42},(_,index) => {
    const day = new Date(gridStart.getTime() + index * DAY); const key = formatKey(day); const dayEntries = entries.filter((entry) => entry.date === key);
    return `<button class="calendar-day ${day.getMonth() !== month ? 'outside' : ''} ${key === todayKey() ? 'today' : ''} ${key === selectedDate ? 'selected' : ''}" type="button" data-date="${key}" aria-label="${formatDate(key)}, ${dayEntries.length} items"><span class="day-number">${day.getDate()}</span><span class="day-events">${dayEntries.slice(0,3).map((entry) => `<span class="calendar-event ${entry.type}">${escapeHtml(entry.title)}</span>`).join('')}${dayEntries.length > 3 ? `<span class="more-events">+${dayEntries.length-3} more</span>` : ''}</span></button>`;
  }).join('');
  renderAgenda(entries.filter((entry) => entry.date === selectedDate));
}

function renderAgenda(entries) {
  els.agendaDate.textContent = parseDate(selectedDate).toLocaleDateString('en-US',{weekday:'long',month:'long',day:'numeric'});
  els.agendaList.innerHTML = entries.length ? entries.map((entry) => `<div class="agenda-item ${entry.type}"><strong>${escapeHtml(entry.title)}</strong><span>${entry.time ? formatTime(entry.time) : entry.type === 'goal' ? 'Goal target' : entry.type === 'task' ? 'Task due' : 'All day'}${entry.done ? ' · Complete' : ''}</span><div class="agenda-actions"><button class="small-action" type="button" data-action="edit-${entry.type}" data-id="${entry.sourceId}">Edit</button>${entry.type === 'event' ? `<button class="small-action danger" type="button" data-action="delete-event" data-id="${entry.sourceId}">Delete</button>` : ''}</div></div>`).join('') : emptyMarkup('Nothing scheduled. Leave space or add an event.');
}

function changeMonth(amount) { calendarCursor = new Date(calendarCursor.getFullYear(), calendarCursor.getMonth()+amount, 1); renderCalendar(); }

function openForm(type, item = null) {
  els.itemForm.reset(); els.itemType.value = type; els.itemId.value = item?.id || '';
  els.taskFields.classList.toggle('hidden', type !== 'task'); els.goalFields.classList.toggle('hidden', type !== 'goal'); els.eventFields.classList.toggle('hidden', type !== 'event');
  $$('input, select', els.taskFields).forEach((control) => { control.disabled = type !== 'task'; });
  $$('input', els.goalFields).forEach((control) => { control.disabled = type !== 'goal'; });
  $$('input', els.eventFields).forEach((control) => { control.disabled = type !== 'event'; });
  const labels = {task:'task',goal:'goal',event:'event'}; els.formEyebrow.textContent = item ? `Edit ${labels[type]}` : `New ${labels[type]}`; els.formTitle.textContent = `${item ? 'Update' : 'Add'} ${labels[type]}`; els.saveItem.textContent = item ? 'Save changes' : `Add ${labels[type]}`;
  els.itemTitle.value = item?.title || ''; els.itemNotes.value = item?.notes || '';
  if (type === 'task') { els.taskDate.value = item?.dueDate || todayKey(); els.taskTime.value = item?.dueTime || ''; els.taskPriority.value = item?.priority || 'medium'; els.taskOnCalendar.checked = item?.onCalendar ?? true; }
  if (type === 'goal') { els.goalDate.value = item?.targetDate || dateOffset(new Date(),30); els.goalProgress.value = item?.progress ?? 0; els.goalProgressOutput.value = `${els.goalProgress.value}%`; }
  if (type === 'event') { els.eventDate.value = item?.date || (activeView === 'calendar' ? selectedDate : todayKey()); els.eventTime.value = item?.time || ''; }
  els.itemModal.showModal(); setTimeout(() => els.itemTitle.focus(), 0);
}

async function saveItem(event) {
  event.preventDefault(); const type = els.itemType.value; const id = els.itemId.value; const existing = id ? findItem(type,id) : null;
  const base = { id: id || uid(), title: els.itemTitle.value.trim(), notes: els.itemNotes.value.trim(), createdAt: existing?.createdAt || Date.now() };
  if (!base.title) return;
  const item = type === 'task' ? { ...base, dueDate:els.taskDate.value,dueTime:els.taskTime.value,priority:els.taskPriority.value,onCalendar:els.taskOnCalendar.checked,status:existing?.status||'open' }
    : type === 'goal' ? { ...base,targetDate:els.goalDate.value,progress:Number(els.goalProgress.value) }
    : { ...base,date:els.eventDate.value,time:els.eventTime.value };
  try { await persistItem(type,item); upsert(type==='task'?state.tasks:type==='goal'?state.goals:state.events,item); els.itemModal.close(); renderAll(); }
  catch(error) { console.error(error); setStorageStatus('Save failed',true); alert('This item could not be saved. Please try again.'); }
}

async function handleItemAction(event) {
  const button = event.target.closest('[data-action]'); if (!button) return;
  const { action, id } = button.dataset;
  if (action === 'toggle-task') { const task=state.tasks.find((item)=>item.id===id); if(task){const previous=task.status;task.status=task.status==='done'?'open':'done';try{await persistItem('task',task)}catch(error){task.status=previous;console.error(error);alert('That change could not be saved.');}} }
  if (action === 'edit-task') return openForm('task', state.tasks.find((item) => item.id === id));
  if (action === 'edit-goal') return openForm('goal', state.goals.find((item) => item.id === id));
  if (action === 'edit-event') return openForm('event', state.events.find((item) => item.id === id));
  if (action.startsWith('delete-')) {
    const type = action.replace('delete-',''); const item = findItem(type,id);
    if (!item || !confirm(`Delete “${item.title}”?`)) return;
    const list = type === 'task' ? state.tasks : type === 'goal' ? state.goals : state.events;
    try { if(currentUser) await removeCloudItem(type,id); list.splice(list.findIndex((entry)=>entry.id===id),1); }
    catch(error) { console.error(error); alert('That item could not be deleted.'); return; }
  }
  renderAll();
}

function findItem(type,id) { return (type === 'task' ? state.tasks : type === 'goal' ? state.goals : state.events).find((item) => item.id === id); }
function upsert(list,item) { const index = list.findIndex((entry) => entry.id === item.id); if (index >= 0) list[index] = item; else list.push(item); }

function exportData() {
  const blob = new Blob([JSON.stringify({ version:1, exportedAt:new Date().toISOString(), ...state },null,2)],{type:'application/json'});
  const url = URL.createObjectURL(blob); const link = document.createElement('a'); link.href=url; link.download=`daymark-backup-${todayKey()}.json`; link.click(); URL.revokeObjectURL(url);
}
async function importData(event) {
  const file = event.target.files[0]; if (!file) return;
  if(!cloudIsEmpty){alert('Import is available only when your cloud account is empty, preventing accidental overwrites.');event.target.value='';return;}
  try {
    const imported=JSON.parse(await file.text());
    if(!Array.isArray(imported.tasks)||!Array.isArray(imported.goals)||!Array.isArray(imported.events)) throw new Error('Invalid backup');
    const batches=[['daymark_tasks',imported.tasks.map(toCloudTask)],['daymark_goals',imported.goals.map(toCloudGoal)],['daymark_events',imported.events.map(toCloudEvent)]];
    for(const [table,rows] of batches){if(!rows.length)continue;const {error}=await cloudClient.from(table).upsert(rows,{onConflict:'user_id,id'});if(error)throw error;}
    state=await loadCloudState();cloudIsEmpty=false;els.migrateData.classList.add('hidden');renderAll();alert('Daymark backup imported into your account.');
  } catch(error) { console.error(error); alert('That backup could not be imported. Your existing cloud data was not replaced.'); }
  finally { event.target.value=''; }
}
async function resetData() {
  if(!confirm(`Reset every task, goal, and event ${currentUser?'in your cloud account':'on this device'}? Export first if you may need this data.`)) return;
  try {
    if(currentUser) for(const table of ['daymark_tasks','daymark_goals','daymark_events']) { const {error}=await cloudClient.from(table).delete().eq('user_id',currentUser.id); if(error) throw error; }
    state={tasks:[],goals:[],events:[]}; cloudIsEmpty=Boolean(currentUser); renderAll();
  } catch(error) { console.error(error); alert('Your data could not be reset.'); }
}

function uid(){return crypto.randomUUID?.() || `${Date.now()}-${Math.random().toString(16).slice(2)}`}
function todayKey(){return formatKey(new Date())}
function dateOffset(date,days){const copy=new Date(date);copy.setHours(12,0,0,0);copy.setDate(copy.getDate()+days);return formatKey(copy)}
function formatKey(date){return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`}
function parseDate(value){const [y,m,d]=String(value).split('-').map(Number);return new Date(y,m-1,d,12)}
function startOfMonth(date){return new Date(date.getFullYear(),date.getMonth(),1,12)}
function formatDate(value){if(!value)return 'No date';return parseDate(value).toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric'})}
function formatTime(value){if(!value)return '';const [h,m]=value.split(':').map(Number);return new Date(2000,0,1,h,m).toLocaleTimeString('en-US',{hour:'numeric',minute:'2-digit'})}
function relativeDate(value){if(!value)return 'No date';const diff=Math.round((parseDate(value)-parseDate(todayKey()))/DAY);if(diff===0)return 'Today';if(diff===1)return 'Tomorrow';if(diff===-1)return 'Yesterday';if(diff<0)return `${Math.abs(diff)}d overdue`;if(diff<7)return `In ${diff} days`;return formatDate(value)}
function sortByDateTime(a,b){return String(a.dueDate||a.date||a.targetDate||'9999').localeCompare(String(b.dueDate||b.date||b.targetDate||'9999'))||String(a.dueTime||a.time||'').localeCompare(String(b.dueTime||b.time||''))}
function priorityRank(priority){return {high:0,medium:1,low:2}[priority]??3}
function clamp(value,min,max){return Math.min(max,Math.max(min,Number(value)||0))}
function emptyMarkup(message){return `<div class="empty">${escapeHtml(message)}</div>`}
function escapeHtml(value){return String(value??'').replace(/[&<>'"]/g,(char)=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[char]))}
