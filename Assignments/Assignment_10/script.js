
class Toy {
    constructor(name, imageFileName, description, price) {
      this.name = name;
      this.imageFileName = imageFileName;
      this.description = description;
      this.price = price;
    }
  
    get details() {
      return `${this.name} - $${this.price}`;
    }
  
    getToyItem() {
      return {
        name: this.name,
        image: this.imageFileName,
        description: this.description,
        price: this.price,
      };
    }
  }
  
  const toys = [
    new Toy("Toy 1", "toy1.png", "Description for Toy 1", 10),
    new Toy("Toy 2", "toy2.jpg", "Description for Toy 2", 15),
    new Toy("Toy 3", "toy3.jpg", "Description for Toy 3", 20),
    new Toy("Toy 4", "toy4.jpg", "Description for Toy 4", 25),
    new Toy("Toy 5", "toy5.jpg", "Description for Toy 5", 30),
    new Toy("Toy 6", "toy6.jpg", "Description for Toy 6", 35),
  ];
  
  const container = document.querySelector('.container');
  const overlay = document.getElementById('overlay');
  const overlayImage = document.getElementById('overlay-image');
  const overlayTitle = document.getElementById('overlay-title');
  const overlayDescription = document.getElementById('overlay-description');
  const overlayPrice = document.getElementById('overlay-price');
  

  function displayToyDetails(toy, toyItem) {
    overlayImage.src = `images/${toy.imageFileName}`;
    overlayTitle.textContent = toy.name;
    overlayDescription.textContent = toy.description;
    overlayPrice.textContent = `$${toy.price}`;
    overlay.style.display = 'block';
  }
  
  function hideToyDetails() {
    overlay.style.display = 'none';
  }
  
  toys.forEach((toy, index) => {
    const toyItem = document.createElement('div');
    toyItem.classList.add('images');
  
    const toyImage = document.createElement('img');
    toyImage.src = `images/${toy.imageFileName}`;
    toyImage.alt = toy.name;
    toyImage.classList.add('img');
  
    toyItem.appendChild(toyImage);
    container.appendChild(toyItem);
  
    toyItem.addEventListener('mouseenter', () => displayToyDetails(toy, toyImage)); // Pass toy and toyImage
    toyItem.addEventListener('mouseleave', hideToyDetails);
  });
  
  