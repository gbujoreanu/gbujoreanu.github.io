const toggleNav = () => {
    document.querySelector(".menu").classList.toggle("active");
  };
  
  window.onload = () => {
    document.getElementById("menuToggle").onclick = toggleNav;
    loadExistingChecklists();
  };