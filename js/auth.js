const profileKenneth = document.querySelector('.active-profile');
const loginPanel = document.querySelector('#login-panel');
const profileTaylor = document.querySelector('.locked');
const loginForm = document.getElementById('login-form');
const userInput = document.getElementById('user-input');
const passInput = document.getElementById('pass-input');
const rememberMe = document.getElementById('remember');

let selectProfile = "";

profileKenneth.addEventListener('click', function() {
    loginPanel.classList.remove('hidden');
    selectProfile = "Kenneth";
    setTimeout(() => {
        loginPanel.classList.add('active');
    }, 10);
});

profileTaylor.addEventListener('click', function () {
    loginPanel.classList.remove('hidden');
    selectProfile = "Taylor";
    setTimeout(() => loginPanel.classList.add('active'), 10);
});

function initSystem () {
    if (localStorage.getItem('user_kenneth') === null) {
        let user = prompt("Crea tu nombre de usuario:");
        let pass = prompt("Crea tu contraseña:");

        localStorage.setItem('user_kenneth', user);
        localStorage.setItem('pass_kenneth', pass);
    }
}


loginForm.addEventListener('submit', function (event) {
    event.preventDefault()
    let text = userInput.value;
    let text2 = passInput.value;
    let user = localStorage.getItem('user_' + selectProfile.toLowerCase());
    let pass = localStorage.getItem('pass_' + selectProfile.toLowerCase());

    if (text === user && text2 === pass) {
        if (rememberMe.checked) {
            localStorage.setItem('rememberUser', selectProfile);
        } else {
            localStorage.removeItem('rememberUser');
        }
        window.location.href = "pages/dashboard.html";
    } else {
        alert("Acceso Denegado");
    }
});

function checkAutoLogin() {
    const sesionSave = localStorage.getItem('rememberUser');
    
    if (sesionSave) {
        console.log("Sesión activa detectada para: " + sesionSave);
        window.location.href = "pages/dashboard.html";
    }
}

checkAutoLogin();
initSystem();