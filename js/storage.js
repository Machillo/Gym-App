function saveData() {
    const gameData = {
        tasks,
        activity,
        bioHistory,
        xp,
        level,
        xpToNextLevel,
        stats
    };
    localStorage.setItem('cazadorGameState', JSON.stringify(gameData));
}

function loadData() {
    const saved = localStorage.getItem('cazadorGameState');
    if (saved) {
        const data = JSON.parse(saved);
        tasks = data.tasks || [];
        activity = data.activity || [];
        bioHistory = data.bioHistory || [];
        xp = data.xp || 0;
        level = data.level || 1;
        xpToNextLevel = data.xpToNextLevel || 1000;
        Object.assign(stats, data.stats);
    }
}