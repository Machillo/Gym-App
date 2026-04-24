let xp=0;
let level=1;
let xpToNextLevel=1000;

const stats={
strength:0,
agility:0,
intelligence:0,
discipline:0,
vitality:0,
prestige:0
};

const REWARDS={
 mma_training:{xp:80,strength:3},
 sparring:{xp:120,agility:4},
 strength:{xp:60,strength:4},
 intelligence:{xp:50,intelligence:4},
 discipline:{xp:40,discipline:4},
 rest:{xp:30,vitality:2}
};

function addXP(type){
const data=REWARDS[type];
if(!data) return;

xp+=data.xp;

for(let key in data){
if(key!=="xp"){
stats[key]+=data[key];
}
}

while(xp>=xpToNextLevel){
 xp-=xpToNextLevel;
 level++;
 xpToNextLevel=Math.floor(
 xpToNextLevel*1.25
 );
}

renderStats();
saveData();
}