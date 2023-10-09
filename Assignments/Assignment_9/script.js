const cycleQuotes = () => {
    const currentQuote = document.querySelector("#quoteCarousel :not(.hidden)");
    currentQuote.classList.add("hidden");

    let nextQuote = currentQuote.nextElementSibling;

    if (nextQuote == null) {
        nextQuote = document.querySelector("#quoteCarousel :first-child");
    }

    nextQuote.classList.remove("hidden");
}

const renderRainbow = () => {
    const rainbowContainer = document.querySelector("#rainbowOutput");
    const pot = document.getElementById("potOfGold");

    let colors = ["red", "orange", "yellow", "green", "blue", "purple"];
    let position = 0;

    const updateRainbow = setInterval(() => {
        if (position === colors.length) {
            pot.classList.remove("hidden");
            clearInterval(updateRainbow);
        }

        const newColorBand = document.createElement("p");
        newColorBand.classList.add("colorBand");
        newColorBand.style.setProperty("background", colors[position]);

        position++;
        rainbowContainer.append(newColorBand);

    }, 100)
}

window.onload = () => {
    setInterval(cycleQuotes, 2000);
    document.getElementById("rainbowTrigger").onclick = renderRainbow;
}
