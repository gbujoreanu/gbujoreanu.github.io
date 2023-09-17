const displayImage = () => {
    document.getElementById("image-placeholder").classList.remove("invisible");
}

const concealImage = () => {
    document.getElementById("image-placeholder").classList.add("invisible");
}

const animateBall = () => {
    document.getElementById("animation-ball").classList.add("animate-ball");
}

const displayUserComment = () => {
    document.getElementById("comment-section").classList.add("user-comment");

    const product = document.getElementById("product-input").value;
    const productName = document.getElementById("display-product");
    
    const comment = document.getElementById("comment-input").value;
    const rating = document.getElementById("rating-input").value;
    const commentText = document.getElementById("display-comment");

    const user = document.getElementById("user-input").value;
    const userDisplay = document.getElementById("display-user");

    productName.innerHTML += `<section class="individual-comment"><strong>${product}</strong> <p class="small-text">${rating}/5 stars</p> <p class="small-text">${comment}</p> <p class="small-text">by ${user}</p></section>`;
}

window.onload = () => {
    document.getElementById("show-button").onclick = displayImage;
    document.getElementById("hide-button").onclick = concealImage;
    document.getElementById("dribble-button").onclick = animateBall;
    document.getElementById("submit-button").onclick = displayUserComment;
}