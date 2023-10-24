const toggleNav = () => {
    document.querySelector(".menu").classList.toggle("active");
};

window.onload = () => {
    document.getElementById("menuToggle").onclick = toggleNav;
};

document.addEventListener("DOMContentLoaded", function () {
    const createChecklistForm = document.getElementById("create-checklist-form");
    const singleItemInput = document.getElementById("single-item");
    const itemsList = document.getElementById("items-list");
    const existingChecklists = document.getElementById("existing-checklists");
    const itemArray = [];

    createChecklistForm.addEventListener("submit", function (event) {
        event.preventDefault(); // Prevent the form from submitting and refreshing the page

        const checklistName = document.getElementById("checklist-name").value.trim();
        if (checklistName === "") {
            alert("Please enter a checklist name.");
            return;
        }

        if (itemArray.length === 0) {
            alert("Please add items to the checklist.");
            return;
        }

        addNewChecklist(checklistName, itemArray);
        clearForm();
    });

    document.getElementById("add-single-item").addEventListener("click", function (event) {
        event.preventDefault();

        const itemName = singleItemInput.value.trim();
        if (itemName !== "") {
            itemArray.push(itemName);
            addNewItem(itemName);
            singleItemInput.value = "";
        }
    });

    function addNewItem(itemName) {
        const listItem = document.createElement("li");
        listItem.innerHTML = `<input type="checkbox"> ${itemName}`;
        itemsList.appendChild(listItem);
    }

    function clearForm() {
        document.getElementById("checklist-name").value = "";
        singleItemInput.value = "";
        itemsList.innerHTML = "";
        itemArray.length = 0;
    }

    function addNewChecklist(checklistName, items) {
        const checklist = document.createElement("div");
        checklist.classList.add("checklist");
        checklist.innerHTML = `
            <h4>${checklistName} <button class="remove-checklist">Remove</button></h4>
            <ul>
                ${items.map((item) => `<li><input type="checkbox"> ${item}</li>`).join("")}
            </ul>
        `;

        existingChecklists.appendChild(checklist);

        const removeButton = checklist.querySelector(".remove-checklist");

        removeButton.addEventListener("click", function () {
            existingChecklists.removeChild(checklist);
        });
    }
});
