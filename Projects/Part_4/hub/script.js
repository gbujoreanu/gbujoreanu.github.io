const toggleNav = () => {
    document.querySelector(".menu").classList.toggle("show");
};

window.onload = () => {
    document.getElementById("menuToggle").addEventListener("click", toggleNav);
};
