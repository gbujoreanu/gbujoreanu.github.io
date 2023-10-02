document.addEventListener("DOMContentLoaded", () => {
    const runningMan = document.getElementById("running-man");
    let isRunning = false;
    let isWalkingImage = true;

   
    function adjustManPosition() {
        let currentMargin = parseInt(getComputedStyle(document.documentElement).getPropertyValue('--man-left-margin'));
        if (currentMargin < window.innerWidth - runningMan.width) {
            currentMargin += 100;  
        } else {
            currentMargin = 0; 
        }
        document.documentElement.style.setProperty('--man-left-margin', currentMargin + 'px');
    }

    runningMan.addEventListener("click", () => {
        if (!isRunning) {
            isRunning = true;
            interval = setInterval(() => {
                adjustManPosition();

                
                runningMan.src = isWalkingImage ? "man-run-frame.png" : "man-walk-frame.png";
                isWalkingImage = !isWalkingImage;
            }, 300);  
        } else {
            isRunning = false;
            clearInterval(interval);
        }
    });

    const donationInput = document.getElementById("donation-input");
    const addDonationButton = document.getElementById("add-donation");
    const fundraisingFill = document.getElementById("fundraising-fill");

    let totalDonation = 0; 

    addDonationButton.addEventListener("click", () => {
        const donationValue = parseInt(donationInput.value);

        if (!isNaN(donationValue)) {
            const clampedValue = Math.min(10000 - totalDonation, Math.max(0, donationValue)); // Limit to $10,000
            totalDonation += clampedValue; 
            const fillPercentage = (totalDonation / 10000) * 100 + "%";
            fundraisingFill.style.height = fillPercentage;
            fundraisingFill.style.backgroundColor = totalDonation === 10000 ? "var(--goal-reached-color)" : "var(--goal-color)";
        }
    });
});
