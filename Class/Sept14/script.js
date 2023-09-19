console.log("George");

const add = (a,b) => a+b;

console.log(add(5,6));


const square = a => a*a;

console.log(square(5));

const hello = () => console.log("Hello George!");

hello();

const helloSpecific = userName => console.log("Hello "+userName+"!");

helloSpecific("George")

const helloFullName =(firstName, lastName) => {
    console.log("Hello "+firstName+" "+lastName);
    console.log("You are cool!")
}

helloFullName("George","Bujoreanu")


const buttonClick = () => {
    document.getElementById("square").classList.add("s-animation");
}


window.onload = () => {
    document.getElementById("button").onclick = buttonClick;
}











