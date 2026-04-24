const xpDisplay = document.getElementById("xp-total");
const levelDisplay = document.getElementById("level");
const strength = document.getElementById("stat-strength");
const intelligence = document.getElementById("stat-intelligence");
const discipline = document.getElementById("stat-discipline");
const prestige = document.getElementById("stat-prestige");
const agility = document.getElementById("stat-agility");
const vitality = document.getElementById("stats-vitality");

const activityInput = document.getElementById("activity-input");
const activityType = document.getElementById("activity-type");
const activityBTN = document.getElementById("activity-btn");
const activityDate = document.getElementById("activity-date");
const activityLog = document.getElementById("activity-log");

const bioBtn = document.getElementById("update-bio-btn");
const peso = document.getElementById("bio-peso");
const talla = document.getElementById("bio-talla");
const grasa = document.getElementById("bio-grasa");
const brazoR = document.getElementById("bio-brazo-r");
const brazoF = document.getElementById("bio-brazo-f");
const antebrazo = document.getElementById("bio-antebrazo");
const cintura = document.getElementById("bio-cintura");
const cadera = document.getElementById("bio-cadera");
const muslo = document.getElementById("biobio-muslo");
const pantorrilla = document.getElementById("bio-pantorrilla");
const triceps = document.getElementById("bio-triceps");
const subescapular = document.getElementById("bio-subescapular");
const biceps = document.getElementById("bio-biceps");
const cresta = document.getElementById("bio-cresta");
const supraespinal = document.getElementById("bio-supraespinal");
const abdominal = document.getElementById("bio-abdominal");
const musloA = document.getElementById("bio-muslo-a");
const pantorrillaM = document.getElementById("bio-pantorrilla-m");

const taskBTN = document.getElementById("task-btn");
const taskInput = document.getElementById("task-input");

const listPending = document.getElementById("list-pending");
const listProgress = document.getElementById("list-progress");
const listDone = document.getElementById("list-done");

const designToggleBtn = document.getElementById("design-toggle-btn");
const designOptions = document.getElementById("design-options");
const themeBtns = document.querySelectorAll(".theme-btn");

const xpCurrentDisplay = document.getElementById("xp-current");
const xpRequiredDisplay = document.getElementById("xp-required");
const xpBarFill = document.getElementById("xp-bar-fill");

let tasks = [];
let activity = [];
let bioHistory = [];
let xp = 0;
let level = 1;
let xpToNextLevel = 1000;
const stats = {strength:0, intelligence:0, discipline:0, prestige:0, agility:0, vitality:0};
const REWARDS = {
    mma_training: { xp: 80, strength: 3, agility: 2, discipline: 1, vitality: 1 },
    sparring:     { xp: 120, agility: 5, strength: 2, vitality: 2, prestige: 2 },
    fight_pro:    { xp: 500, prestige: 10, strength: 5, agility: 5, vitality: 5 },
    strength:     { xp: 60, strength: 4, discipline: 1, vitality: 1 },
    intelligence: { xp: 50, intelligence: 4, discipline: 2 },
    discipline:   { xp: 40, discipline: 5, vitality: 1 },
    rest:         { xp: 30, vitality: 4, intelligence: 1 }, 
    skill:        { xp: 20, intelligence: 1, agility: 1 }    
};

function addXP(type) {
    const data = REWARDS[type];
    if (!data) return; 
    
    xp += data.xp;

    for (const key in data) {
        if (key !== 'xp') {
            stats[key] += data[key];
        }
    }

    while (xp >= xpToNextLevel) {
        xp -= xpToNextLevel;
        level += 1;
        xpToNextLevel = Math.floor(xpToNextLevel * 1.25);
        alert(`¡SISTEMA ACTUALIZADO! Ahora eres Nivel ${level}`);
    }
    renderStats();
}

function renderStats() {
    levelDisplay.textContent = level;
    strength.textContent = stats.strength;
    intelligence.textContent = stats.intelligence;
    discipline.textContent = stats.discipline;
    prestige.textContent = stats.prestige;
    agility.textContent = stats.agility;
    vitality.textContent = stats.vitality;

    xpDisplay.textContent = xp; 
    xpCurrentDisplay.textContent = xp;
    xpRequiredDisplay.textContent = xpToNextLevel;

    const percentage = (xp / xpToNextLevel) * 100;
    xpBarFill.style.width = `${percentage}%`;
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

bioBtn.addEventListener('click', () => {
    
    const newBio = {
        fecha: new Date().toLocaleDateString(),
        peso: parseFloat(peso.value) || 0,
        grasa: parseFloat(grasa.value) || 0,
        sumatoriaPliegues: (parseFloat(triceps.value) || 0) + 
                           (parseFloat(subescapular.value) || 0) + 
                           (parseFloat(abdominal.value) || 0)
    };

    if (bioHistory.length > 0) {
        const lastBio = bioHistory[bioHistory.length - 1];
        if (newBio.sumatoriaPliegues < lastBio.sumatoriaPliegues) {
            xp += 100; 
            stats.discipline += 2;
            stats.vitality += 2;
        }
    }

    bioHistory.push(newBio);
    addXP('rest'); // Usamos 'rest' o una categoría neutra para actualizar stats
    renderBioTable(); // Esta función la crearemos luego para ver la tabla
    alert("Datos biométricos sincronizados con el sistema.");
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

designToggleBtn.addEventListener('click', () => {
    designOptions.classList.toggle('hidden');
});

themeBtns.forEach(btn => {
    btn.addEventListener('click', () => {
        const chosenColor = btn.getAttribute('data-color');
        
        document.documentElement.style.setProperty('--system-blue', chosenColor);
        
        designOptions.classList.add('hidden');
    });
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

function xpNegative () {
    newDay != activityLog;
}