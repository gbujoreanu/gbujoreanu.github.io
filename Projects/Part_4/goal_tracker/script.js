const toggleNav = () => {
    document.querySelector(".menu").classList.toggle("active");
};

window.onload = () => {
    document.getElementById("menuToggle").onclick = toggleNav;
};

document.getElementById("add-goal-form").addEventListener("submit", function(event) {
    event.preventDefault();

    const goalName = document.getElementById("goal-name").value;
    const goalDescription = document.getElementById("goal-description").value;
    const goalDueDate = document.getElementById("goal-due-date").value;
    const goalProgress = document.getElementById("goal-progress").value;
    const goalNotes = document.getElementById("goal-notes").value;

    addNewGoal(goalName, goalDescription, goalDueDate, goalProgress, goalNotes);

    // Clear form
    event.target.reset();
    document.getElementById("progress-display").textContent = "0%";
});

function addNewGoal(name, description, dueDate, progress, notes) {
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

    goalElement.querySelector(".edit-goal").addEventListener("click", function() {
        document.getElementById("goal-name").value = name;
        document.getElementById("goal-description").value = description;
        document.getElementById("goal-due-date").value = dueDate;
        document.getElementById("goal-progress").value = progress;
        document.getElementById("goal-notes").value = notes;

        goalElement.remove();
    });

    goalElement.querySelector(".delete-goal").addEventListener("click", function() {
        goalElement.remove();
    });

    document.getElementById("goals-list").appendChild(goalElement);
}

// Update progress display when the range slider changes
document.getElementById("goal-progress").addEventListener("input", function(event) {
    document.getElementById("progress-display").textContent = event.target.value + "%";
});
