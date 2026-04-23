const xpDisplay = document.getElementById("xp-total");
const levelDisplay = document.getElementById("level");
const statStrength = document.getElementById("stat-strength");
const statIntelligence = document.getElementById("stat-intelligence");
const statDiscipline = document.getElementById("stat-discipline");
const statSkill = document.getElementById("stat-skill");

const activityInput = document.getElementById("activity-input");
const activityType = document.getElementById("activity-type");
const activityBTN = document.getElementById("activity-btn");
const activityDate = document.getElementById("activity-date");
const activityLog = document.getElementById("activity-log");

const taskBTN = document.getElementById("task-btn");
const taskInput = document.getElementById("task-input");

const listPending = document.getElementById("list-pending");
const listProgress = document.getElementById("list-progress");
const listDone = document.getElementById("list-done");

let tasks = [];
let activity = [];
let xp = 0;
let level = 1;
const stats = {statStrength:0, statIntelligence:0, statDiscipline:0, statSkill:0};

function addXP(type) {
        switch (type) {
            case 'strength':
              xp += 50;
              stats.statStrength += 1;                
              break ;
            case 'intelligence':
              xp += 40;
              stats.statIntelligence += 1;
              break;
            case 'discipline':
              xp += 30;
              stats.statDiscipline += 1;
              break;
            case 'skill':
              xp += 20;
              stats.statSkill += 1;
              break;
            default:
        }

        if (xp >= 1000){
            level +=1;
            xp -= 1000;
            alert("Nuevo nivel!")
        }
        renderStats();
}

function renderStats() {
    xpDisplay.textContent = xp;
    levelDisplay.textContent = level;
    statStrength.textContent = stats.statStrength;
    statIntelligence.textContent = stats.statIntelligence;
    statDiscipline.textContent = stats.statDiscipline;
    statSkill.textContent = stats.statSkill;
}

activityBTN.addEventListener('click', () => {
    const text = activityInput.value.trim();
    if (text !== '') {
        const type = activityType.value;
        const newLog = {
            actividad: text,
            tipo: activityType.value,
            fecha: activityDate.value
        }
        activity.push(newLog);
        addXP(type);
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