const toggleNav = () => {
    document.querySelector(".menu").classList.toggle("active");
  };
  
  const loadAndDisplayGoals = () => {
    const url = 'https://raw.githubusercontent.com/gbujoreanu/gbujoreanu.github.io/main/Projects/Part_5/goal_tracker/goals.json';
  
    fetch(url)
      .then(response => response.json())
      .then(data => {
        data.forEach(goal => addNewGoal(goal.name, goal.description, goal.due_date, goal.progress, goal.notes));
      })
      .catch(error => {
        console.error('Error loading goals:', error);
      });
  };
  
  const addNewGoal = (name, description, dueDate, progress, notes) => {
    const goalElement = document.createElement("div");
    goalElement.classList.add("goal");
    goalElement.innerHTML = `
      <h3 class="goal-name">${name}</h3>
      <p class="goal-description">${description}</p>
      <p class="goal-due-date">Due Date: ${dueDate}</p>
      <p class="goal-progress">Progress: ${progress}%</p>
      <p class="goal-notes">${notes}</p>
      <button class="edit-goal">Edit</button>
      <button class="delete-goal">Delete</button>
    `;
  
    goalElement.querySelector(".edit-goal").addEventListener("click", () => {
      document.getElementById("goal-name").value = name;
      document.getElementById("goal-description").value = description;
      document.getElementById("goal-due-date").value = dueDate;
      document.getElementById("goal-progress").value = progress;
      document.getElementById("goal-notes").value = notes;
      document.getElementById("progress-display").textContent = progress + "%";
  
      goalElement.remove();
    });
  
    goalElement.querySelector(".delete-goal").addEventListener("click", () => {
      goalElement.remove();
    });
  
    document.getElementById("goals-list").appendChild(goalElement);
  };
  
  window.onload = () => {
    document.getElementById("menuToggle").onclick = toggleNav;
    loadAndDisplayGoals();
  };
  
  document.getElementById("add-goal-form").addEventListener("submit", (event) => {
    event.preventDefault();
  
    const goalName = document.getElementById("goal-name").value;
    const goalDescription = document.getElementById("goal-description").value;
    const goalDueDate = document.getElementById("goal-due-date").value;
    const goalProgress = document.getElementById("goal-progress").value;
    const goalNotes = document.getElementById("goal-notes").value;
  
    addNewGoal(goalName, goalDescription, goalDueDate, goalProgress, goalNotes);
  
    event.target.reset();
    document.getElementById("progress-display").textContent = "0%";
  });
  
  document.getElementById("goal-progress").addEventListener("input", (event) => {
    document.getElementById("progress-display").textContent = event.target.value + "%";
  });
  