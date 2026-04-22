let activities = [];
let stats = {strength:0, intelligence:0, discipline:0, skill:0};
let xp = 0;
let level = 1;

const activityBTN = document.getElementById("activity-btn");
const taskBTN = document.getElementById("task-btn");
const listPending = document.getElementById('list-pending');
const listProgress = document.getElementById('list-progress');
const listDone = document.getElementById('list-done');

function addActivity() {
    const text = input.value.trim();

    if (text !== "") {
        const newTasks = {
            texto: text,
            estado: "list-pending"
        };
        activities.push(newTasks);
        input.value = "";
        renderTasks();
    }
}

function addTask() {
    const text = input.value.trim();

    if (text !== "") {
        const newTasks = {
            texto: text,
            estado: "listPending"
        };
        activities.push(newTasks);
        input.value = "";
        renderTasks();
    }
}

function toggleTaskStatus(index) {
    const task = taks[index];

    if (task.estado === "listPending") {
        task.estado = "listProgress";
    } else if (task.estado === "listProgress") {
        task.estado = "listDone";
    }
    renderTasks();
}

function renderTasks() {
    listPending.innerHTML = "";
    listProgress.innerHTML = "";
    listDone.innerHTML = "";

    tasks.forEach((task, index) => {
        const li = document.createElement('li');

        const checkbox = document.createElement('input');
        checkbox.type = "checkbox";
        checkbox.checked = task.estado === "done";
        checkbox.onclick = () => toggleTaskStatus(index);

        const span = document.createElement('span');
        span.textContent = task.texto;
        span.style.marginLeft = "10px";

        li.appendChild(checkbox);
        li.appendChild(span);

        if (task.estado === "pending") {
            listPending.appendChild(li);
        } else if (task.estado === "progress") {
            listProgress.appendChild(li);
        } else if (task.estado === "done") {
            listDone.appendChild(li);
        }
    });
}

activityBTN.addEventListener('click', addActivity);
taskBTN.addEventListener('click', addTask);

input.addEventListener('keypress', (e) => {
    if (e.key === 'Enter') {
        addTask();
    }
});