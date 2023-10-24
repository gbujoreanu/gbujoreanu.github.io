const toggleNav = () => {
    document.querySelector(".menu").classList.toggle("active");
};

window.onload = () => {
    document.getElementById("menuToggle").onclick = toggleNav;
};

let currentEditingTask = null;

document.getElementById("task-form").addEventListener("submit", function(event) {
    event.preventDefault();  // Prevent the form from submitting and refreshing the page

    const taskName = document.getElementById("task-name").value;
    const taskDescription = document.getElementById("task-description").value;
    const taskDueDate = document.getElementById("task-due-date").value;
    const taskPriority = document.getElementById("task-priority").value;
    const taskStatus = document.getElementById("task-status").value;

    if (currentEditingTask) {
        // Update the task details in the DOM
        currentEditingTask.querySelector(".task-name").innerText = taskName;
        currentEditingTask.querySelector(".task-description").innerText = taskDescription;
        currentEditingTask.querySelector(".task-due-date").innerText = `Due Date: ${taskDueDate}`;
        currentEditingTask.querySelector(".task-priority").innerText = `Priority: ${taskPriority}`;
        currentEditingTask.querySelector(".task-status").innerText = `Status: ${taskStatus}`;

        // Clear form and editing state
        currentEditingTask = null;
        document.getElementById("task-form").reset();
    } else {
        addNewTask(taskName, taskDescription, taskDueDate, taskPriority, taskStatus);
    }
});

function addNewTask(name, description, dueDate, priority, status) {
    const taskElement = document.createElement("div");
    taskElement.classList.add("task");
    taskElement.innerHTML = `
        <h3 class="task-name">${name}</h3>
        <p class="task-description">${description}</p>
        <p class="task-due-date">Due Date: ${dueDate}</p>
        <p class="task-priority">Priority: ${priority}</p>
        <p class="task-status">Status: ${status}</p>
        <button class="edit-task">Edit</button>
        <button class="delete-task">Delete</button>
    `;

    taskElement.querySelector(".edit-task").addEventListener("click", function() {
        document.getElementById("task-name").value = name;
        document.getElementById("task-description").value = description;
        document.getElementById("task-due-date").value = dueDate;
        document.getElementById("task-priority").value = priority;
        document.getElementById("task-status").value = status;
        
        currentEditingTask = taskElement;
    });

    taskElement.querySelector(".delete-task").addEventListener("click", function() {
        document.getElementById("tasks-list").removeChild(taskElement);
    });

    document.getElementById("tasks-list").appendChild(taskElement);
}
