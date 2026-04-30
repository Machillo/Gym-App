const btnLogOut = document.getElementById("logout-btn");
const toggleBtn = document.getElementById("design-toggle-btn");
const themeBtn = document.querySelectorAll(".theme-btn");

const activityInput = document.getElementById("activity-input");
const activityType = document.getElementById("activity-type");
const activityBtn = document.getElementById("activity-btn");
const activityDate = document.getElementById("activity-date");
const activityLog = document.getElementById("activity-log");

const designOptions = document.getElementById("design-options");

const xpCurrentDisplay = document.getElementById("xp-current");
const xpRequiredDisplay = document.getElementById("xp-required");
const xpBarFill = document.getElementById("xp-bar-fill");


const renderStats = () => {
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

const renderLog = () => {
    activityLog.innerHTML = "";
    activity.forEach((logs) => {
        const li = document.createElement('li');
        li.classList.add('log-item');
        li.innerHTML = `<span>[${logs.tipo}] ${logs.actividad}</span>`;
        activityLog.appendChild(li);
    });
}

const changeTheme = () => {
    themeBtn.forEach(btn => {
        btn.addEventListener('click', () => {
            const chosenColor = btn.getAttribute('data-color');
            document.documentElement.style.setProperty('--system-blue', chosenColor);
            designOptions.classList.add('hidden');
            saveData(); 
        });
    });
}

const bindEvents = () => {
    btnLogOut.addEventListener('click', logout);
    toggleBtn.addEventListener('click', toggleDesignPanel);
    activityBtn.addEventListener('click', handleActivitySubmit);

    changeTheme();
}

const renderTasks = () => {
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

const toggleTaskStatus = (index) => {
    const task = tasks[index];

     if (task.estado === "list-pending") {
        task.estado = "list-progress";
    } else if (task.estado === "list-progress") {
        task.estado = "list-done";
    }
    renderTasks();
    saveData();
}

const initDashboard = () => {
    loadData(); 
    xpNegative();  
    bindEvents(); 
    renderStats(); 
    renderLog();
    renderTasks();

}

const handleActivitySubmit = () => {
    const text = activityInput.value.trim();
    if (text !== '') {
        const type = activityType.value;
        const newLog = {
            actividad: text,
            tipo: activityType.value,
            fecha: activityDate.value || new Date().toLocaleDateString()
        }
        activity.push(newLog);
        addXP(type);
        saveData();
        activityInput.value = "";
        renderLog();
    }
}


const toggleDesignPanel = () => {
     designOptions.classList.toggle('hidden');
}

const logout = () => {
    const answer = confirm("¿Estás seguro de que quieres cerrar sesión?");
    if (answer) {
        localStorage.removeItem('rememberUser');
        window.location.href = "../index.html";
    }
}


initDashboard();