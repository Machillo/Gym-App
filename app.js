const xpDisplay = document.getElementById("xp-total");
const levelDisplay = document.getElementById("level");
const statStrength = document.getElementById("stat-strength");

const activityInput = document.getElementById("activity-input");
const activityType = document.getElementById("activity-type");
const activityBTN = document.getElementById("activity-btn");
const activityDate = document.getElementById("activity-date");
const activityLog = document.getElementById('activity-log');

const taskBTN = document.getElementById("task-btn");
const taskInput = document.getElementById("task-input");

const listPending = document.getElementById('list-pending');
const listProgress = document.getElementById('list-progress');
const listDone = document.getElementById('list-done');

let tasks = [];
let activity = [];

activityBTN.addEventListener('click', () => {
    const text = activityInput.value.trim();
    if (text !== '') {
        const newLog = {
            actividad: text,
            tipo: activityType.value,
            fecha: activityDate.value
        }
        activity.push(newLog);
        activityInput.value = "";
        renderLog();
    }
    
});

taskBTN.addEventListener('click', () => {
    const text = taskInput.value.trim();
    if (text !== '') {
        const newTask = {
            texto: text,
            estado: "list-pending"
        }
        tasks.push(newTask);
        taskInput.value = "";
        renderTasks();
    }
});

function renderLog () {
    activityLog.innerHTML = "";

    activity.forEach((logs, index) => {
        const li = document.createElement('li');

        li.classList.add('log-item');
        li.innerHTML = `
            <span>
                <span class="log-category">[${logs.tipo}]</span> 
                ${logs.actividad}
            </span>
            <span class="log-date">${logs.fecha || 'Sin fecha'}</span>
        `;

        activityLog.appendChild(li);
    });
}

function renderTasks () {
    listPending.innerHTML = "";
    listProgress.innerHTML = "";
    listDone.innerHTML = "";

    tasks.forEach((task, index) => {
        const li = document.createElement('li');
        const checkbox = document.createElement('input');
        
        checkbox.type = "checkbox";
        checkbox.checked = task.estado === "list-done";
        checkbox.onclick = () => toggleTaskStatus(index);

        const span = document.createElement('span');

        span.textContent = task.texto;
        span.style.marginLeft = "10px";

        li.appendChild(checkbox);
        li.appendChild(span);

        if (task.estado === "list-pending") {
            listPending.appendChild(li);
        } else if (task.estado === "list-progress") {
            listProgress.appendChild(li);
        } else if (task.estado === "list-done") {
            listDone.appendChild(li);
        }
    });
}

function toggleTaskStatus(index) {
    const task = tasks[index];

     if (task.estado === "list-pending") {
        task.estado = "list-progress";
    } else if (task.estado === "list-progress") {
        task.estado = "list-done";
    }
    renderTasks();
}