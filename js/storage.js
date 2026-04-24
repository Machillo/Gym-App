function saveData(){

const data={
xp,
level,
xpToNextLevel,
stats,
activity,
tasks,
bioHistory
};

localStorage.setItem(
"cazadorGameState",
JSON.stringify(data)
);

}


function loadData(){

const saved=
localStorage.getItem(
"cazadorGameState"
);

if(!saved) return;

const data=
JSON.parse(saved);

xp=data.xp||0;
level=data.level||1;
xpToNextLevel=data.xpToNextLevel||1000;

Object.assign(
stats,
data.stats
);

}