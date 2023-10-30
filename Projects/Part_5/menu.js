const toggleNav = () => {
    document.querySelector(".menu").classList.toggle("active");
};

window.onload = () => {
    const menuToggle = document.getElementById("menuToggle");
    if (menuToggle) {
        menuToggle.onclick = toggleNav;
    }
};
