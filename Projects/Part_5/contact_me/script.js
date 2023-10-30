const logSubmit = () => {
    event.preventDefault();

    const name = document.getElementById("namebox").value;
    const email = document.getElementById("emailbox").value;
    const subject = document.getElementById("subjectbox").value;
    const message = document.getElementById("messagebox").value;

    console.log(name); 
    console.log(email); 
    console.log(subject); 
    console.log(message); 
}

window.onload = () => {
    document.getElementById("nav-toggle").onclick = toggleNav;

    document.getElementById("submit").onclick = logSubmit;
}