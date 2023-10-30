const toggleNav = () => {
  document.querySelector(".menu").classList.toggle("active");
};

const daysTag = document.querySelector(".days");
const currentDate = document.querySelector(".current-date");
const prevMonthBtn = document.querySelector("#prev");
const nextMonthBtn = document.querySelector("#next");
const eventDateInput = document.querySelector("#event-date");
const eventTimeInput = document.querySelector("#event-time");
const eventDescriptionInput = document.querySelector("#event-description");

let date = new Date();
let currentYear = date.getFullYear();
let currentMonth = date.getMonth();
let selectedDate = new Date(); // Initialize selected date to the current date

const months = [
  "January", "February", "March", "April", "May", "June", "July",
  "August", "September", "October", "November", "December"
];

const renderCalendar = () => {
  const firstDayOfMonth = new Date(currentYear, currentMonth, 1).getDay();
  const lastDateOfMonth = new Date(currentYear, currentMonth + 1, 0).getDate();
  const lastDayOfMonth = new Date(currentYear, currentMonth, lastDateOfMonth).getDay();
  const lastDateOfLastMonth = new Date(currentYear, currentMonth, 0).getDate();

  let liTag = "";
  for (let i = firstDayOfMonth; i > 0; i--) {
      const day = String(lastDateOfLastMonth - i + 1).padStart(2, '0');
      liTag += `<li class="inactive">${day}<div class="events"></div></li>`;
  }
  for (let i = 1; i <= lastDateOfMonth; i++) {
      const isToday = i === date.getDate() && currentMonth === date.getMonth() && currentYear === date.getFullYear() ? "active" : "";
      const day = String(i).padStart(2, '0');
      liTag += `<li class="${isToday}" data-date="${currentYear}-${String(currentMonth + 1).padStart(2, '0')}-${day}">
      ${day}
      <div class="events"></div>
    </li>`;
  }
  for (let i = lastDayOfMonth; i < 6; i++) {
      const day = String(i - lastDayOfMonth + 1).padStart(2, '0');
      liTag += `<li class="inactive">${day}<div class="events"></div></li>`;
  }

  currentDate.innerText = `${months[currentMonth]} ${currentYear}`;
  daysTag.innerHTML = liTag;
  fetchAndDisplayEvents(); 
};

const fetchAndDisplayEvents = () => {
  const url = 'https://raw.githubusercontent.com/gbujoreanu/gbujoreanu.github.io/main/Projects/Part_5/calendar/calendar.json';
  fetch(url)
      .then(response => response.json())
      .then(data => {
          const events = data.events;
          events.forEach(event => {
              const eventDate = new Date(event.date);
              if (eventDate.getMonth() + 1 === currentMonth + 1 && eventDate.getFullYear() === currentYear) {
                  const dayElement = daysTag.querySelector(`li[data-date="${event.date}"] .events`);
                  if (dayElement) {
                      const eventElement = document.createElement("div");
                      eventElement.className = "event";
                      eventElement.textContent = `${event.time}: ${event.description}`;
                      dayElement.appendChild(eventElement);
                  }
              }
          });
      })
      .catch(error => console.error('Error fetching events:', error));
};

window.onload = () => {
  document.getElementById("menuToggle").onclick = toggleNav;
  renderCalendar();
};

prevMonthBtn.addEventListener("click", () => {
  currentMonth--;
  if (currentMonth < 0) {
      currentMonth = 11;
      currentYear--;
  }
  selectedDate.setMonth(currentMonth);
  selectedDate.setFullYear(currentYear);
  renderCalendar();
});

nextMonthBtn.addEventListener("click", () => {
  currentMonth++;
  if (currentMonth > 11) {
      currentMonth = 0;
      currentYear++;
  }
  selectedDate.setMonth(currentMonth);
  selectedDate.setFullYear(currentYear);
  renderCalendar();
});

document.getElementById("event-form").addEventListener("submit", function (e) {
  e.preventDefault(); // Prevent form submission
  const dateToAddEvent = eventDateInput.value;
  const timeToAddEvent = eventTimeInput.value;
  const descriptionToAddEvent = eventDescriptionInput.value;

  const matchingDay = daysTag.querySelector(`li[data-date="${dateToAddEvent}"]`);

  if (matchingDay) {
      const eventElement = document.createElement("div");
      eventElement.textContent = `${formatDate(selectedDate)} ${timeToAddEvent}: ${descriptionToAddEvent}`;
      eventElement.className = "event";
      const eventsContainer = matchingDay.querySelector(".events");
      eventsContainer.appendChild(eventElement);

      eventDateInput.value = "";
      eventTimeInput.value = "";
      eventDescriptionInput.value = "";
  }
});

function formatDate(date) {
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const year = date.getFullYear();
  return `${month}/${day}/${year}`;
}
