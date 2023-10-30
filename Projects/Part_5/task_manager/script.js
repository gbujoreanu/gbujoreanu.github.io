const toggleNav = () => {
    document.querySelector(".menu").classList.toggle("active");
  };
  
  window.onload = () => {
    document.getElementById("menuToggle").onclick = toggleNav;
    loadAndDisplayTasks();
  };
  
  function loadAndDisplayTasks() {
    const url = 'https://raw.githubusercontent.com/gbujoreanu/gbujoreanu.github.io/main/Projects/Part_5/task_manager/tasks.json';
  
    fetch(url)
      .then(response => response.json())
      .then(data => {
        const tasksList = document.getElementById('data-container');
        tasksList.innerHTML = '';
  
        data.forEach(task => {
          const taskElement = document.createElement('div');
          taskElement.classList.add('task');
          taskElement.innerHTML = `
            <h3 class="task-name">${task.name}</h3>
            <p class="task-description">${task.description}</p>
            <p class="task-due-date">Due Date: ${task.due_date}</p>
            <p class="task-priority">Priority: ${task.priority}</p>
            <p class="task-status">Status: ${task.status}</p>
            <button class="edit-task">Edit</button>
            <button class="delete-task">Delete</button>
          `;
  
          taskElement.querySelector('.edit-task').addEventListener('click', () => {
            // Code for editing a task
          });
  
          taskElement.querySelector('.delete-task').addEventListener('click', () => {
            // Code for deleting a task
          });
  
          tasksList.appendChild(taskElement);
        });
      })
      .catch(error => {
        console.error('Error loading tasks:', error);
      });
  }
  
  document.getElementById('task-form').addEventListener('submit', function(event) {
    event.preventDefault();
  
    const taskName = document.getElementById('task-name').value;
    const taskDescription = document.getElementById('task-description').value;
    const taskDueDate = document.getElementById('task-due-date').value;
    const taskPriority = document.getElementById('task-priority').value;
    const taskStatus = document.getElementById('task-status').value;
  
    document.getElementById('task-form').reset();
  });
  