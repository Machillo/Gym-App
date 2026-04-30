const btnLogOut = document.getElementById("logout-btn");
const toggleBtn = document.getElementById("design-toggle-btn");
const themeBtn = document.querySelectorAll(".theme-btn");

const designOptions = document.getElementById("design-options");

const xpDisplay = document.getElementById("xp-total");
const levelDisplay = document.getElementById("level");

const xpCurrentDisplay = document.getElementById("xp-current");
const xpRequiredDisplay = document.getElementById("xp-required");
const xpBarFill = document.getElementById("xp-bar-fill");

const strength = document.getElementById("stat-strength");
const intelligence = document.getElementById("stat-intelligence");
const discipline = document.getElementById("stat-discipline");
const prestige = document.getElementById("stat-prestige");
const agility = document.getElementById("stat-agility");
const vitality = document.getElementById("stat-vitality");


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
};


const changeTheme = () => {
    themeBtn.forEach(btn => {
        btn.addEventListener('click', () => {
            const chosenColor = btn.getAttribute('data-color');
            document.documentElement.style.setProperty('--system-blue', chosenColor);
            designOptions.classList.add('hidden');
            saveData();
        });
    });
};



const bindEvents = () => {
    btnLogOut.addEventListener('click', logout);
    toggleBtn.addEventListener('click', toggleDesignPanel);

    changeTheme();
};


const initDashboard = () => {
    loadData();
    xpNegative();

    bindEvents();
    renderStats();
};


const toggleDesignPanel = () => {
    designOptions.classList.toggle('hidden');
};

const logout = () => {
    const answer = confirm("¿Estás seguro de que quieres cerrar sesión?");
    if (answer) {
        localStorage.removeItem('rememberUser');
        window.location.href = "../index.html";
    }
};


initDashboard();