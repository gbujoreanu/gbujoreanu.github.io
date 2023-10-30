const toggleNav = () => {
    document.querySelector(".menu").classList.toggle("active");
};

window.onload = () => {
    document.getElementById("menuToggle").onclick = toggleNav;
};

function loadAndDisplayTasks() {
    fetch('tasks.json')
      .then((response) => response.json())
      .then((data) => {
        const tasksList = document.getElementById('tasks-list');
        tasksList.innerHTML = '';
  
        data.forEach((task) => {
          const taskElement = document.createElement('div');
          taskElement.classList.add('task');
          taskElement.innerHTML = `
            <h3 class="task-name">${task.name}</h3>
            <p class="task-description">${task.description}</p>
            <p class="task-due-date">Due Date: ${task.dueDate}</p>
            <p class="task-priority">Priority: ${task.priority}</p>
            <p class="task-status">Status: ${task.status}</p>
            <button class="edit-task">Edit</button>
            <button class="delete-task">Delete</button>
          `;
  
          taskElement.querySelector('.edit-task').addEventListener('click', () => {
            // Add your code for editing a task here
          });
  
          taskElement.querySelector('.delete-task').addEventListener('click', () => {
            // Add your code for deleting a task here
          });
  
          tasksList.appendChild(taskElement);
        });
      })
      .catch((error) => {
        console.error('Error loading tasks:', error);
      });
  }
  
  window.onload = loadAndDisplayTasks;
  
  function saveDataToJson(data) {
    fetch('tasks.json', {
      method: 'PUT',
      body: JSON.stringify(data),
      headers: {
        'Content-Type': 'application/json',
      },
    })
      .then((response) => {
        if (!response.ok) {
          throw new Error('Failed to save data to JSON file.');
        }
      })
      .catch((error) => {
        console.error('Error saving data to JSON file:', error);
      });
  }
  
  function saveTaskData(taskData) {
    fetch('tasks.json')
      .then((response) => response.json())
      .then((data) => {
        data.push(taskData);
        saveDataToJson(data);
        loadAndDisplayTasks(); // Refresh the task list after adding a task
      })
      .catch((error) => {
        console.error('Error adding new task:', error);
      });
  }
  
  document.getElementById('task-form').addEventListener('submit', function (event) {
    event.preventDefault();
  
    const taskName = document.getElementById('task-name').value;
    const taskDescription = document.getElementById('task-description').value;
    const taskDueDate = document.getElementById('task-due-date').value;
    const taskPriority = document.getElementById('task-priority').value;
    const taskStatus = document.getElementById('task-status').value;
  
    saveTaskData({
      name: taskName,
      description: taskDescription,
      dueDate: taskDueDate,
      priority: taskPriority,
      status: taskStatus,
    });
  
    document.getElementById('task-form').reset(); // Clear the form after submission
  });
  