const toggleNav = () => {
    document.querySelector(".menu").classList.toggle("active");
};

window.onload = () => {
    document.getElementById("menuToggle").onclick = toggleNav;
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
    const lastDateofMonth = new Date(currentYear, currentMonth + 1, 0).getDate();
    const lastDayofMonth = new Date(currentYear, currentMonth, lastDateofMonth).getDay();
    const lastDateofLastMonth = new Date(currentYear, currentMonth, 0).getDate();
  
    let liTag = "";
    for (let i = firstDayOfMonth; i > 0; i--) {
      const day = String(lastDateofLastMonth - i + 1).padStart(2, '0');
      liTag += `<li class="inactive">${day}<div class="events"></div></li>`;
    }
    for (let i = 1; i <= lastDateofMonth; i++) {
      const isToday = i === selectedDate.getDate() && currentMonth === selectedDate.getMonth()
        && currentYear === selectedDate.getFullYear() ? "active" : "";
      const day = String(i).padStart(2, '0');
      liTag += `<li class="${isToday}" data-date="${currentYear}-${currentMonth + 1}-${day}">
        ${day}
        <div class="events"></div>
      </li>`;
    }
    for (let i = lastDayofMonth; i < 6; i++) {
      const day = String(i - lastDayofMonth + 1).padStart(2, '0');
      liTag += `<li class="inactive">${day}<div class="events"></div></li>`;
    }
  
    currentDate.innerText = `${months[currentMonth]} ${currentYear}`;
    daysTag.innerHTML = liTag;
  };

// Initial rendering
renderCalendar();

// Function to navigate to the previous month
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

// Function to navigate to the next month
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

// Function to format a date object as "mm/dd/yyyy"
function formatDate(date) {
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const year = date.getFullYear();
    return `${month}/${day}/${year}`;
  }
  
  // Add event button click event
  document.getElementById("event-form").addEventListener("submit", function (e) {
    e.preventDefault(); // Prevent form submission
    const dateToAddEvent = eventDateInput.value;
    const timeToAddEvent = eventTimeInput.value;
    const descriptionToAddEvent = eventDescriptionInput.value;
  
    // Find the day element with a matching data-date attribute
    const matchingDay = daysTag.querySelector(`li[data-date="${dateToAddEvent}"]`);
  
    if (matchingDay) {
      // Create a new event element
      const eventElement = document.createElement("div");
      eventElement.textContent = `${formatDate(selectedDate)} ${timeToAddEvent}: ${descriptionToAddEvent}`;
      eventElement.className = "event";
  
      // Append the event to the day's events container
      const eventsContainer = matchingDay.querySelector(".events");
      eventsContainer.appendChild(eventElement);
  
      // Clear the form inputs
      eventDateInput.value = "";
      eventTimeInput.value = "";
      eventDescriptionInput.value = "";
    }
});
