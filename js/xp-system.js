let tasks = [];
let activity = [];
let bioHistory = [];
let xp = 0;
let level = 1;
let xpToNextLevel = 1000;
const stats = { strength: 0, intelligence: 0, discipline: 0, prestige: 0, agility: 0, vitality: 0 };

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
    saveData();
}

function xpNegative() {
    if (activity.length === 0) return; 

    const lastActivity = activity[activity.length - 1];
    const lastDate = new Date(lastActivity.fecha);
    const today = new Date();

    const diffTime = Math.abs(today - lastDate);
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));

    if (diffDays > 7) {
        const penalty = (diffDays - 7) * 20; 
        xp -= penalty;
        if (xp < 0) xp = 0; 
        alert(`¡OXIDACIÓN DETECTADA! Perdiste ${penalty} XP.`);
        renderStats();
    }
}