/*
const loadFucntion = () => {
    const helloP = document.getElementById("date")
    helloP.innerHTML = "Hello"
}


(Waits to load the fuction before calling) 

window.onload = loadFunction;
*/


/*
window.onload = () => {
    const helloP = document.getElementById("date")
    helloP.innerHTML = "Hello"

}
*/

/*  (Changes text when called)  

const changeText = () => {
    const helloP = document.getElementById("date")
    helloP.innerHTML = "Hi";

}

   (Calls changeText when button is clicked)   

window.onload = () => {
    const clickButton = document.getElementById("button-click")
    clcickButton.onclick = changeText;
}

*/

const changeText = () => {
    const helloP = document.getElementById("date")
    helloP.innerHTML = "Hi";
    helloP.classList.add("special")

}

window.onload = () => {
    document.getElementById("button-click").onclick = changeText;
}


const show = () => {

}

const hide = () => {

}

window.onload = () => {
    document.getElementById("button-click").onclick = changeText;
    document.getElementById("button-show").onclick = show;
    document.getElementById("button-hide").onclick = hide;

}











